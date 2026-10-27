// Island state: launcher — compact search pill (420×60) and results panel (520px wide).
// Applications come from the live DesktopEntries model; calculator and command mode are
// deliberately parsed locally and never passed through a shell.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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
    readonly property bool hasQuery: query.trim() !== ""
    readonly property real w: calc || hasQuery ? 520 : 420
    readonly property real h: calc ? 120 : hasQuery ? Math.min(360, 16 + 44 + 9 + Math.max(1, results.length) * 38 + 40) : 60
    readonly property color accent: calc ? core.amber : core.teal
    anchors.fill: parent
    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    onActiveChanged: {
        if (active) {
            query = ""; input.text = ""; results = []; calc = null; sel = 0
            focusTimer.restart()
        } else {
            query = ""; results = []; calc = null
        }
    }
    Timer { id: focusTimer; interval: 90; onTriggered: input.forceActiveFocus() }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/launcher-shortcuts.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const a = JSON.parse(text()); st.shortcuts = Array.isArray(a) ? a.filter(x => x && x.name && x.target) : [] } catch (e) { st.shortcuts = [] } }
    }
    readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/island/launcher-usage.json"
    FileView {
        path: st.usagePath
        onLoaded: { try { st.usage = JSON.parse(text()) } catch (e) { st.usage = {} } }
    }
    function bump(id) {
        const u = Object.assign({}, usage); u[id] = (u[id] || 0) + 1; usage = u
        // The path is fixed by the component and the value is passed as an argument.
        Quickshell.execDetached(["sh", "-c", "umask 077; mkdir -p \"$(dirname \"$1\")\"; printf '%s\\n' \"$2\" > \"$1\"", "sh", usagePath, JSON.stringify(u)])
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
        return best + Math.min(20, usage[e.id] || 0) * 2
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
        sel = 0; calc = null; const raw = query.trim()
        if (raw === "") { results = []; return }
        const math = evalMath(raw)
        if (math) { calc = math; results = []; return }
        if (raw.charAt(0) === ">") { const cmd = raw.slice(1).trim(); results = cmd ? [{ kind: "cmd", name: "Run: " + cmd, cmd: cmd }] : []; return }
        const q = raw.toLowerCase(), out = []
        for (const sc of shortcuts) { const f = fuzzy(q, sc.name); if (f >= 0) out.push({ kind: "shortcut", name: sc.name, target: String(sc.target), score: f + 30 }) }
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            const score = appScore(q, e); if (score >= 0) out.push({ kind: "app", name: e.name, sub: e.genericName || "", entry: e, id: e.id, score: score })
        }
        out.sort((a, b) => b.score - a.score)
        results = out.slice(0, 5).concat([{ kind: "web", name: "Search the web for “" + raw + "”", url: core.searchUrl + encodeURIComponent(raw) }])
    }

    // Deliberate command mode is argv-only and bounded. Shell operators, paths, and
    // substitutions are rejected; this keeps >kitty useful without turning the launcher into a shell.
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
    function runCommand(src) { const argv = commandArgv(src); if (argv.length) Quickshell.execDetached(argv); else return false; return true }
    function copyResult() {
        if (calc) Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", calc.text])
    }
    function activate(r) {
        if (calc && !r) { copyResult(); core.setLauncher(false); return }
        if (!r) return
        if (r.kind === "app") { bump(r.id); r.entry.execute() }
        else if (r.kind === "cmd") { if (!runCommand(r.cmd)) return }
        else if (r.kind === "web") Quickshell.execDetached(["xdg-open", r.url])
        else if (r.kind === "shortcut") {
            if (r.target.indexOf("cmd:") === 0) { if (!runCommand(r.target.slice(4))) return }
            else if (/^https?:\/\//i.test(r.target)) Quickshell.execDetached(["xdg-open", r.target])
            else return
        }
        core.setLauncher(false)
    }
    function glyph(k) { return k === "app" ? "apps" : k === "cmd" ? "terminal" : k === "shortcut" ? "bookmark" : "public" }
    function tone(k) { return k === "app" ? core.teal : k === "cmd" ? core.lav : k === "shortcut" ? core.amber : core.dim }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: hasQuery ? 14 : 0
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hasQuery ? 44 : 60
            radius: hasQuery ? 14 : 30
            color: hasQuery ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10
                Text {
                    text: st.core.iconOk ? "search" : "⌕"
                    font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
                    font.pixelSize: 18
                    color: st.core.teal
                    Layout.preferredWidth: 22
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        visible: input.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps, shortcuts or math…"
                        color: st.core.dim
                        font.family: st.core.uiFont
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: input
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: st.core.text
                        font.family: st.core.uiFont
                        font.pixelSize: 14
                        clip: true
                        text: st.query
                        onTextChanged: { if (text !== st.query) st.query = text; st.compute() }
                        Keys.onEscapePressed: { st.core.setLauncher(false); event.accepted = true }
                        Keys.onReturnPressed: st.activate(st.calc ? null : st.results[st.sel])
                        Keys.onEnterPressed: st.activate(st.calc ? null : st.results[st.sel])
                        Keys.onDownPressed: { st.sel = Math.min(st.results.length - 1, st.sel + 1); event.accepted = true }
                        Keys.onUpPressed: { st.sel = Math.max(0, st.sel - 1); event.accepted = true }
                        Keys.onTabPressed: { if (st.results[st.sel] && st.results[st.sel].kind !== "web") { st.query = st.results[st.sel].name; text = st.query; cursorPosition = text.length }; event.accepted = true }
                    }
                }
                Text {
                    visible: hasQuery && !calc
                    text: results.length + (results.length === 1 ? " result" : " results") + " · ESC"
                    color: st.core.dim
                    font.family: st.core.monoFont
                    font.pixelSize: 10
                }
            }
        }
        ColumnLayout {
            visible: hasQuery && !calc
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: st.results
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === st.sel
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 9
                    color: chosen ? Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.14) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 10
                        Item {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                visible: status === Image.Ready
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 44
                                sourceSize.height: 44
                                source: modelData.kind === "app" && modelData.entry.icon
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
                                font.pixelSize: 18
                                color: st.tone(modelData.kind)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Text {
                            text: modelData.name
                            color: st.core.text
                            font.family: st.core.uiFont
                            font.pixelSize: 13
                            font.weight: chosen ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: modelData.sub !== undefined && chosen
                            text: modelData.sub || ""
                            color: st.core.dim
                            font.family: st.core.monoFont
                            font.pixelSize: 10
                        }
                        Text {
                            text: modelData.kind.toUpperCase()
                            color: st.tone(modelData.kind)
                            font.family: st.core.monoFont
                            font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: st.sel = index
                        onClicked: st.activate(modelData)
                    }
                }
            }
        }
        Text {
            visible: hasQuery && !calc
            text: "[↵] Open    [Tab] Complete    [↑↓] Move                  > controlled command"
            color: st.core.dim
            font.family: st.core.monoFont
            font.pixelSize: 10
            Layout.fillWidth: true
        }
        RowLayout {
            visible: calc !== null
            Layout.fillWidth: true
            Text { text: st.core.iconOk ? "calculate" : "="; color: st.core.amber; font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont; font.pixelSize: 18 }
            Text { text: calc ? "= " + calc.text : ""; color: st.core.teal; font.family: st.core.monoFont; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
            Text { text: "[↵] Copy"; color: st.core.dim; font.family: st.core.monoFont; font.pixelSize: 10 }
        }
        Item { Layout.fillHeight: true; visible: !hasQuery }
    }
}
