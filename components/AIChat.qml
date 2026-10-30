import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// AETHERIC NEURAL CHAT — local-only AI panel (design_refs/ai-chat.html).
//
// Backend: scripts/ai-chat.py -> Ollama at 127.0.0.1:11434. Streaming is read
// as NDJSON from the helper's stdout; prompts never leave the machine and are
// never persisted (history lives in memory for the lifetime of the shell).
//
// Conversation state is deliberately ephemeral: closing the panel keeps the
// thread for the session, clearing the chat discards it permanently.
PanelWindow {
    id: root

    property var hub: null
    property bool isOpen: false

    readonly property string projectPath: Quickshell.env("HOME") + "/Projects/my-rice"
    readonly property string bridgePath: projectPath + "/scripts/ai-chat.py"
    readonly property string storePath: Quickshell.env("HOME") + "/.config/quickshell/rice-settings.json"
    readonly property int maxHistoryChars: 20000
    readonly property string defaultPersona: "You are Aetheric Neural Chat, the local assistant built into the user's Linux desktop shell. Be concise, technical and honest. Never pretend to run commands."

    // Assistant defaults are shared with the Settings Hub through
    // rice-settings.json ("ai" object). The hub is the single source of truth:
    // this panel applies changes live, and picking a model in the panel's
    // dropdown writes the choice back so both stay in sync.
    property string desiredModel: ""
    property int numCtx: 8192
    property real temperature: 0.7
    property string persona: defaultPersona

    // Design palette: binds to Theme tokens with design defaults as fallback
    readonly property color cSurface: Theme.surfaceDeep !== undefined ? Theme.surfaceDeep : "#0F131C"
    readonly property color cLowest: "#0A0E17"
    readonly property color cLow: Theme.surfaceBase !== undefined ? Theme.surfaceBase : "#181B25"
    readonly property color cContainer: Theme.card !== undefined ? Theme.card : "#1C1F29"
    readonly property color cHigh: Theme.surfaceHigh !== undefined ? Theme.surfaceHigh : "#262A34"
    readonly property color cVariant: Theme.surfaceVariant !== undefined ? Theme.surfaceVariant : "#31353F"
    readonly property color cPri: Theme.brandAccent !== undefined ? Theme.brandAccent : "#57F1DB"
    readonly property color cSec: Theme.accentSecondary !== undefined ? Theme.accentSecondary : "#DDB8FF"
    readonly property color cTer: Theme.accentTertiary !== undefined ? Theme.accentTertiary : "#FFD47B"
    readonly property color cText: Theme.textMain !== undefined ? Theme.textMain : "#DFE2EF"
    readonly property color cMuted: Theme.textMuted !== undefined ? Theme.textMuted : "#BACAC5"
    readonly property color cOnPri: Theme.brandAccentFg !== undefined ? Theme.brandAccentFg : "#003731"
    readonly property color cErr: Theme.statusDanger !== undefined ? Theme.statusDanger : "#FFB4AB"
    readonly property color cErrBg: "#93000A"

    // Backend state
    property var models: []
    property string selectedModel: ""
    property string backendState: "idle" // idle | ok | offline
    property string backendMessage: ""
    property string vramText: ""
    property string hostName: ""
    property string pendingSend: ""

    // Conversation state
    property bool streaming: false
    property bool stoppedByUser: false
    property real streamStart: 0
    property real firstTokenAt: 0
    property real lastTps: 0
    property int tokensUsed: 0

    // UI state
    property bool showMetrics: true
    property bool clearArmed: false
    property bool dropdownOpen: false
    readonly property string userName: Quickshell.env("USER") || "user"

    function open() {
        if (root.isOpen) return
        if (root.hub) {
            root.hub.closePopup()
            root.hub.closeDashboard()
            root.hub.closeWallpaperCarousel()
        }
        root.isOpen = true
        root.refreshModels()
        root.refreshVram()
        vramTimer.restart()
        Qt.callLater(() => {
            if (promptArea) promptArea.forceActiveFocus()
            root.scrollToEnd()
        })
    }
    function close() {
        root.dropdownOpen = false
        root.isOpen = false
        vramTimer.stop()
    }
    function toggle() { root.isOpen ? root.close() : root.open() }

    function nowHM() {
        const d = new Date()
        function pad(n) { return (n < 10 ? "0" : "") + n }
        return pad(d.getHours()) + ":" + pad(d.getMinutes())
    }
    function fmtSize(bytes) {
        if (!bytes) return ""
        return (bytes / 1073741824).toFixed(1) + " GB"
    }
    function fmtTps(v) { return v > 0 ? v.toFixed(1) + " t/s" : "" }

    function refreshModels() {
        if (!modelsProc.running) modelsProc.running = true
    }
    function refreshVram() {
        if (!vramProc.running) vramProc.running = true
    }

    // Apply the Settings Hub assistant defaults (model / ctx / temperature /
    // system prompt). Called on load and whenever rice-settings.json changes.
    function applyAiStore() {
        let d = {}
        try { d = JSON.parse(storeView.text()) } catch (_) { return }
        const ai = d.ai || {}
        const m = (typeof ai.model === "string" ? ai.model : "").trim()
        root.desiredModel = m
        if (m !== "" && root.models.some(x => x.name === m)) root.selectedModel = m
        const c = parseInt(ai.ctx)
        if (c >= 2048 && c <= 32768) root.numCtx = c
        const t = parseFloat(ai.temp)
        if (!isNaN(t) && t >= 0 && t <= 1.5) root.temperature = t
        root.persona = (typeof ai.system === "string" && ai.system.trim() !== "") ? ai.system : root.defaultPersona
    }

    function persistModelChoice(name) {
        Quickshell.execDetached(["python3", "-c",
            "import json, os, sys, tempfile\n" +
            "p = sys.argv[1]; n = sys.argv[2]; d = {}\n" +
            "if os.path.isfile(p):\n" +
            "    try:\n" +
            "        with open(p, 'r', encoding='utf-8') as f:\n" +
            "            content = f.read().strip()\n" +
            "            if content: d = json.loads(content)\n" +
            "    except Exception: pass\n" +
            "if not isinstance(d, dict): d = {}\n" +
            "ai = d.setdefault('ai', {})\n" +
            "if isinstance(ai, dict): ai['model'] = n\n" +
            "d_dir = os.path.dirname(p)\n" +
            "os.makedirs(d_dir, exist_ok=True)\n" +
            "fd, tmp = tempfile.mkstemp(dir=d_dir, prefix='.rice-settings.tmp-')\n" +
            "with os.fdopen(fd, 'w', encoding='utf-8') as f:\n" +
            "    json.dump(d, f, indent=2)\n" +
            "    f.flush()\n" +
            "    os.fsync(f.fileno())\n" +
            "os.replace(tmp, p)",
            root.storePath, name])
    }

    function pickModel(name) {
        root.selectedModel = name
        root.persistModelChoice(name)
        root.dropdownOpen = false
    }

    function scrollToEnd() {
        Qt.callLater(() => {
            if (messages.count > 0) streamView.positionViewAtEnd()
        })
    }

    function handleLine(line) {
        let e
        try { e = JSON.parse(line) } catch (_) { return }
        if (e.type === "models") {
            root.models = e.models || []
            root.backendState = "ok"
            root.backendMessage = ""
            const has = root.models.some(m => m.name === root.selectedModel)
            if (!has) {
                const wanted = root.models.find(m => m.name === root.desiredModel)
                root.selectedModel = wanted ? wanted.name : (root.models.length > 0 ? root.models[0].name : "")
            }
            if (root.pendingSend !== "") {
                const queued = root.pendingSend
                root.pendingSend = ""
                root.send(queued, false)
            }
        } else if (e.type === "chunk") {
            if (root.firstTokenAt === 0) root.firstTokenAt = Date.now()
            const last = messages.count - 1
            if (last < 0) return
            messages.setProperty(last, "text", messages.get(last).text + e.content)
            root.scrollToEnd()
        } else if (e.type === "done") {
            const last = messages.count - 1
            const evalSec = (e.eval_ns || 0) / 1e9
            const tps = evalSec > 0 ? (e.output_tokens || 0) / evalSec : 0
            if (last >= 0) {
                messages.setProperty(last, "streaming", false)
                messages.setProperty(last, "ttftMs", root.firstTokenAt > 0 ? (root.firstTokenAt - root.streamStart) : 0)
                messages.setProperty(last, "tps", tps)
                messages.setProperty(last, "promptTok", e.prompt_tokens || 0)
                messages.setProperty(last, "outTok", e.output_tokens || 0)
                messages.setProperty(last, "totalMs", (e.total_ns || 0) / 1e6)
            }
            root.lastTps = tps
            root.tokensUsed = (e.prompt_tokens || 0) + (e.output_tokens || 0)
            root.streaming = false
            root.backendState = "ok"
            root.scrollToEnd()
        } else if (e.type === "offline") {
            root.backendState = "offline"
            root.backendMessage = e.message || "Ollama unreachable"
            const last = messages.count - 1
            if (last >= 0 && messages.get(last).kind === "assistant" && messages.get(last).text === "") {
                messages.setProperty(last, "streaming", false)
                messages.setProperty(last, "error", "Ollama is offline. Start it with: systemctl --user start ollama")
            }
            root.streaming = false
        } else if (e.type === "error") {
            const last = messages.count - 1
            if (last >= 0) {
                messages.setProperty(last, "streaming", false)
                if (messages.get(last).text === "" || messages.get(last).error !== "")
                    messages.setProperty(last, "error", e.message || "request failed")
            }
            root.streaming = false
        }
    }

    function buildHistory() {
        const out = [{ role: "system", content: root.persona }]
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i)
            if (m.kind !== "user" && m.kind !== "assistant") continue
            if (!m.text || m.text.trim() === "") continue
            if (m.error && m.error !== "") continue
            out.push({ role: m.kind, content: m.text })
        }
        let total = out.reduce((acc, m) => acc + m.content.length, 0)
        while (total > root.maxHistoryChars && out.length > 3) {
            const removed = out.splice(1, 1)[0]
            total -= removed.content.length
        }
        return out
    }

    function send(text, regenerate) {
        const t = (text || "").trim()
        if (t === "" || root.streaming) return
        if (root.backendState !== "ok") {
            root.open()
            root.refreshModels()
            if (root.backendState === "offline") return
        }
        if (root.selectedModel === "") {
            root.pendingSend = t
            root.refreshModels()
            return
        }
        if (!regenerate) {
            messages.append({
                kind: "user", text: t, model: "", streaming: false, error: "",
                stopped: false, ttftMs: 0, tps: 0, promptTok: 0, outTok: 0,
                totalMs: 0, timeLabel: root.nowHM()
            })
            promptArea.text = ""
        }
        const history = root.buildHistory()
        messages.append({
            kind: "assistant", text: "", model: root.selectedModel,
            streaming: true, error: "", stopped: false, ttftMs: 0, tps: 0,
            promptTok: 0, outTok: 0, totalMs: 0, timeLabel: ""
        })
        root.streaming = true
        root.stoppedByUser = false
        root.streamStart = Date.now()
        root.firstTokenAt = 0
        root.scrollToEnd()
        chatProc.pendingPayload = JSON.stringify({
            model: root.selectedModel,
            messages: history,
            num_ctx: root.numCtx,
            temperature: root.temperature
        }) + "\n"
        chatProc.running = true
    }

    function submit(text) { root.open(); root.send(text, false) }

    function stopGeneration() {
        if (!root.streaming) return
        root.stoppedByUser = true
        chatProc.running = false
    }

    function regenerate() {
        if (root.streaming || messages.count === 0) return
        const last = messages.count - 1
        if (messages.get(last).kind !== "assistant") return
        messages.remove(last)
        let userText = ""
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).kind === "user") { userText = messages.get(i).text; break }
        }
        if (userText !== "") root.send(userText, true)
    }

    function clearNow() {
        root.clearArmed = false
        clearResetTimer.stop()
        messages.clear()
        root.tokensUsed = 0
        root.lastTps = 0
        root.dropdownOpen = false
        promptArea.text = ""
    }

    function clearConversation() {
        if (!root.clearArmed) {
            root.clearArmed = true
            clearResetTimer.restart()
            return
        }
        root.clearNow()
    }

    function openDropdown() {
        if (root.models.length === 0) { root.refreshModels(); return }
        const p = modelPill.mapToItem(panel, 0, 0)
        root.dropdownX = Math.round(p.x)
        root.dropdownY = Math.round(p.y + modelPill.height + 6)
        root.dropdownOpen = !root.dropdownOpen
    }
    property real dropdownX: 18
    property real dropdownY: 120

    function segmentsFor(text) {
        const out = []
        const re = /```([\w+-]*)\n?([\s\S]*?)```/g
        let last = 0
        let m
        while ((m = re.exec(text)) !== null) {
            if (m.index > last) out.push({ kind: "text", text: text.slice(last, m.index) })
            out.push({ kind: "code", lang: (m[1] || "code"), text: m[2] })
            last = m.index + m[0].length
        }
        if (last < text.length) out.push({ kind: "text", text: text.slice(last) })
        return out
    }

    anchors { top: true }
    margins { top: 80 }
    implicitWidth: 860
    implicitHeight: 680
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Shortcut {
        sequence: "Escape"
        enabled: root.isOpen
        context: Qt.ApplicationShortcut
        onActivated: root.close()
    }

    ListModel { id: messages }

    FileView {
        id: storeView
        path: root.storePath
        watchChanges: true
        onLoaded: root.applyAiStore()
        onFileChanged: reload()
    }

    Process {
        id: modelsProc
        command: ["python3", root.bridgePath, "--list-models"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim()
                if (text !== "") root.handleLine(text.split("\n")[0])
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.backendState !== "offline") {
                root.backendState = "offline"
                root.backendMessage = "Ollama unreachable at 127.0.0.1:11434"
            }
        }
    }

    Process {
        id: chatProc
        command: ["python3", root.bridgePath]
        stdinEnabled: true
        property string pendingPayload: ""
        onStarted: {
            if (pendingPayload !== "") {
                write(pendingPayload)
                pendingPayload = ""
            }
        }
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onExited: (code, status) => {
            pendingPayload = ""
            if (root.streaming) {
                root.streaming = false
                const last = messages.count - 1
                if (last >= 0) {
                    messages.setProperty(last, "streaming", false)
                    if (root.stoppedByUser) {
                        messages.setProperty(last, "stopped", true)
                    } else if (messages.get(last).text === "" && messages.get(last).error === "") {
                        messages.setProperty(last, "error", "stream ended without a response")
                    }
                }
                root.stoppedByUser = false
            }
        }
    }

    Process {
        id: vramProc
        command: ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(",")
                if (parts.length !== 2) { root.vramText = ""; return }
                const used = parseFloat(parts[0]) / 1024
                const total = parseFloat(parts[1]) / 1024
                if (isNaN(used) || isNaN(total)) { root.vramText = ""; return }
                root.vramText = "VRAM " + used.toFixed(1) + "GB/" + total.toFixed(0) + "GB"
            }
        }
    }

    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector {
            onStreamFinished: root.hostName = this.text.trim()
        }
        Component.onCompleted: running = true
    }

    Timer {
        id: clearResetTimer
        interval: 3200
        onTriggered: root.clearArmed = false
    }
    Timer {
        id: vramTimer
        interval: 5000
        repeat: true
        running: false
        onTriggered: root.refreshVram()
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(15 / 255, 19 / 255, 28 / 255, 0.94)
        border.width: 1
        border.color: Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.22)

        FocusScope {
            id: focusRoot
            anchors.fill: parent

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                }
            }

            // ============================ HEADER ============================
            Rectangle {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: headerCol.implicitHeight + 28
                topLeftRadius: 18
                topRightRadius: 18
                color: Qt.rgba(10 / 255, 14 / 255, 23 / 255, 0.82)

                Column {
                    id: headerCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 14
                    spacing: 9

                    RowLayout {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.15)
                            Text {
                                anchors.centerIn: parent
                                text: "\u{F06A9}"
                                font.family: Theme.fontMono
                                font.pixelSize: 17
                                color: root.cPri
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            Row {
                                spacing: 8
                                Text {
                                    text: "AETHERIC NEURAL CHAT"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.letterSpacing: 0.3
                                    color: root.cText
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: versionText.implicitWidth + 10
                                    height: 15
                                    radius: 7
                                    color: root.cHigh
                                    Text {
                                        id: versionText
                                        anchors.centerIn: parent
                                        text: "v0.9"
                                        font.family: Theme.fontMono
                                        font.pixelSize: 8
                                        color: root.cPri
                                    }
                                }
                            }

                            Row {
                                spacing: 6
                                Rectangle {
                                    id: statusDot
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: 3
                                    color: root.backendState === "ok" ? root.cPri
                                         : (root.backendState === "offline" ? root.cErr : root.cMuted)

                                    SequentialAnimation on opacity {
                                        running: root.backendState === "ok"
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.35; duration: 900 }
                                        NumberAnimation { from: 0.35; to: 1; duration: 900 }
                                    }
                                }
                                Text {
                                    text: {
                                        let s = "aetheric // local llm"
                                        if (root.backendState === "offline") s += " offline"
                                        else if (root.backendState === "ok") s += " active"
                                        else s += " connecting\u2026"
                                        s += " \u2022 ollama:11434"
                                        if (root.lastTps > 0) s += " \u2022 " + root.lastTps.toFixed(1) + " t/s"
                                        return s
                                    }
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    color: root.cMuted
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6
                            IconBtn {
                                glyph: "\u{F01B4}"
                                tint: root.clearArmed ? root.cErr : root.cMuted
                                tooltipText: root.clearArmed ? "Tap again to clear" : "Clear conversation"
                                onClicked: root.clearConversation()
                            }
                            IconBtn {
                                glyph: "\u{F012A}"
                                tint: root.showMetrics ? root.cPri : root.cMuted
                                tooltipText: "Toggle inference telemetry"
                                onClicked: root.showMetrics = !root.showMetrics
                            }
                            IconBtn {
                                glyph: "\u{F0156}"
                                tint: root.cMuted
                                tooltipText: "Close (Esc)"
                                onClicked: root.close()
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            id: modelPill
                            height: 26
                            width: modelRow.implicitWidth + 24
                            radius: 13
                            color: modelHover.hovered ? root.cVariant : root.cContainer

                            Row {
                                id: modelRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "\u{F035B}"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                    color: root.cPri
                                }
                                Text {
                                    text: root.selectedModel !== "" ? root.selectedModel : "no model"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: root.cPri
                                }
                                Text {
                                    text: "\u25BE"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    color: root.cMuted
                                }
                            }

                            HoverHandler { id: modelHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.openDropdown() }
                        }

                        Rectangle {
                            visible: root.vramText !== ""
                            height: 26
                            width: vramTextItem.implicitWidth + 20
                            radius: 13
                            color: root.cLow
                            Text {
                                id: vramTextItem
                                anchors.centerIn: parent
                                text: root.vramText
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                color: root.cMuted
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 24
                            width: personaText.implicitWidth + 24
                            radius: 12
                            color: Qt.rgba(98 / 255, 37 / 255, 155 / 255, 0.30)
                            Text {
                                id: personaText
                                anchors.centerIn: parent
                                text: "// Hyprland Rice Architect & Linux Systems"
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                color: root.cSec
                            }
                        }
                    }
                }
            }

            // ========================= CHAT STREAM =========================
            ListView {
                id: streamView
                anchors {
                    top: header.bottom
                    left: parent.left
                    right: parent.right
                    bottom: offlineBanner.visible ? offlineBanner.top : inputBar.top
                }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 14
                topMargin: 12
                bottomMargin: 12
                leftMargin: 18
                rightMargin: 18
                model: messages
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                header: Item {
                    width: streamView.width - 36
                    height: messages.count > 0 ? 28 : 0
                    visible: messages.count > 0

                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle { width: (streamView.width - 360) / 2; height: 1; color: Qt.rgba(49 / 255, 53 / 255, 63 / 255, 0.5); anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "TODAY \u2022 LOCAL SESSION"
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            font.letterSpacing: 2
                            color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.7)
                        }
                        Rectangle { width: (streamView.width - 360) / 2; height: 1; color: Qt.rgba(49 / 255, 53 / 255, 63 / 255, 0.5); anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                delegate: MessageRow {}
            }

            // Empty state
            Item {
                anchors.fill: streamView
                visible: messages.count === 0

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 120
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\u{F09D1}"
                        font.family: Theme.fontMono
                        font.pixelSize: 34
                        color: Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.55)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "LOCAL INFERENCE READY"
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 2.4
                        color: root.cText
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.selectedModel !== "" ? root.selectedModel : "no model") + " \u00b7 " + root.numCtx + " ctx \u00b7 loopback only"
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: root.cMuted
                    }
                    Item { width: 1; height: 6 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        ChipButton { label: "Explain this shell"; onClicked: { promptArea.text = "Explain what this desktop shell is capable of."; promptArea.forceActiveFocus() } }
                        ChipButton { label: "Draft a keybind"; onClicked: { promptArea.text = "Write a Hyprland Lua keybind that opens a scratchpad terminal."; promptArea.forceActiveFocus() } }
                        ChipButton { label: "Local LLM tradeoffs"; onClicked: { promptArea.text = "Summarize the tradeoffs of running LLMs locally versus in the cloud."; promptArea.forceActiveFocus() } }
                    }
                }
            }

            // Offline / error banner
            Rectangle {
                id: offlineBanner
                visible: root.backendState === "offline"
                anchors { left: parent.left; right: parent.right; bottom: inputBar.top }
                height: visible ? 30 : 0
                color: Qt.rgba(147 / 255, 0 / 255, 10 / 255, 0.28)

                Row {
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Text {
                        text: "OLLAMA OFFLINE"
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        font.bold: true
                        color: root.cErr
                    }
                    Text {
                        text: root.backendMessage !== "" ? root.backendMessage : "systemctl --user start ollama"
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        color: Qt.rgba(255 / 255, 180 / 255, 171 / 255, 0.75)
                        elide: Text.ElideRight
                        width: offlineBanner.width - 280
                    }
                }
                ChipButton {
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    label: "RETRY"
                    accent: root.cErr
                    onClicked: root.refreshModels()
                }
            }

            // ========================= BOTTOM BAR =========================
            Rectangle {
                id: inputBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: inputCol.implicitHeight + 26
                bottomLeftRadius: 18
                bottomRightRadius: 18
                color: Qt.rgba(10 / 255, 14 / 255, 23 / 255, 0.9)

                Column {
                    id: inputCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 12
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            height: 22
                            width: ctxText.implicitWidth + 24
                            radius: 11
                            color: root.cContainer
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Rectangle {
                                    width: 5; height: 5; radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.backendState === "ok" ? root.cPri : root.cMuted
                                }
                                Text {
                                    id: ctxText
                                    text: "Context: " + root.numCtx + " tokens"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    color: root.cMuted
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 22
                            width: tokensText.implicitWidth + 24
                            radius: 11
                            color: root.cContainer
                            Text {
                                id: tokensText
                                anchors.centerIn: parent
                                text: "Tokens: " + root.tokensUsed + " / " + root.numCtx
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                color: root.cMuted
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(112, promptArea.implicitHeight) + 16
                        radius: 14
                        color: promptArea.activeFocus ? root.cHigh : root.cContainer

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 7; topMargin: 7; bottomMargin: 7 }
                            spacing: 8

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                ScrollBar.vertical: ScrollBar {
                                    width: 4
                                    policy: ScrollBar.AsNeeded
                                    contentItem: Rectangle { radius: 2; color: root.cVariant }
                                }

                                TextArea {
                                    id: promptArea
                                    placeholderText: "Ask your local model anything\u2026"
                                    placeholderTextColor: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.5)
                                    color: root.cText
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    wrapMode: TextArea.Wrap
                                    selectByMouse: true
                                    background: null
                                    topPadding: 2
                                    bottomPadding: 2

                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Escape) {
                                            root.close()
                                            event.accepted = true
                                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                                   && !(event.modifiers & Qt.ShiftModifier)) {
                                            root.send(promptArea.text, false)
                                            event.accepted = true
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignBottom
                                width: 36
                                height: 36
                                radius: 18
                                color: root.streaming ? root.cVariant
                                     : (root.sendReady ? root.cPri : Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.25))

                                Text {
                                    anchors.centerIn: parent
                                    text: root.streaming ? "\u25A0" : "\u2191"
                                    font.family: Theme.fontMono
                                    font.pixelSize: root.streaming ? 12 : 16
                                    font.bold: true
                                    color: root.streaming ? root.cText : root.cOnPri
                                }

                                HoverHandler {
                                    cursorShape: (root.streaming || root.sendReady) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                                TapHandler {
                                    enabled: root.streaming || root.sendReady
                                    onTapped: {
                                        if (root.streaming) root.stopGeneration()
                                        else root.send(promptArea.text, false)
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Row {
                            spacing: 6
                            KbdHint { label: "RETURN" }
                            Text { text: "to send"; font.family: Theme.fontMono; font.pixelSize: 8; color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.55); anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "\u2022"; font.family: Theme.fontMono; font.pixelSize: 8; color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.35); anchors.verticalCenter: parent.verticalCenter }
                            KbdHint { label: "SHIFT+RETURN" }
                            Text { text: "for newline"; font.family: Theme.fontMono; font.pixelSize: 8; color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.55); anchors.verticalCenter: parent.verticalCenter }
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 6
                            Text {
                                text: "BACKEND:"
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                font.letterSpacing: 1.5
                                color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.55)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.backendState === "ok" ? "OLLAMA (ACTIVE)"
                                     : (root.backendState === "offline" ? "OLLAMA (OFFLINE)" : "OLLAMA (CONNECTING)")
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                font.bold: true
                                color: root.backendState === "ok" ? root.cPri : root.cErr
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "\u2022 127.0.0.1:11434"
                                font.family: Theme.fontMono
                                font.pixelSize: 8
                                color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.4)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ===================== MODEL DROPDOWN (overlay) =====================
            Rectangle {
                id: modelDropdown
                visible: root.dropdownOpen
                z: 90
                x: root.dropdownX
                y: root.dropdownY
                width: 300
                height: dropdownCol.implicitHeight + 12
                radius: 12
                color: Qt.rgba(38 / 255, 42 / 255, 52 / 255, 0.97)
                border.width: 1
                border.color: root.cVariant

                Column {
                    id: dropdownCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.margins: 6
                    spacing: 2

                    Text {
                        text: "AVAILABLE LOCAL MODELS"
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        font.letterSpacing: 1.5
                        color: root.cMuted
                        leftPadding: 6
                        topPadding: 2
                        bottomPadding: 4
                    }

                    Repeater {
                        model: root.models

                        Rectangle {
                            required property var modelData
                            width: dropdownCol.width
                            height: 40
                            radius: 8
                            color: itemHover.hovered ? root.cHigh
                                 : (modelData.name === root.selectedModel ? Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.10) : "transparent")

                            Column {
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text {
                                    text: modelData.name
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: modelData.name === root.selectedModel ? root.cPri : root.cText
                                }
                                Text {
                                    text: "ollama \u00b7 local nvme \u00b7 " + root.fmtSize(modelData.size)
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    color: root.cMuted
                                }
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: modelData.name === root.selectedModel ? "\u2713" : ""
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                color: root.cPri
                            }

                            HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: root.pickModel(modelData.name)
                            }
                        }
                    }

                    Text {
                        visible: root.models.length === 0
                        text: root.backendState === "offline" ? "Ollama offline" : "Refreshing\u2026"
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: root.cMuted
                        leftPadding: 6
                        bottomPadding: 4
                    }
                }
            }

            // Click-catcher so the dropdown closes on outside clicks.
            MouseArea {
                anchors.fill: parent
                z: 80
                visible: root.dropdownOpen
                onClicked: root.dropdownOpen = false
            }
        }
    }

    readonly property bool sendReady: promptArea !== null && promptArea.text.trim() !== "" && root.backendState === "ok"

    // ============================ COMPONENTS ============================

    component IconBtn: Rectangle {
        id: ib
        property string glyph: ""
        property color tint: root.cMuted
        property string tooltipText: ""
        signal clicked()

        width: 26
        height: 26
        radius: 13
        color: ibHover.hovered ? root.cVariant : root.cContainer

        Text {
            anchors.centerIn: parent
            text: ib.glyph
            font.family: Theme.fontMono
            font.pixelSize: 12
            color: ib.tint
        }

        ToolTip.visible: ibHover.hovered && ib.tooltipText !== ""
        ToolTip.text: ib.tooltipText
        ToolTip.delay: 500

        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
    }

    component ChipButton: Rectangle {
        id: chip
        property string label: ""
        property color accent: root.cMuted
        signal clicked()

        implicitHeight: 22
        implicitWidth: chipText.implicitWidth + 18
        radius: 11
        color: chipHover.hovered ? root.cVariant : root.cContainer

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.family: Theme.fontMono
            font.pixelSize: 8
            color: chip.accent
        }

        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    component KbdHint: Rectangle {
        id: kbd
        property string label: ""
        implicitHeight: 16
        implicitWidth: kbdText.implicitWidth + 10
        radius: 4
        color: root.cHigh

        Text {
            id: kbdText
            anchors.centerIn: parent
            text: kbd.label
            font.family: Theme.fontMono
            font.pixelSize: 7
            color: root.cText
        }
    }

    component MessageRow: Item {
        id: row
        required property int index
        required property string kind
        required property string text
        required property string model
        required property bool streaming
        required property string error
        required property bool stopped
        required property real ttftMs
        required property real tps
        required property int promptTok
        required property int outTok
        required property real totalMs
        required property string timeLabel

        readonly property bool isLast: row.index === messages.count - 1
        width: streamView.width - 36
        height: rowCol.height

        Column {
            id: rowCol
            width: parent.width
            spacing: 6

            // ---------------- user message ----------------
            RowLayout {
                visible: row.kind === "user"
                width: parent.width
                spacing: 10

                Item { Layout.fillWidth: true }

                Column {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: row.width * 0.85
                    spacing: 4

                    Row {
                        anchors.right: parent.right
                        spacing: 6
                        Text {
                            text: root.userName + "@" + (root.hostName !== "" ? root.hostName : "local")
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: root.cMuted
                        }
                        Text {
                            text: "\u2022"
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.4)
                        }
                        Text {
                            text: row.timeLabel
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: root.cMuted
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: userText.width + 26
                        height: userText.height + 26
                        topRightRadius: 4
                        radius: 14
                        color: root.cHigh

                        Text {
                            id: userText
                            x: 13
                            y: 13
                            text: row.text
                            width: Math.min(implicitWidth, row.width * 0.85 - 26)
                            wrapMode: Text.Wrap
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            color: root.cText
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 28
                    height: 28
                    radius: 14
                    color: root.cContainer
                    Text {
                        anchors.centerIn: parent
                        text: "\u{F0004}"
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                        color: root.cPri
                    }
                }
            }

            // ---------------- assistant message ----------------
            RowLayout {
                visible: row.kind === "assistant"
                width: parent.width
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 28
                    height: 28
                    radius: 14
                    color: Qt.rgba(87 / 255, 241 / 255, 219 / 255, 0.2)
                    Text {
                        anchors.centerIn: parent
                        text: "\u{F06A9}"
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                        color: root.cPri
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 6

                    Row {
                        spacing: 6
                        Text {
                            text: row.model !== "" ? row.model : "local"
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                            font.bold: true
                            color: root.cPri
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            height: 15
                            width: gpuChip.implicitWidth + 10
                            radius: 7
                            color: root.cContainer
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: gpuChip
                                anchors.centerIn: parent
                                text: "GPU LOCAL"
                                font.family: Theme.fontMono
                                font.pixelSize: 7
                                color: root.cMuted
                            }
                        }
                        Text {
                            visible: row.ttftMs > 0
                            text: "TTFT: " + Math.round(row.ttftMs) + "ms"
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: root.cMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: row.tps > 0
                            text: "\u2022 " + row.tps.toFixed(1) + " t/s"
                            font.family: Theme.fontMono
                            font.pixelSize: 8
                            color: root.cMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: row.streaming && row.text !== ""
                            text: "STREAMING\u2026"
                            font.family: Theme.fontMono
                            font.pixelSize: 7
                            font.letterSpacing: 1.2
                            color: root.cTer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        width: parent.width
                        topLeftRadius: 4
                        radius: 14
                        color: root.cLow
                        implicitHeight: cardCol.implicitHeight + 28

                        Column {
                            id: cardCol
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 14
                            spacing: 10

                            Repeater {
                                model: root.segmentsFor(row.text)

                                Item {
                                    required property var modelData
                                    width: cardCol.width
                                    height: modelData.kind === "code" ? codeBlock.implicitHeight
                                          : (modelData.kind === "text" ? textBlock.implicitHeight : 0)

                                    Text {
                                        id: textBlock
                                        visible: modelData.kind === "text"
                                        width: parent.width
                                        text: modelData.kind === "text" ? modelData.text : ""
                                        wrapMode: Text.Wrap
                                        font.family: Theme.fontUi
                                        font.pixelSize: 12
                                        lineHeight: 1.25
                                        color: root.cText
                                    }

                                    Rectangle {
                                        id: codeBlock
                                        visible: modelData.kind === "code"
                                        width: parent.width
                                        radius: 8
                                        color: root.cLowest
                                        implicitHeight: codeCol.implicitHeight + 8

                                        Column {
                                            id: codeCol
                                            width: parent.width
                                            spacing: 0

                                            Rectangle {
                                                width: parent.width
                                                height: 24
                                                color: Qt.rgba(38 / 255, 42 / 255, 52 / 255, 0.6)
                                                topLeftRadius: 8
                                                topRightRadius: 8

                                                Row {
                                                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                                    spacing: 6
                                                    Text {
                                                        text: "</>"
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 8
                                                        color: root.cTer
                                                    }
                                                    Text {
                                                        text: String(modelData.lang || "code").toUpperCase()
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 8
                                                        color: root.cMuted
                                                    }
                                                }

                                                Text {
                                                    id: copyLabel
                                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                                    text: copyMouse.copied ? "COPIED" : "COPY"
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 8
                                                    color: root.cPri

                                                    MouseArea {
                                                        id: copyMouse
                                                        property bool copied: false
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Quickshell.clipboardText = String(modelData.text || "")
                                                            copyMouse.copied = true
                                                            copyTimer.restart()
                                                        }
                                                        Timer {
                                                            id: copyTimer
                                                            interval: 1400
                                                            onTriggered: copyMouse.copied = false
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width - 20
                                                x: 10
                                                y: 10
                                                text: String(modelData.text || "").replace(/\n+$/, "")
                                                wrapMode: Text.WrapAnywhere
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                                lineHeight: 1.2
                                                color: root.cText
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: row.text === "" && row.streaming
                                text: "\u2026"
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                                color: root.cMuted
                            }

                            Rectangle {
                                visible: row.error !== ""
                                width: parent.width
                                height: errorText.implicitHeight + 16
                                radius: 8
                                color: Qt.rgba(147 / 255, 0, 10 / 255, 0.25)
                                Text {
                                    id: errorText
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    text: row.error
                                    wrapMode: Text.Wrap
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    color: root.cErr
                                }
                            }

                            RowLayout {
                                visible: root.showMetrics && !row.streaming && (row.outTok > 0 || row.totalMs > 0)
                                width: parent.width
                                spacing: 6

                                Rectangle {
                                    width: 5; height: 5; radius: 3
                                    color: row.stopped ? root.cTer : root.cPri
                                }
                                Text {
                                    text: (row.stopped ? "Stopped" : "Inference " + (row.totalMs / 1000).toFixed(2) + "s")
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.7)
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Prompt: " + row.promptTok + " tok \u2022 Output: " + row.outTok + " tok"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    color: Qt.rgba(186 / 255, 202 / 255, 197 / 255, 0.7)
                                }
                                Text {
                                    visible: row.tps > 0
                                    text: "\u2022 " + row.tps.toFixed(1) + " t/s"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 8
                                    color: root.cPri
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 6

                        ChipButton {
                            visible: row.streaming
                            label: "STOP GENERATION"
                            accent: root.cErr
                            onClicked: root.stopGeneration()
                        }
                        ChipButton {
                            visible: !row.streaming && row.isLast && row.text !== "" && row.error === ""
                            label: "REGENERATE"
                            accent: root.cPri
                            onClicked: root.regenerate()
                        }
                    }
                }
            }
        }
    }
}
