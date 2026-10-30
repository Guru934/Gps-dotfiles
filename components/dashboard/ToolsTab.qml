import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components.dashboard

// Tools tab: capture actions, wallpaper/theme workflow, system automation and
// the Tide Island clipboard/notification routes.
//
// Every action is explicit: nothing runs on tab creation or render. Capture
// and picker actions are launched detached (scripts/toolkit.sh) so a drawer
// auto-hide can never kill a running slurp/swappy/hyprpicker; their real
// outcome is read back from tools-last on the next open. Short
// actions run as one-shot Process children so success is only reported after
// the command really exits. Destructive actions (suspend, poweroff, shell
// reload, wine kill, cliphist wipe) need two deliberate taps; merely opening
// the tab can never trigger them.
Item {
    id: root
    property bool isOpen: false
    property var hub: null

    readonly property color cardFill: Theme.surfaceBase
    readonly property color tileFill: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.55)
    readonly property color chipFill: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.7)
    readonly property string projectPath: Quickshell.env("HOME") + "/Projects/my-rice"
    readonly property string tidePath: Quickshell.env("HOME") + "/.local/share/tide-island"

    // ----------------------------------------------------------------
    // Feedback strip: last real toolkit outcome (file-read or in-session)
    // ----------------------------------------------------------------
    property string fbText: "READY :: awaiting command"
    property string fbKind: "idle" // idle | info | ok | err
    property real fbTime: 0

    function say(msg, kind) {
        root.fbText = msg
        root.fbKind = kind
        root.fbTime = Date.now() / 1000
    }

    function fmtFbTime() {
        if (root.fbTime <= 0) return "--:--"
        const d = new Date(root.fbTime * 1000)
        function p(n) { return (n < 10 ? "0" : "") + n }
        return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }

    // ----------------------------------------------------------------
    // Two-step confirmations (3.2 s window, any pending state auto-reverts)
    // ----------------------------------------------------------------
    readonly property int confirmWindowMs: 3200
    property string pendingPower: ""
    property bool pendingReload: false
    property bool pendingWipe: false
    property bool pendingKill: false

    function tapConfirm(kind) {
        if (kind === "suspend" || kind === "poweroff") {
            if (root.pendingPower === kind) {
                root.pendingPower = ""
                confirmTimer.stop()
                root.runPower(kind)
            } else {
                root.pendingPower = kind
                confirmTimer.restart()
            }
        } else if (kind === "reload") {
            if (root.pendingReload) {
                root.pendingReload = false
                confirmTimer.stop()
                root.reloadShell()
            } else {
                root.pendingReload = true
                confirmTimer.restart()
            }
        } else if (kind === "wipe") {
            if (root.pendingWipe) {
                root.pendingWipe = false
                confirmTimer.stop()
                root.wipeClipHistory()
            } else {
                root.pendingWipe = true
                confirmTimer.restart()
            }
        } else if (kind === "kill") {
            if (root.pendingKill) {
                root.pendingKill = false
                confirmTimer.stop()
                root.killWine()
            } else {
                root.pendingKill = true
                confirmTimer.restart()
            }
        }
    }

    Timer {
        id: confirmTimer
        interval: root.confirmWindowMs
        repeat: false
        onTriggered: {
            root.pendingPower = ""
            root.pendingReload = false
            root.pendingWipe = false
            root.pendingKill = false
        }
    }

    // ----------------------------------------------------------------
    // Live reads (one-shot on open; wine list refreshes slowly while open)
    // ----------------------------------------------------------------
    property string hyprVersion: ""
    property int histItems: -1
    property int wineProcs: -1
    property bool wineExpectZero: false
    property int killExitCode: -99
    property real themeMtime: 0
    property real themeAfter: -1

    Process {
        id: statusReadProc
        // Lines: status-file mtime, status text, theme-json mtime.
        command: ["sh", "-c", "f=\"$HOME/.config/quickshell/tools-last\"; if [ -f \"$f\" ]; then stat -c %Y \"$f\"; cat \"$f\"; else echo 0; echo; fi; stat -c %Y \"$HOME/.config/quickshell/gps-theme.json\" 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                const stamp = parseFloat(lines[0]) || 0
                const msg = (lines[1] || "").trim()
                const themeStamp = parseFloat(lines[2]) || 0
                if (themeStamp > 0) root.themeMtime = themeStamp
                if (msg !== "" && stamp > root.fbTime) {
                    root.fbText = msg
                    root.fbKind = "info"
                    root.fbTime = stamp
                }
            }
        }
    }

    Process {
        id: verProc
        command: ["sh", "-c", "hyprctl version 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /^Hyprland\s+([\d.]+)/.exec(text.trim())
                root.hyprVersion = m ? m[1] : ""
            }
        }
    }

    Process {
        id: histCountProc
        command: ["sh", "-c", "cliphist list 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.histItems = isNaN(n) ? -1 : n
            }
        }
    }

    Process {
        id: wineCountProc
        command: ["pgrep", "-cf", "wine|wineserver|proton"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.wineProcs = isNaN(n) ? -1 : n
                if (root.wineExpectZero) {
                    root.wineExpectZero = false
                    if (root.killExitCode === 1) root.say("no wine/proton processes were running", "info")
                    else if (root.wineProcs === 0) root.say("wine/proton processes ended", "ok")
                    else if (root.wineProcs > 0) root.say(root.wineProcs + " wine/proton process(es) still running", "err")
                    root.killExitCode = -99
                }
            }
        }
    }

    Timer {
        id: wineTimer
        interval: 8000
        repeat: true
        running: root.isOpen
        onTriggered: if (!wineCountProc.running) wineCountProc.running = true
    }

    function refreshReads() {
        if (!statusReadProc.running) statusReadProc.running = true
        if (!verProc.running) verProc.running = true
        if (!histCountProc.running) histCountProc.running = true
        if (!wineCountProc.running) wineCountProc.running = true
    }

    onIsOpenChanged: {
        if (root.isOpen) root.refreshReads()
    }

    Component.onCompleted: root.refreshReads()

    // ----------------------------------------------------------------
    // Capture actions (detached; validated by scripts/toolkit.sh)
    // ----------------------------------------------------------------
    readonly property string toolkitPath: root.projectPath + "/scripts/toolkit.sh"

    function runTile(key) {
        if (key === "picker") {
            if (root.hub) root.hub.closeDashboard()
            Quickshell.execDetached(["bash", root.toolkitPath, "picker"])
            root.say("picker armed :: click a pixel, esc cancels", "info")
            return
        }
        if (root.hub) root.hub.closeDashboard()
        Quickshell.execDetached(["bash", root.toolkitPath, key])
        if (key === "snip-edit") root.say("snip armed :: select a region", "info")
        else if (key === "snip-copy") root.say("region copy armed :: select a region", "info")
        else if (key === "full-edit") root.say("full-screen capture dispatched", "info")
        else if (key === "full-copy") root.say("full-screen copy dispatched", "info")
    }

    // ----------------------------------------------------------------
    // Wallpaper & theme
    // ----------------------------------------------------------------
    function nextWallpaper() {
        if (!root.hub) return
        root.hub.cycleWallpaper()
        root.say("next wallpaper dispatched (cycle-wall.fish)", "info")
    }

    // Hub-side call (like nextWallpaper): the shell root owns the carousel
    // lifetime, so this survives the synchronous closeDashboard() teardown.
    function openCarousel() {
        if (root.hub) root.hub.toggleWallpaperCarousel()
        if (root.hub) root.hub.closeDashboard()
    }

    Process {
        id: themeProc
        command: ["sh", "-c", "python3 " + root.projectPath + "/scripts/extract-theme.py; stat -c %Y \"$HOME/.config/quickshell/gps-theme.json\" 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const epoch = parseFloat(text.trim().split("\n").pop()) || 0
                root.themeAfter = epoch
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.say("palette: " + text.trim().split("\n")[0], "err")
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                if (root.fbKind !== "err") root.say("palette regeneration failed (exit " + code + ")", "err")
                return
            }
            if (root.themeAfter > root.themeMtime) {
                root.themeMtime = root.themeAfter
                root.say("palette regenerated (hypr border + rofi)", "ok")
            } else if (root.fbKind !== "err") {
                root.say("palette unchanged (no wallpaper?)", "err")
            }
        }
    }

    function regenTheme() {
        themeAfter = -1
        themeProc.running = true
    }

    // ----------------------------------------------------------------
    // Power, reload, wine kill (all confirmed)
    // ----------------------------------------------------------------
    Process {
        id: powerProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.say("power: " + text.trim().split("\n")[0], "err")
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.fbKind !== "err")
                root.say("power command failed (exit " + code + ")", "err")
        }
    }

    function runPower(kind) {
        const cmd = (kind === "suspend") ? "suspend" : "poweroff"
        root.say(cmd + " dispatched to systemd", "info")
        powerProc.command = ["systemctl", cmd]
        powerProc.running = true
    }

    function reloadShell() {
        root.say("reloading shell :: run-gps.fish", "info")
        Quickshell.execDetached([root.projectPath + "/scripts/run-gps.fish"])
    }

    function lockScreen() {
        root.say("locking session :: gps-lock", "info")
        Quickshell.execDetached(["sh", "-c", "command -v gps-lock >/dev/null && exec gps-lock || exec $HOME/Projects/my-rice/scripts/gps-lock"])
    }

    Process {
        id: killProc
        command: ["pkill", "-f", "wine|wineserver|proton"]
        stderr: StdioCollector {}
        onExited: (code, status) => {
            root.killExitCode = code
            root.wineExpectZero = true
            if (!wineCountProc.running) wineCountProc.running = true
        }
    }

    function killWine() {
        killProc.running = true
    }

    // ----------------------------------------------------------------
    // Tide Island: notifications + clipboard
    // ----------------------------------------------------------------
    // Both rows route through Quickshell.execDetached: closeDashboard()
    // unloads this pane synchronously, so instance-scoped Processes started
    // in the same handler would be torn down before their IPC could run.
    function openNotif() {
        Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "--any-display", "-p", root.tidePath, "call", "tide", "toggleNotificationCenter"])
        if (root.hub) root.hub.closeDashboard()
    }

    function openClipHist() {
        Quickshell.execDetached([root.projectPath + "/scripts/gps-ipc", "shell", "clipboard", "toggle"])
        if (root.hub) root.hub.closeDashboard()
    }

    Process {
        id: clearClipProc
        command: ["wl-copy", "--clear"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.say("clipboard: " + text.trim().split("\n")[0], "err")
            }
        }
        onExited: (code, status) => {
            if (code === 0) root.say("clipboard cleared", "ok")
            else if (root.fbKind !== "err") root.say("clipboard clear failed (exit " + code + ")", "err")
        }
    }

    function clearClipboard() {
        clearClipProc.running = true
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") root.say("cliphist: " + text.trim().split("\n")[0], "err")
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.say("clipboard history wiped", "ok")
            } else if (root.fbKind !== "err") {
                root.say("cliphist wipe failed (exit " + code + ")", "err")
            }
            if (!histCountProc.running) histCountProc.running = true
        }
    }

    function wipeClipHistory() {
        wipeProc.running = true
    }

    // ----------------------------------------------------------------
    // Local components (match the sibling tabs' visual language)
    // ----------------------------------------------------------------
    component SectionHead: RowLayout {
        property string icon: ""
        property color tint: Theme.accentPrimary
        property string title: ""
        property string hint: ""
        Layout.fillWidth: true
        spacing: 5

        DashIcon {
            Layout.alignment: Qt.AlignVCenter
            name: parent.icon
            color: parent.tint
            font.pixelSize: 13
        }

        Text {
            Layout.fillWidth: true
            text: parent.title
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 8
            font.bold: true
            font.letterSpacing: 0.8
        }

        Text {
            text: parent.hint
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 7
        }
    }

    component ToolTile: Rectangle {
        id: tile
        required property var modelData
        property bool actionEnabled: !(tile.modelData.disabled === true)
        signal tapped()

        radius: 10
        color: (tileHover.hovered && tile.actionEnabled) ? Theme.surfaceVariant : root.tileFill
        opacity: tile.actionEnabled ? 1.0 : 0.55
        Behavior on color { ColorAnimation { duration: 120 } }

        implicitHeight: 62

        Column {
            anchors.centerIn: parent
            spacing: 3

            Rectangle {
                width: 26
                height: 26
                radius: 13
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(tile.modelData.tint.r, tile.modelData.tint.g, tile.modelData.tint.b, 0.14)

                DashIcon {
                    anchors.centerIn: parent
                    name: tile.modelData.icon
                    color: tile.modelData.tint
                    font.pixelSize: 14
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.modelData.title
                color: (tileHover.hovered && tile.actionEnabled) ? Theme.textMain : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.modelData.sub
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 7
            }
        }

        HoverHandler {
            id: tileHover
            cursorShape: tile.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: tile.actionEnabled
            onTapped: tile.tapped()
        }
    }

    component ToolRow: Rectangle {
        id: row
        property string icon: ""
        property color tint: Theme.accentPrimary
        property string title: ""
        property string sub: ""
        property string trailing: ""
        property bool rowEnabled: true
        property bool confirmActive: false
        property color confirmTint: Theme.statusDanger
        signal tapped()

        radius: 10
        color: (rowHover.hovered && row.rowEnabled) ? Theme.surfaceVariant : root.tileFill
        opacity: row.rowEnabled ? 1.0 : 0.55
        Behavior on color { ColorAnimation { duration: 120 } }
        implicitHeight: 42

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: row.icon
                color: row.rowEnabled ? row.tint : Theme.textDim
                font.pixelSize: 16
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                Text {
                    text: row.confirmActive ? "CONFIRM " + row.title + "?" : row.title
                    color: row.confirmActive ? row.confirmTint : Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    font.bold: true
                }

                Text {
                    text: row.sub
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 7
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: row.trailing
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 8
                font.bold: true
            }
        }

        HoverHandler {
            id: rowHover
            cursorShape: row.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: row.rowEnabled
            onTapped: row.tapped()
        }
    }

    component PowerPill: Rectangle {
        id: pill
        property string icon: ""
        property string label: ""
        property string confirmLabel: ""
        property color tint: Theme.accentPrimary
        property bool confirmActive: false
        signal tapped()

        radius: 15
        color: pill.confirmActive
            ? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.22)
            : (pillHover.hovered ? Theme.surfaceVariant : root.tileFill)
        border.width: 1
        border.color: pill.confirmActive ? pill.tint : Theme.outlineSoft
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        implicitHeight: 32

        RowLayout {
            anchors.centerIn: parent
            spacing: 6

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: pill.icon
                color: pill.tint
                font.pixelSize: 14
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: pill.confirmActive ? pill.confirmLabel : pill.label
                color: pill.confirmActive ? pill.tint : Theme.textMain
                font.family: Theme.fontMono
                font.pixelSize: 9
                font.bold: true
            }
        }

        HoverHandler {
            id: pillHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler { onTapped: pill.tapped() }
    }

    // ----------------------------------------------------------------
    // Layout
    // ----------------------------------------------------------------
    Flickable {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.implicitHeight

        ColumnLayout {
            id: content
            width: parent.width
            spacing: 10

            // HUD header row: section label + real runtime chip.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "HUD // TOOLKIT"
                    color: Theme.accentPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 1
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: hyprChip.implicitWidth + 12
                    implicitHeight: 16
                    radius: 8
                    color: root.chipFill

                    Text {
                        id: hyprChip
                        anchors.centerIn: parent
                        text: "HYPRLAND " + (root.hyprVersion !== "" ? root.hyprVersion : "\u2026")
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 7
                    }
                }
            }

            // ---------- Capture & tools ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: captureCol.implicitHeight + 20

                ColumnLayout {
                    id: captureCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    SectionHead {
                        icon: "crop_free"
                        tint: Theme.accentPrimary
                        title: "CAPTURE & TOOLS"
                        hint: "GRIM // SLURP // SWAPPY"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 6
                        rowSpacing: 6

                        Repeater {
                            model: [
                                { key: "snip-edit", icon: "crop_free", tint: Theme.accentPrimary, title: "SNIP REGION", sub: "grim + slurp \u2192 swappy" },
                                { key: "snip-copy", icon: "content_copy", tint: Theme.accentSecondary, title: "COPY REGION", sub: "grim + slurp \u2192 wl-copy" },
                                { key: "full-edit", icon: "fullscreen", tint: Theme.accentTertiary, title: "FULL SCREEN", sub: "grim \u2192 swappy" },
                                { key: "picker", icon: "colorize", tint: Theme.accentPrimary, title: "COLOR PICKER", sub: "hyprpicker \u2192 wl-copy" }
                            ]

                            ToolTile {
                                Layout.fillWidth: true
                                onTapped: root.runTile(modelData.key)
                            }
                        }
                    }
                }
            }

            // ---------- Wallpaper & theme ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: wallCol.implicitHeight + 20

                ColumnLayout {
                    id: wallCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    SectionHead {
                        icon: "wallpaper"
                        tint: Theme.accentSecondary
                        title: "WALLPAPER & THEME"
                        hint: "AWWW // EXTRACT-THEME"
                    }

                    ToolRow {
                        Layout.fillWidth: true
                        icon: "navigate_next"
                        tint: Theme.accentSecondary
                        title: "NEXT WALLPAPER"
                        sub: "cycle-wall.fish \u00b7 applies + refreshes palette"
                        trailing: "\u2192"
                        onTapped: root.nextWallpaper()
                    }

                    ToolRow {
                        Layout.fillWidth: true
                        icon: "wallpaper"
                        tint: Theme.accentPrimary
                        title: "WALLPAPER CAROUSEL"
                        sub: "in-shell picker \u00b7 arrows + enter"
                        trailing: "SUPER+W"
                        onTapped: root.openCarousel()
                    }

                    ToolRow {
                        Layout.fillWidth: true
                        icon: "palette"
                        tint: Theme.accentTertiary
                        title: "REGENERATE PALETTE"
                        sub: "extract-theme.py \u00b7 hypr border + rofi only"
                        trailing: "RUN"
                        onTapped: root.regenTheme()
                    }
                }
            }

            // ---------- Automation & power ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: autoCol.implicitHeight + 20

                ColumnLayout {
                    id: autoCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    SectionHead {
                        icon: "bolt"
                        tint: Theme.statusWarn
                        title: "AUTOMATION & POWER"
                        hint: "SYSTEMD // LOGINCTL"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 6
                        rowSpacing: 6

                        ToolTile {
                            Layout.fillWidth: true
                            modelData: {
                                return {
                                    icon: "nightlight",
                                    tint: Theme.accentTertiary,
                                    title: "NIGHT WARMTH",
                                    sub: "unavailable \u00b7 no hyprsunset",
                                    disabled: true
                                }
                            }
                        }

                        ToolTile {
                            Layout.fillWidth: true
                            modelData: {
                                return {
                                    icon: "sports_esports",
                                    tint: Theme.statusDanger,
                                    title: root.pendingKill ? "CONFIRM KILL" : "END WINE / PROTON",
                                    sub: root.wineProcs > 0
                                        ? (root.wineProcs + " process(es) running")
                                        : (root.wineProcs === 0 ? "none running" : "probing\u2026"),
                                    disabled: root.wineProcs <= 0
                                }
                            }
                            onTapped: root.tapConfirm("kill")
                        }

                        ToolTile {
                            Layout.fillWidth: true
                            modelData: {
                                return {
                                    icon: "lock",
                                    tint: Theme.accentPrimary,
                                    title: "LOCK SCREEN",
                                    sub: "hyprlock \u00b7 password + face"
                                }
                            }
                            onTapped: root.lockScreen()
                        }

                        ToolTile {
                            Layout.fillWidth: true
                            modelData: {
                                return {
                                    icon: "cycle",
                                    tint: Theme.accentPrimary,
                                    title: root.pendingReload ? "CONFIRM RELOAD" : "RELOAD SHELL",
                                    sub: "run-gps.fish \u00b7 keeps Tide Island"
                                }
                            }
                            onTapped: root.tapConfirm("reload")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        PowerPill {
                            Layout.fillWidth: true
                            icon: "bedtime"
                            label: "SUSPEND"
                            confirmLabel: "CONFIRM SUSPEND"
                            tint: Theme.statusWarn
                            confirmActive: root.pendingPower === "suspend"
                            onTapped: root.tapConfirm("suspend")
                        }

                        PowerPill {
                            Layout.fillWidth: true
                            icon: "power_settings_new"
                            label: "SHUT DOWN"
                            confirmLabel: "CONFIRM SHUTDOWN"
                            tint: Theme.statusDanger
                            confirmActive: root.pendingPower === "poweroff"
                            onTapped: root.tapConfirm("poweroff")
                        }
                    }
                }
            }

            // ---------- Tide Island: notifications & clipboard ----------
            DashSurface {
                Layout.fillWidth: true
                fill: root.cardFill
                radius: 14
                implicitHeight: tideCol.implicitHeight + 20

                ColumnLayout {
                    id: tideCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    SectionHead {
                        icon: "notifications"
                        tint: Theme.accentPrimary
                        title: "TIDE ISLAND // CLIPBOARD"
                        hint: "WL-CLIPBOARD // CLIPHIST"
                    }

                    ToolRow {
                        Layout.fillWidth: true
                        icon: "notifications"
                        tint: Theme.accentTertiary
                        title: "NOTIFICATION CENTER"
                        sub: "tide stays the D-Bus notification owner"
                        trailing: "OPEN"
                        onTapped: root.openNotif()
                    }

                    ToolRow {
                        Layout.fillWidth: true
                        icon: "content_paste"
                        tint: Theme.accentPrimary
                        title: "CLIPBOARD HISTORY"
                        sub: root.histItems >= 0
                            ? (root.histItems + " item(s) stored")
                            : "open clipboard picker"
                        trailing: "OPEN"
                        onTapped: root.openClipHist()
                    }
                }
            }

            // ---------- Feedback strip ----------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Theme.radiusControl
                color: root.chipFill
                border.width: 1
                border.color: {
                    if (root.fbKind === "ok") return Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.5)
                    if (root.fbKind === "err") return Qt.rgba(Theme.statusDanger.r, Theme.statusDanger.g, Theme.statusDanger.b, 0.5)
                    return Theme.outlineSoft
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    DashIcon {
                        Layout.alignment: Qt.AlignVCenter
                        name: root.fbKind === "ok" ? "check_circle" : (root.fbKind === "err" ? "error" : "info")
                        color: root.fbKind === "ok" ? Theme.accentPrimary : (root.fbKind === "err" ? Theme.statusDanger : Theme.textMuted)
                        font.pixelSize: 13
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.fbText
                        color: root.fbKind === "err" ? Theme.statusDanger : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.fmtFbTime()
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 7
                    }
                }
            }
        }
    }
}
