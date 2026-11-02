// Island state: launcher — compact search pill (520px wide) with favorites, frequent apps, and live search.
// Applications come from the live DesktopEntries model; calculator and command mode are
// deliberately parsed locally and never passed through a shell.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config

Item {
    id: st
    required property var core
    readonly property string key: "launcher"
    readonly property bool active: core.mode === key
    property string query: ""
    property var results: []
    property var calc: null
    property int sel: 0
    property var shortcuts: []
    property var usage: ({})
    property var favorites: []
    readonly property bool hasQuery: query.trim() !== ""
    readonly property real w: Theme.islandLauncherWidth
    readonly property real h: calc
        ? core.scale(120)
        : hasQuery
            ? Math.min(core.scale(460), core.scale(58) + Math.max(1, results.length) * core.scale(40) + core.scale(36))
            : Math.min(core.scale(460), Math.max(core.scale(220), core.scale(58) + Math.max(1, results.length) * core.scale(40) + (favorites.length === 0 ? core.scale(32) : core.scale(56)) + core.scale(36)))
    readonly property color accent: calc ? core.amber : core.teal
    anchors.fill: parent
    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: {
        core.register(key, st)
        compute()
    }

    onActiveChanged: {
        if (active) {
            query = ""
            input.text = ""
            calc = null
            sel = 0
            compute()
            focusTimer.restart()
        } else {
            query = ""
            calc = null
        }
    }
    Timer { id: focusTimer; interval: 90; onTriggered: input.forceActiveFocus() }

    readonly property string shortcutsPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/launcher-shortcuts.json"
    readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/island/launcher-usage.json"
    readonly property string favoritesPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/island/launcher-favorites.json"

    function atomicSave(targetPath, content) {
        Quickshell.execDetached([
            "sh", "-c",
            "umask 077; d=\"$(dirname \"$1\")\"; tmp=\"${d}/.$(basename \"$1\").tmp.$$\"; mkdir -p \"$d\" && printf '%s\\n' \"$2\" > \"$tmp\" && mv -f \"$tmp\" \"$1\"",
            "sh", targetPath, content
        ])
    }

    FileView {
        path: st.shortcutsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const a = JSON.parse(text())
                st.shortcuts = Array.isArray(a) ? a.filter(x => x && x.name && x.target) : []
            } catch (e) {
                st.shortcuts = []
            }
        }
    }

    FileView {
        path: st.usagePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                    st.usage = parsed
                } else {
                    st.usage = {}
                }
            } catch (e) {
                st.usage = {}
            }
            st.compute()
        }
    }

    FileView {
        path: st.favoritesPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (Array.isArray(parsed)) {
                    st.favorites = parsed.filter(x => typeof x === "string" && x.trim() !== "")
                } else {
                    st.favorites = []
                }
            } catch (e) {
                st.favorites = []
            }
            st.compute()
        }
    }

    function bump(id) {
        if (!id || typeof id !== "string") return
        const u = Object.assign({}, st.usage)
        u[id] = (u[id] || 0) + 1
        st.usage = u
        atomicSave(st.usagePath, JSON.stringify(u, null, 2))
    }

    function saveFavorites() {
        atomicSave(st.favoritesPath, JSON.stringify(st.favorites, null, 2))
    }

    function toggleFavorite(id) {
        if (!id || typeof id !== "string") return
        let favs = st.favorites.slice()
        const idx = favs.indexOf(id)
        if (idx >= 0) {
            favs.splice(idx, 1)
        } else {
            favs.push(id)
        }
        st.favorites = favs
        saveFavorites()
        compute()
    }

    function isAppFavorite(id) {
        return Boolean(id && st.favorites.indexOf(id) >= 0)
    }

    function findAppById(appId) {
        if (!appId || typeof appId !== "string") return null
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            if (e && e.id === appId && !e.noDisplay) return e
        }
        return null
    }

    function fuzzy(q, text) {
        if (!text) return -1
        const s = String(text).toLowerCase()
        if (s === q) return 100
        if (s.indexOf(q) === 0) return 80 - (s.length - q.length) * 0.2
        const at = s.indexOf(q)
        if (at >= 0) return 55 - at * 0.5 + (at === 0 || " -_.".indexOf(s.charAt(at - 1)) >= 0 ? 12 : 0)
        let qi = 0, score = 0, last = -1
        for (let i = 0; i < s.length && qi < q.length; i++) if (s.charAt(i) === q.charAt(qi)) {
            score += (last === i - 1 ? 5 : 1) + (i === 0 || " -_.".indexOf(s.charAt(i - 1)) >= 0 ? 4 : 0); last = i; qi++
        }
        return qi === q.length ? 15 + score : -1
    }

    function appScore(q, e) {
        let best = fuzzy(q, e.name)
        const g = fuzzy(q, e.genericName); if (g >= 0) best = Math.max(best, g * 0.7)
        for (const k of (e.keywords || [])) { const f = fuzzy(q, k); if (f >= 0) best = Math.max(best, f * 0.6) }
        if (best < 0) return -1
        return best + Math.min(20, (usage[e.id] || 0) * 2)
    }

    // Restricted recursive-descent parser: numbers, parentheses, unary signs, + - * / % ^.
    function evalMath(src) {
        const s = src.replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, ".")
        if (!/^[0-9+\-*/^%().\s]+$/.test(s) || !/[0-9]/.test(s)) return null
        let i = 0
        function ws() { while (/\s/.test(s.charAt(i))) i++ }
        function number() { ws(); const m = /^\d*\.?\d+/.exec(s.slice(i)); if (!m) throw 0; i += m[0].length; return Number(m[0]) }
        function primary() { ws(); if (s.charAt(i) === "(") { i++; const v = expression(); ws(); if (s.charAt(i++) !== ")") throw 0; return v } return number() }
        function unary() { ws(); if (s.charAt(i) === "-") { i++; return -unary() } if (s.charAt(i) === "+") { i++; return unary() } return power() }
        function power() { const b = primary(); ws(); if (s.charAt(i) === "^") { i++; return Math.pow(b, unary()) } return b }
        function term() { let v = unary(); for (;;) { ws(); const c = s.charAt(i); if (c === "*") { i++; v *= unary() } else if (c === "/") { i++; v /= unary() } else if (c === "%") { i++; v %= unary() } else return v } }
        function expression() { let v = term(); for (;;) { ws(); const c = s.charAt(i); if (c === "+") { i++; v += term() } else if (c === "-") { i++; v -= term() } else return v } }
        try { const value = expression(); ws(); return i === s.length && isFinite(value) ? { text: String(Number(value.toPrecision(12))) } : null } catch (e) { return null }
    }

    function compute() {
        sel = 0
        calc = null
        const raw = query.trim()

        if (raw === "") {
            const out = []
            // 1. Favorites section (appears first)
            const favIds = st.favorites || []
            for (let i = 0; i < favIds.length; i++) {
                const e = findAppById(favIds[i])
                if (e) {
                    out.push({
                        kind: "app",
                        section: "favorites",
                        id: e.id,
                        name: e.name,
                        sub: e.genericName || "",
                        entry: e,
                        isFavorite: true
                    })
                }
            }

            // 2. Frequently opened section (below favorites, excluding favorites, max 6 apps)
            const favSet = new Set(favIds)
            const freqList = []
            for (const id in st.usage) {
                if (!favSet.has(id)) {
                    const count = st.usage[id]
                    if (typeof count === "number" && count > 0) {
                        const e = findAppById(id)
                        if (e) {
                            freqList.push({
                                id: id,
                                entry: e,
                                count: count
                            })
                        }
                    }
                }
            }
            freqList.sort((a, b) => b.count - a.count)
            const topFreq = freqList.slice(0, 6)
            for (let j = 0; j < topFreq.length; j++) {
                const item = topFreq[j]
                out.push({
                    kind: "app",
                    section: "frequent",
                    id: item.id,
                    name: item.entry.name,
                    sub: item.entry.genericName || (item.count + (item.count === 1 ? " launch" : " launches")),
                    entry: item.entry,
                    isFavorite: false
                })
            }

            // 3. Fallback when both favorites and frequent are empty
            if (out.length === 0) {
                const apps = DesktopEntries.applications.values
                let added = 0
                for (let k = 0; k < apps.length && added < 6; k++) {
                    const e = apps[k]
                    if (e && !e.noDisplay) {
                        out.push({
                            kind: "app",
                            section: "suggestions",
                            id: e.id,
                            name: e.name,
                            sub: e.genericName || "",
                            entry: e,
                            isFavorite: false
                        })
                        added++
                    }
                }
            }

            results = out
            return
        }

        const math = evalMath(raw)
        if (math) {
            calc = math
            results = []
            return
        }

        if (raw.charAt(0) === ">") {
            const cmd = raw.slice(1).trim()
            results = cmd ? [{ kind: "cmd", name: "Run: " + cmd, cmd: cmd }] : []
            return
        }

        const q = raw.toLowerCase()
        const out = []
        for (const sc of shortcuts) {
            const f = fuzzy(q, sc.name)
            if (f >= 0) out.push({ kind: "shortcut", name: sc.name, target: String(sc.target), score: f + 30 })
        }

        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            let score = appScore(q, e)
            if (score >= 0) {
                if (isAppFavorite(e.id)) score += 20
                out.push({
                    kind: "app",
                    section: "results",
                    id: e.id,
                    name: e.name,
                    sub: e.genericName || "",
                    entry: e,
                    score: score,
                    isFavorite: isAppFavorite(e.id)
                })
            }
        }
        out.sort((a, b) => b.score - a.score)

        const topApps = out.slice(0, 6)
        topApps.push({
            kind: "web",
            section: "web",
            name: "Search the web for “" + raw + "”",
            url: core.searchUrl + encodeURIComponent(raw)
        })
        results = topApps
    }

    readonly property var commandNames: ["kitty", "foot", "alacritty", "wezterm", "firefox", "chromium", "google-chrome", "thunar", "nautilus", "code", "nvim", "notify-send"]
    function commandArgv(src) {
        const s = String(src || "").trim()
        if (s === "" || s.length > 240 || /[;&|`$<>\\\n]/.test(s)) return []
        const tokens = s.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || []
        if (tokens.length === 0 || tokens.length > 16) return []
        const argv = tokens.map(t => (t.charAt(0) === '"' || t.charAt(0) === "'") ? t.slice(1, -1) : t)
        if (commandNames.indexOf(argv[0]) < 0 || argv.some(a => a.length > 120 || /[;&|`$<>\\\n]/.test(a))) return []
        return argv
    }
    function runCommand(src) {
        const argv = commandArgv(src)
        if (argv.length) Quickshell.execDetached(argv)
        else return false
        return true
    }

    function copyResult() {
        if (calc) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", calc.text])
    }

    function launchApp(entry) {
        if (!entry) return false
        try {
            entry.execute()
            bump(entry.id)
            return true
        } catch (e) {
            console.warn("[Launcher] Launch failed for:", entry.id, e)
            return false
        }
    }

    function launchWeb(url) {
        if (!url) return false
        try {
            Quickshell.execDetached(["xdg-open", url])
            return true
        } catch (e) {
            return false
        }
    }

    function activate(r) {
        if (calc && !r) {
            copyResult()
            core.setLauncher(false)
            return
        }
        if (!r) return

        if (r.kind === "app") {
            if (launchApp(r.entry)) {
                core.setLauncher(false)
            }
            return
        }
        if (r.kind === "cmd") {
            if (runCommand(r.cmd)) {
                core.setLauncher(false)
            }
            return
        }
        if (r.kind === "web") {
            if (launchWeb(r.url)) {
                core.setLauncher(false)
            }
            return
        }
        if (r.kind === "shortcut") {
            if (r.target.indexOf("cmd:") === 0) {
                if (runCommand(r.target.slice(4))) {
                    core.setLauncher(false)
                }
                return
            } else if (/^https?:\/\//i.test(r.target)) {
                if (launchWeb(r.target)) {
                    core.setLauncher(false)
                }
                return
            }
        }
    }

    function glyph(k) {
        return k === "app" ? "apps" : k === "cmd" ? "terminal" : k === "shortcut" ? "bookmark" : "public"
    }

    function tone(k) {
        return k === "app" ? core.teal : k === "cmd" ? core.lav : k === "shortcut" ? core.amber : core.dim
    }

    onSelChanged: {
        if (resultsFlickable && resultsCol && st.results.length > 0) {
            const itemY = st.sel * 40
            if (itemY < resultsFlickable.contentY) {
                resultsFlickable.contentY = Math.max(0, itemY)
            } else if (itemY + 44 > resultsFlickable.contentY + resultsFlickable.height) {
                resultsFlickable.contentY = Math.max(0, itemY + 44 - resultsFlickable.height)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // Top Search Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.islandLauncherSearchHeight
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.4) : Qt.rgba(1, 1, 1, 0.08)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                Text {
                    text: st.core.iconOk ? "search" : "⌕"
                    font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
                    font.pixelSize: core.scale(18)
                    color: st.core.teal
                    Layout.preferredWidth: Theme.scaled(22)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        visible: input.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps, favorites, shortcuts or math…"
                        color: st.core.dim
                        font.family: st.core.uiFont
                        font.pixelSize: core.scale(13)
                    }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: st.core.text
                        font.family: st.core.uiFont
                        font.pixelSize: core.scale(14)
                        clip: true
                        text: st.query
                        onTextChanged: {
                            if (text !== st.query) st.query = text
                            st.compute()
                        }
                        Keys.onEscapePressed: {
                            st.core.setLauncher(false)
                            event.accepted = true
                        }
                        Keys.onReturnPressed: st.activate(st.calc ? null : st.results[st.sel])
                        Keys.onEnterPressed: st.activate(st.calc ? null : st.results[st.sel])
                        Keys.onDownPressed: {
                            st.sel = Math.min(st.results.length - 1, st.sel + 1)
                            event.accepted = true
                        }
                        Keys.onUpPressed: {
                            st.sel = Math.max(0, st.sel - 1)
                            event.accepted = true
                        }
                        Keys.onTabPressed: {
                            if (st.results[st.sel] && st.results[st.sel].kind === "app") {
                                st.query = st.results[st.sel].name
                                text = st.query
                                cursorPosition = text.length
                            }
                            event.accepted = true
                        }
                        Keys.onPressed: (event) => {
                            if ((event.key === Qt.Key_D || event.key === Qt.Key_F) && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                                const cur = st.results[st.sel]
                                if (cur && cur.id) {
                                    st.toggleFavorite(cur.id)
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }

                // Clear query button
                Rectangle {
                    visible: st.hasQuery
                    Layout.preferredWidth: Theme.scaled(20)
                    Layout.preferredHeight: Theme.scaled(20)
                    radius: 10
                    color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: core.scale(10)
                        color: clearMouse.containsMouse ? st.core.text : st.core.dim
                    }
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            st.query = ""
                            input.text = ""
                            st.compute()
                            input.forceActiveFocus()
                        }
                    }
                }

                // Close button / ESC indicator
                Rectangle {
                    Layout.preferredWidth: Theme.scaled(38)
                    Layout.preferredHeight: Theme.scaled(22)
                    radius: 6
                    color: closeMouse.containsMouse ? Qt.rgba(st.core.coral ? st.core.coral.r : 0.9, 0.3, 0.3, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: "ESC"
                        font.family: st.core.monoFont
                        font.pixelSize: core.scale(10)
                        color: closeMouse.containsMouse ? st.core.text : st.core.dim
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.core.setLauncher(false)
                    }
                }
            }
        }

        // Calculator Result Surface
        RowLayout {
            visible: calc !== null
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.scaled(48)
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.3)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Text {
                        text: st.core.iconOk ? "calculate" : "="
                        color: st.core.amber
                        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
                        font.pixelSize: core.scale(20)
                    }
                    Text {
                        text: calc ? calc.text : ""
                        color: st.core.amber
                        font.family: st.core.monoFont
                        font.pixelSize: core.scale(20)
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "[↵] Copy to clipboard"
                        color: st.core.dim
                        font.family: st.core.monoFont
                        font.pixelSize: core.scale(11)
                    }
                }
            }
        }

        // Empty favorites hint when search is empty and user has not pinned any favorites yet
        Rectangle {
            visible: !hasQuery && !calc && st.favorites.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.scaled(32)
            radius: 8
            color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.2)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Text {
                    text: "★"
                    color: st.core.amber
                    font.pixelSize: core.scale(12)
                }
                Text {
                    text: "No favorites pinned yet · Click the star on any app below to pin it here"
                    color: st.core.text
                    font.family: st.core.uiFont
                    font.pixelSize: core.scale(11)
                    Layout.fillWidth: true
                }
            }
        }

        // Scrollable List of Items
        Flickable {
            id: resultsFlickable
            visible: !calc
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: resultsCol.implicitHeight

            ColumnLayout {
                id: resultsCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: st.results
                    delegate: ColumnLayout {
                        id: itemDelegate
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === st.sel
                        Layout.fillWidth: true
                        spacing: 2

                        // Section Header (Favorites vs Frequent vs Suggestions)
                        Item {
                            visible: !st.hasQuery && (index === 0 || (st.results[index - 1] && modelData.section !== st.results[index - 1].section))
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.scaled(24)
                            Layout.topMargin: index === 0 ? 0 : 8

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: 6

                                Text {
                                    text: modelData.section === "favorites" ? "★" : (modelData.section === "frequent" ? "󰁯" : "✦")
                                    color: modelData.section === "favorites" ? st.core.amber : st.core.teal
                                    font.pixelSize: core.scale(11)
                                }
                                Text {
                                    text: modelData.section === "favorites" ? "FAVORITES" : (modelData.section === "frequent" ? "FREQUENTLY OPENED" : "SUGGESTIONS")
                                    color: st.core.dim
                                    font.family: st.core.monoFont
                                    font.pixelSize: core.scale(10)
                                    font.bold: true
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // App / Action Row Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.scaled(38)
                            radius: 9
                            color: chosen
                                ? Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.16)
                                : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            border.width: chosen ? 1 : 0
                            border.color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.35)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 10

                                // App Icon or Kind Glyph
                                Item {
                                    Layout.preferredWidth: Theme.scaled(24)
                                    Layout.preferredHeight: Theme.scaled(24)

                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        visible: status === Image.Ready
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 48
                                        sourceSize.height: 48
                                        source: modelData.kind === "app" && modelData.entry && modelData.entry.icon
                                            ? (modelData.entry.icon.charAt(0) === "/"
                                               ? "file://" + modelData.entry.icon
                                               : Quickshell.iconPath(modelData.entry.icon, true))
                                            : ""
                                    }

                                    Text {
                                        anchors.fill: parent
                                        visible: appIcon.status !== Image.Ready
                                        text: st.core.iconOk ? st.glyph(modelData.kind) : "•"
                                        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
                                        font.pixelSize: core.scale(18)
                                        color: st.tone(modelData.kind)
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                // App Name
                                Text {
                                    text: modelData.name
                                    color: st.core.text
                                    font.family: st.core.uiFont
                                    font.pixelSize: core.scale(13)
                                    font.bold: chosen
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // Subtitle
                                Text {
                                    visible: Boolean(modelData.sub)
                                    text: modelData.sub || ""
                                    color: st.core.dim
                                    font.family: st.core.monoFont
                                    font.pixelSize: core.scale(10)
                                    elide: Text.ElideRight
                                }

                                // Section Tag / Kind Badge
                                Rectangle {
                                    visible: modelData.kind !== "app" || modelData.isFavorite
                                    Layout.preferredHeight: Theme.scaled(18)
                                    implicitWidth: tagText.implicitWidth + 10
                                    radius: 5
                                    color: modelData.isFavorite
                                        ? Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.18)
                                        : Qt.rgba(1, 1, 1, 0.08)
                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: modelData.isFavorite ? "PINNED" : modelData.kind.toUpperCase()
                                        font.family: st.core.monoFont
                                        font.pixelSize: core.scale(9)
                                        font.bold: true
                                        color: modelData.isFavorite ? st.core.amber : st.tone(modelData.kind)
                                    }
                                }

                                // Star / Favorite Toggle Button
                                Item {
                                    visible: modelData.kind === "app"
                                    Layout.preferredWidth: Theme.scaled(26)
                                    Layout.preferredHeight: Theme.scaled(26)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.isFavorite ? "★" : "☆"
                                        font.pixelSize: core.scale(16)
                                        color: modelData.isFavorite
                                            ? st.core.amber
                                            : (starMouse.containsMouse ? st.core.text : (chosen ? st.core.dim : Qt.rgba(1, 1, 1, 0.2)))
                                        scale: starMouse.containsMouse ? 1.25 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                    }

                                    MouseArea {
                                        id: starMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: st.toggleFavorite(modelData.id)
                                    }
                                }
                            }

                            // Launch Click Area (covers entire row except star toggle on right)
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                anchors.rightMargin: modelData.kind === "app" ? 34 : 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: st.sel = index
                                onClicked: st.activate(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Bottom Footer Keyboard Help
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.scaled(20)
            visible: !calc

            Text {
                text: "[↵] Open   [Tab] Complete   [↑↓] Move   [Ctrl+D] Star   [ESC] Close"
                color: st.core.dim
                font.family: st.core.monoFont
                font.pixelSize: core.scale(10)
                Layout.fillWidth: true
            }

            Text {
                visible: st.hasQuery
                text: st.results.length + (st.results.length === 1 ? " match" : " matches")
                color: st.core.dim
                font.family: st.core.monoFont
                font.pixelSize: core.scale(10)
            }
        }
    }
}
