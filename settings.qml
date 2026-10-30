// ─────────────────────────────────────────────────────────────────────────────
//  Settings Hub — single-file QuickShell settings window for Hyprland
//  Target: QuickShell 0.3.x · Qt 6.x · Hyprland 0.5x (hyprlang AND Lua configs)
//
//  Run standalone :  qs -p ~/Projects/my-rice/settings.qml
//  Toggle via IPC :  qs -p <path> ipc call settings toggle      (or: open network)
//  Embed in shell :  change `ShellRoot` to `Scope` and drop it into your shell.qml
//
//  Nothing system-specific is hard-coded: monitors, modes, refresh rates, audio
//  devices, Bluetooth, Wi-Fi, GPU, battery, power profiles, fonts, palette,
//  keybinds, services, tools and Ollama models are all detected live.
//  Palette follows the wallpaper (GPS theme json → pywal colors.json →
//  Caelestia scheme.json, all watched live).
//
//  Persistence: every change applies live AND is written to
//    ~/.config/quickshell/rice-settings.json     (own state, readable by your assistant)
//    ~/.config/hypr/rice-settings.conf | .lua    (include it once from your Hypr config)
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import qs.config

ShellRoot {
    id: root

    // ───────────────────────────── state ─────────────────────────────
    readonly property string home: Quickshell.env("HOME")
    readonly property string storePath: home + "/.config/quickshell/rice-settings.json"
    readonly property string hyprFile: home + "/.config/hypr/rice-settings." + (luaMode ? "lua" : "conf")

    property bool shown: true
    property int page: 0
    property string uiFont: Theme.fontSans
    property string monoFont: Theme.fontMono
    property string iconFont: Theme.fontIcon
    property bool iconOk: true
    property string palettePath: ""
    property string paletteSource: "built-in fallback"

    property var sys: ({})          // key=value facts from the system
    property var mons: []           // hyprctl monitors -j
    property int monIdx: 0
    property string pickRes: ""
    property var opt: ({})          // live Hyprland option values
    property var binds: []
    property string bindFilter: ""
    property string hyprVersion: ""
    property bool luaMode: false
    property var store: ({ hypr: {}, monitors: {}, ai: {} })
    property string saved: ""

    property var wifi: []
    property string wifiRadio: ""
    property string wifiIp: ""
    property string wifiSel: ""
    property string wifiMsg: ""
    property var services: []
    property string cfgErrors: ""

    property var ai: ({ ollama: false, version: "", models: [], lmstudio: false, llamacpp: false })
    property var pull: ({})
    property string confirmDel: ""

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var mon: mons.length > 0 ? mons[Math.min(monIdx, mons.length - 1)] : null

    // ─────────────────────────── palette ───────────────────────────
    QtObject {
        id: pal
        property color bg: "#0f131c"
        property color surface: "#181b25"
        property color surfaceHi: "#262a34"
        property color line: "#31353f"
        property color text: "#dfe2ef"
        property color dim: "#9aa5a1"
        property color primary: "#57f1db"
        property color secondary: "#ddb8ff"
        property color tertiary: "#ffd47b"
        property color error: "#ffb4ab"
        property color ink: "#00201c"
    }

    function applyPalette(txt) {
        let j
        try { j = JSON.parse(txt) } catch (e) { return }
        const hex = s => Qt.color(String(s).charAt(0) === "#" ? s : "#" + s)
        if (j.brandAccent) {                               // GPS rice theme (extract-theme.py)
            const acc = hex(j.brandAccent)
            const opaque = c => Qt.rgba(c.r, c.g, c.b, 1)
            pal.primary = acc
            pal.ink = hex(j.brandAccentFg || "#00201c")
            const bump = dh => Qt.hsva((acc.hsvHue + dh) % 1, Math.max(0.45, acc.hsvSaturation * 0.9), Math.max(0.88, acc.hsvValue), 1)
            pal.secondary = bump(0.13)
            pal.tertiary = bump(0.26)
            if (j.surface) pal.bg = opaque(hex(j.surface))
            if (j.card) pal.surface = opaque(hex(j.card))
            if (j.cardHover) pal.surfaceHi = opaque(hex(j.cardHover))
            if (j.border) pal.line = opaque(hex(j.border))
            if (j.textMain) pal.text = hex(j.textMain)
            pal.dim = j.textMuted ? hex(j.textMuted) : Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.62)
            paletteSource = "GPS theme (wallpaper)"
        } else if (j.colours) {                            // Caelestia-style scheme.json
            const c = j.colours
            if (c.primary) pal.primary = hex(c.primary)
            if (c.secondary) pal.secondary = hex(c.secondary)
            if (c.tertiary) pal.tertiary = hex(c.tertiary)
            if (c.error) pal.error = hex(c.error)
            if (c.onPrimary) pal.ink = hex(c.onPrimary)
            const bg = hex(c.background || c.surface || "#0f131c")
            const fg = hex(c.onSurface || c.onBackground || "#dfe2ef")
            setSurfaces(bg, fg)
            paletteSource = "Caelestia scheme"
        } else if (j.colors && j.special) {                // pywal colors.json
            const keys = Object.keys(j.colors).filter(k => ["color0", "color7", "color8", "color15"].indexOf(k) < 0)
            const list = keys.map(k => Qt.color(j.colors[k]))
            list.sort((a, b) => b.hsvSaturation * b.hsvValue - a.hsvSaturation * a.hsvValue)
            const lift = c => Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, Math.min(1, Math.max(c.hsvSaturation, 0.45)), Math.max(c.hsvValue, 0.88), 1)
            if (list.length > 0) pal.primary = lift(list[0])
            let sec = list.find(c => Math.abs(c.hsvHue - list[0].hsvHue) > 0.12) || list[Math.min(1, list.length - 1)]
            if (sec) pal.secondary = lift(sec)
            let ter = list.find(c => Math.abs(c.hsvHue - list[0].hsvHue) > 0.12 && Math.abs(c.hsvHue - sec.hsvHue) > 0.12) || list[list.length - 1]
            if (ter) pal.tertiary = lift(ter)
            pal.ink = pal.primary.hsvValue > 0.6 ? Qt.rgba(0, 0, 0, 0.85) : "#ffffff"
            setSurfaces(Qt.color(j.special.background), Qt.color(j.special.foreground))
            paletteSource = "pywal"
        }
    }
    function setSurfaces(bg, fg) {
        pal.bg = bg
        pal.surface = Qt.tint(bg, Qt.rgba(1, 1, 1, 0.045))
        pal.surfaceHi = Qt.tint(bg, Qt.rgba(1, 1, 1, 0.10))
        pal.line = Qt.tint(bg, Qt.rgba(1, 1, 1, 0.16))
        pal.text = fg
        pal.dim = Qt.rgba(fg.r, fg.g, fg.b, 0.62)
    }

    // ─────────────────────── process helpers ───────────────────────
    component Cmd: Process {
        id: p
        property string script: ""
        property var args: []
        property string out: ""
        signal done(string text)
        command: ["sh", "-c", script, "sh"].concat(args)
        stdout: StdioCollector {
            onStreamFinished: { p.out = text; p.done(text) }
        }
        function go(s) {
            if (s !== undefined) script = s
            if (!running) running = true
        }
    }

    function sh(script, args) { Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args || [])) }
    function writeFile(path, text) {
        sh('d="$(dirname "$1")" && mkdir -p "$d" && tmp="${d}/.$(basename "$1").tmp.$$" && printf "%s\\n" "$2" > "$tmp" && mv -f "$tmp" "$1"', [path, text])
    }
    function kv(txt) {
        const o = {}
        for (const l of txt.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1).trim() }
        return o
    }
    function after(ms, fn) { delayer.fns.push(fn); delayer.restart(); delayer.interval = ms }
    Timer {
        id: delayer
        property var fns: []
        onTriggered: { const f = fns; fns = []; f.forEach(x => x()) }
    }

    // ─────────────────── Hyprland option schema ────────────────────
    function en(list, labels) { return list.map((v, i) => ({ v: v, l: labels ? labels[i] : String(v) })) }
    readonly property var schema: [
        { key: "general:layout", group: "Layout & Gaps", label: "Tiling layout", type: "enum", opts: en(["dwindle", "master", "scrolling", "monocle"], ["Dwindle", "Master", "Scrolling", "Monocle"]) },
        { key: "general:gaps_in", group: "Layout & Gaps", label: "Inner gaps", type: "int", min: 0, max: 30, unit: "px" },
        { key: "general:gaps_out", group: "Layout & Gaps", label: "Outer gaps", type: "int", min: 0, max: 60, unit: "px" },
        { key: "general:border_size", group: "Layout & Gaps", label: "Border thickness", type: "int", min: 0, max: 8, unit: "px" },
        { key: "decoration:rounding", group: "Decoration", label: "Window rounding", type: "int", min: 0, max: 30, unit: "px" },
        { key: "decoration:active_opacity", group: "Decoration", label: "Active window opacity", type: "float", min: 0.3, max: 1, step: 0.05 },
        { key: "decoration:inactive_opacity", group: "Decoration", label: "Inactive window opacity", type: "float", min: 0.3, max: 1, step: 0.05 },
        { key: "decoration:blur:enabled", group: "Effects", label: "Background blur", type: "bool", desc: "Glass effect behind translucent windows" },
        { key: "decoration:blur:size", group: "Effects", label: "Blur size", type: "int", min: 1, max: 20 },
        { key: "decoration:blur:passes", group: "Effects", label: "Blur passes", type: "int", min: 1, max: 6, desc: "More passes look smoother but cost GPU" },
        { key: "decoration:shadow:enabled", group: "Effects", label: "Window shadows", type: "bool" },
        { key: "animations:enabled", group: "Effects", label: "Animations", type: "bool" },
        { key: "input:kb_layout", group: "Keyboard", label: "Keyboard layout", type: "str", desc: "XKB layouts, comma separated (us, in, ...)" },
        { key: "input:kb_options", group: "Keyboard", label: "XKB options", type: "str", desc: "e.g. caps:escape, grp:alt_shift_toggle" },
        { key: "input:repeat_rate", group: "Keyboard", label: "Key repeat rate", type: "int", min: 10, max: 80, unit: "/s" },
        { key: "input:repeat_delay", group: "Keyboard", label: "Key repeat delay", type: "int", min: 150, max: 800, unit: "ms" },
        { key: "input:follow_mouse", group: "Mouse & Touchpad", label: "Focus follows mouse", type: "enum", opts: en([0, 1, 2, 3], ["Off", "Always", "Loose", "Click only"]) },
        { key: "input:sensitivity", group: "Mouse & Touchpad", label: "Pointer speed", type: "float", min: -1, max: 1, step: 0.1 },
        { key: "input:touchpad:natural_scroll", group: "Mouse & Touchpad", label: "Natural scrolling", type: "bool" },
        { key: "input:touchpad:tap-to-click", group: "Mouse & Touchpad", label: "Tap to click", type: "bool" },
        { key: "input:touchpad:disable_while_typing", group: "Mouse & Touchpad", label: "Disable touchpad while typing", type: "bool" },
        { key: "misc:vrr", group: "Display & Sync", label: "Variable refresh rate", type: "enum", opts: en([0, 1, 2], ["Off", "On", "Fullscreen only"]) },
        { key: "misc:vfr", group: "Display & Sync", label: "Variable frame rate", type: "bool", desc: "Skip redraws when nothing changes (saves battery)" },
        { key: "general:allow_tearing", group: "Display & Sync", label: "Allow tearing", type: "bool", desc: "Lower latency in games, may show tearing" },
        { key: "cursor:no_hardware_cursors", group: "NVIDIA & Rendering", label: "Hardware cursors", type: "enum", opts: en([0, 1, 2], ["Use", "Disable", "Auto"]), desc: "Disable if the cursor glitches on NVIDIA" },
        { key: "render:direct_scanout", group: "NVIDIA & Rendering", label: "Direct scanout", type: "enum", opts: en([0, 1, 2], ["Off", "On", "Auto"]), desc: "Fullscreen apps skip compositing" }
    ]

    function luaVal(v) { return typeof v === "boolean" ? (v ? "true" : "false") : typeof v === "number" ? String(v) : '"' + v + '"' }
    function luaSnippet(key, v) {
        const parts = key.replace(/-/g, "_").split(":")
        let s = parts[parts.length - 1] + " = " + luaVal(v)
        for (let i = parts.length - 2; i >= 0; i--) s = parts[i] + " = { " + s + " }"
        return "hl.config({ " + s + " })"
    }
    // try classic IPC first, fall back to Lua eval (Hyprland 0.55+ Lua mode rejects `keyword`)
    function hyprRun(kw, val, lua) {
        sh('r=$(hyprctl keyword "$1" "$2" 2>&1); case "$r" in ok*) ;; *) hyprctl eval "$3" >/dev/null 2>&1 ;; esac', [kw, val, lua])
    }
    function setOpt(def, v) {
        const o = Object.assign({}, opt); o[def.key] = v; opt = o
    }
    function commitOpt(def, v) {
        if (def.type === "float") v = Math.round(v * 100) / 100
        setOpt(def, v)
        store.hypr[def.key] = v
        hyprRun(def.key, typeof v === "boolean" ? (v ? "true" : "false") : String(v), luaSnippet(def.key, v))
        queueSave()
    }

    // ─────────────────────── persistence ───────────────────────
    function queueSave() { saved = "saving…"; saveTimer.restart() }
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: { root.writeAll(); root.saved = "saved" }
    }
    function tree() {
        const t = {}
        for (const k in store.hypr) {
            const parts = k.split(":"); let n = t
            for (let i = 0; i < parts.length - 1; i++) n = n[parts[i]] = n[parts[i]] || {}
            n[parts[parts.length - 1]] = store.hypr[k]
        }
        return t
    }
    function confBlock(n, ind) {
        let s = ""
        for (const k in n) s += typeof n[k] === "object" ? ind + k + " {\n" + confBlock(n[k], ind + "    ") + ind + "}\n" : ind + k + " = " + n[k] + "\n"
        return s
    }
    function luaBlock(n, ind) {
        const items = []
        for (const k in n) {
            const kk = k.replace(/-/g, "_")
            items.push(typeof n[k] === "object" ? ind + kk + " = {\n" + luaBlock(n[k], ind + "    ") + "\n" + ind + "}" : ind + kk + " = " + luaVal(n[k]))
        }
        return items.join(",\n")
    }
    function writeAll() {
        writeFile(storePath, JSON.stringify(store, null, 2))
        const t = tree(), m = store.monitors
        let out = ""
        if (luaMode) {
            out = "-- generated by settings.qml — do not edit by hand\n"
            if (Object.keys(t).length) out += "hl.config({\n" + luaBlock(t, "    ") + "\n})\n"
            for (const n in m) out += 'hl.monitor({ output = "' + n + '", mode = "' + m[n].mode + '", position = "' + m[n].position + '", scale = ' + m[n].scale + " })\n"
        } else {
            out = "# generated by settings.qml — do not edit by hand\n" + confBlock(t, "")
            for (const n in m) out += "monitor = " + n + "," + m[n].mode + "," + m[n].position + "," + m[n].scale + "\n"
        }
        writeFile(hyprFile, out)
    }
    readonly property string includeLine: luaMode
        ? 'dofile(os.getenv("HOME") .. "/.config/hypr/rice-settings.lua")'
        : "source = ~/.config/hypr/rice-settings.conf"

    FileView {
        path: root.storePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                    root.store = Object.assign({ hypr: {}, monitors: {}, ai: {} }, parsed)
                }
            } catch (e) {}
        }
    }
    FileView {
        path: root.palettePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyPalette(text())
    }

    // ───────────────────── system detection ─────────────────────
    Cmd {
        id: cmdSys
        script: `
echo "host=$(hostname)"; echo "model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
echo "kernel=$(uname -r)"; echo "threads=$(nproc)"; echo "load=$(cut -d' ' -f1 /proc/loadavg)"
echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} /SwapTotal/{st=$2} /SwapFree/{sf=$2} END{printf "memtotal=%d\\nmemused=%d\\nswaptotal=%d\\nswapused=%d\\n",t,t-a,st,st-sf}' /proc/meminfo
echo "uptime=$(uptime -p | sed 's/^up //')"
echo "gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
echo "profile=$(powerprofilesctl get 2>/dev/null)"
echo "profiles=$(powerprofilesctl list 2>/dev/null | grep -E '^[* ] [a-z-]+:' | tr -d '*: ' | tr '\\n' ',')"
for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type 2>/dev/null)" = x86_pkg_temp ] && echo "cputemp=$(( $(cat $z/temp) / 1000 ))"; done
for b in /sys/class/power_supply/BAT*; do [ -d "$b" ] || continue; echo "bat=$(cat $b/capacity)"; echo "batstatus=$(cat $b/status)"; echo "batlimit=$(cat $b/charge_control_end_threshold 2>/dev/null)"; break; done
echo "ollama_svc=$(systemctl --user is-active ollama 2>/dev/null)"
{ grep -q rice-settings "$HOME/.config/hypr/hyprland.lua" 2>/dev/null || grep -q rice-settings "$HOME/.config/hypr/hyprland.conf" 2>/dev/null; } && echo "inc=1" || echo "inc=0"
echo "gpu=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,driver_version --format=csv,noheader,nounits 2>/dev/null | head -1)"
command -v envycontrol >/dev/null && echo "gpumode=$(envycontrol --query 2>/dev/null)"
command -v supergfxctl >/dev/null && echo "gpumode=$(supergfxctl -g 2>/dev/null)"
for t in hyprctl nvidia-smi brightnessctl nmcli powerprofilesctl curl ollama hypridle hyprsunset sensors wl-copy notify-send jq; do command -v $t >/dev/null && echo "has_$t=1"; done
{ [ -x "$HOME/Projects/my-rice/scripts/gps-idle" ] && "$HOME/Projects/my-rice/scripts/gps-idle" is-running || pgrep -x hypridle >/dev/null; } && echo "run_hypridle=1"; pgrep -x hyprsunset >/dev/null && echo "run_hyprsunset=1"
[ -f "$HOME/.config/hypr/hyprland.lua" ] && echo "lua=1"
[ -n "$ANTHROPIC_API_KEY" ] && echo "key_anthropic=1"; [ -n "$OPENAI_API_KEY" ] && echo "key_openai=1"; [ -n "$OPENROUTER_API_KEY" ] && echo "key_openrouter=1"
`
        onDone: text => { root.sys = root.kv(text); root.luaMode = root.sys.lua === "1" }
    }
    Timer { interval: 3000; repeat: true; running: win.visible; triggeredOnStart: true; onTriggered: cmdSys.go() }

    Cmd {
        id: cmdHypr
        script: {
            const keys = root.schema.map(d => d.key).join(" ")
            return `
echo "##version"; hyprctl version -j 2>/dev/null | tr -d '\\n'; echo
echo "##monitors"; hyprctl monitors -j 2>/dev/null | tr -d '\\n'; echo
echo "##binds"; hyprctl binds -j 2>/dev/null | tr -d '\\n'; echo
for o in ${keys}; do echo "##opt $o"; hyprctl getoption $o -j 2>/dev/null | tr -d '\\n'; echo; done
`
        }
        onDone: text => root.parseHypr(text)
    }
    function hyprRefresh() { cmdHypr.go() }
    Timer { id: hyprDebounce; interval: 350; onTriggered: root.hyprRefresh() }
    Component.onCompleted: { hyprRefresh(); cmdFonts.go(); cmdPal.go() }
    Connections {
        target: Hyprland
        function onRawEvent(ev) { if (/^(monitor|configreloaded)/.test(ev.name)) hyprDebounce.restart() }
    }

    function parseHypr(txt) {
        const o = {}
        for (let p of txt.split("\n##")) {
            p = p.replace(/^##/, "")
            const nl = p.indexOf("\n")
            if (nl < 0) continue
            const head = p.slice(0, nl).trim(), body = p.slice(nl + 1).trim()
            let j
            try { j = JSON.parse(body) } catch (e) { continue }
            if (head === "version") hyprVersion = j.tag || j.version || ""
            else if (head === "monitors") { mons = j; if (pickRes === "" && j.length) pickRes = j[0].width + "x" + j[0].height }
            else if (head === "binds") binds = j
            else if (head.indexOf("opt ") === 0) {
                const key = head.slice(4), def = schema.find(d => d.key === key)
                let v = j.int !== undefined ? j.int : j.float !== undefined ? j.float : j.str !== undefined ? j.str : j.custom
                if (v === undefined || !def) continue
                if (def.type === "bool") v = !!Number(v)
                else if (def.type !== "str" && typeof v === "string") v = parseFloat(v.split(" ")[0])
                o[key] = v
            }
        }
        opt = o
    }

    Cmd {
        id: cmdFonts
        script: "fc-list : family 2>/dev/null | tr ',' '\\n' | sort -u"
        onDone: text => {
            const f = text.split("\n").map(s => s.trim())
            const has = n => f.indexOf(n) >= 0
            const ico = f.find(s => /^Material Symbols (Rounded|Outlined)/.test(s))
            root.iconOk = !!ico
            if (ico) root.iconFont = ico
            if (has("Inter")) root.uiFont = "Inter"
            else if (has("Plus Jakarta Sans")) root.uiFont = "Plus Jakarta Sans"
            const mono = f.find(s => /^JetBrains ?Mono( Nerd Font)?$/.test(s)) || f.find(s => /Mono/.test(s) && /Nerd/.test(s))
            if (mono) root.monoFont = mono
        }
    }
    Cmd {
        id: cmdPal
        script: `for f in "$HOME/.config/quickshell/gps-theme.json" "$HOME/.cache/wal/colors.json" "$HOME/.local/state/caelestia/scheme.json"; do [ -f "$f" ] && { echo "$f"; break; }; done`
        onDone: text => { if (text.trim() !== "") root.palettePath = text.trim() }
    }

    // ─────────────────────────── Wi-Fi ───────────────────────────
    Cmd {
        id: cmdWifi
        script: `
echo "radio=$(nmcli radio wifi 2>/dev/null)"
echo "ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -1)"
nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | sed 's/^/net=/'
`
        onDone: text => {
            const seen = {}, nets = []
            for (const l of text.split("\n")) {
                if (l.indexOf("radio=") === 0) root.wifiRadio = l.slice(6)
                else if (l.indexOf("ip=") === 0) root.wifiIp = l.slice(3)
                else if (l.indexOf("net=") === 0) {
                    const f = l.slice(4).replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
                    if (!f[1]) continue
                    const n = { active: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0, sec: f[3] || "" }
                    if (!seen[n.ssid] || seen[n.ssid].signal < n.signal || n.active) seen[n.ssid] = n
                }
            }
            for (const k in seen) nets.push(seen[k])
            nets.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
            root.wifi = nets
        }
    }
    Timer { interval: 8000; repeat: true; running: win.visible && root.page === 5; triggeredOnStart: true; onTriggered: cmdWifi.go() }

    // ────────────────────── services / config errors ──────────────────────
    Cmd {
        id: cmdSvc
        script: "systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null | awk '{print $1}'"
        onDone: text => root.services = text.split("\n").filter(s => s !== "")
    }
    Cmd {
        id: cmdErr
        script: "hyprctl configerrors 2>&1"
        onDone: text => root.cfgErrors = text.trim()
    }
    property var healthReport: null
    Cmd {
        id: cmdHealth
        script: '"' + repo + '/scripts/gps-doctor" --json 2>/dev/null || true'
        onDone: text => {
            try {
                root.healthReport = JSON.parse(text)
            } catch (e) {
                root.healthReport = null
            }
        }
    }

    // ───────────────────── AI / local inference ─────────────────────
    readonly property string aiEndpoint: store.ai.endpoint || "http://127.0.0.1:11434"
    readonly property string shellPath: home + "/Projects/my-rice/shell.qml"
    readonly property string modelsDir: home + "/.ollama/models"
    property string pullReq: ""
    property string aiMsg: ""
    Cmd {
        id: cmdAi
        args: [root.aiEndpoint]
        script: `
H="$1"
echo "##ver"; curl -s -m 1 "$H/api/version"; echo
echo "##tags"; curl -s -m 2 "$H/api/tags"; echo
echo "##ps"; curl -s -m 2 "$H/api/ps"; echo
echo "##lms"; curl -s -m 1 http://127.0.0.1:1234/v1/models | head -c 400; echo
echo "##llama"; curl -s -m 1 http://127.0.0.1:8080/v1/models | head -c 400; echo
`
        onDone: text => {
            const sec = {}
            for (let p of text.split("\n##")) {
                p = p.replace(/^##/, ""); const nl = p.indexOf("\n")
                if (nl > 0) sec[p.slice(0, nl).trim()] = p.slice(nl + 1).trim()
            }
            const pj = s => { try { return JSON.parse(s) } catch (e) { return null } }
            const ver = pj(sec.ver), tags = pj(sec.tags), ps = pj(sec.ps)
            const resident = {}
            if (ps && ps.models) ps.models.forEach(m => resident[m.name] = m.size_vram || 0)
            const models = ((tags && tags.models) || []).map(m => ({
                name: m.name, size: m.size || 0,
                params: (m.details && m.details.parameter_size) || "", quant: (m.details && m.details.quantization_level) || "",
                loaded: resident[m.name] !== undefined, vram: resident[m.name] || 0 }))
            root.ai = { ollama: !!ver, version: ver ? ver.version : "", models: models, lmstudio: !!pj(sec.lms), llamacpp: !!pj(sec.llama) }
        }
    }
    function aiRefresh() { cmdAi.go() }
    Timer { interval: 5000; repeat: true; running: win.visible && root.page === 7; triggeredOnStart: true; onTriggered: root.aiRefresh() }
    function ollamaPost(path, body) {
        sh('curl -s -m 60 "$1$2" -d "$3" >/dev/null', [aiEndpoint, path, JSON.stringify(body)])
        after(900, aiRefresh)
    }
    Process {
        id: pullProc
        property string model: ""
        command: ["curl", "-sN", root.aiEndpoint + "/api/pull", "-d", JSON.stringify({ model: model })]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const j = JSON.parse(line)
                    root.pull = { model: pullProc.model, status: j.status || "", total: j.total || 0, done: j.completed || 0, err: j.error || "" }
                } catch (e) {}
            }
        }
        onExited: { root.pull = Object.assign({}, root.pull, { finished: true }); root.aiRefresh() }
    }
    // Downloads are only started after a real free-space check on the models
    // volume (never auto-start a multi-GB pull blind).
    Cmd {
        id: cmdSpace
        args: [root.modelsDir]
        script: 'd="$1"; [ -d "$d" ] || d="$HOME/.ollama"; df -BG --output=avail "$d" 2>/dev/null | tail -1 | tr -dc "0-9"'
        onDone: text => {
            const gb = parseInt(text) || 0
            if (gb < 20) {
                root.pull = { model: root.pullReq, status: "", done: 0, total: 0, finished: true,
                    err: "Only " + gb + " GB free on the models volume - a pull needs at least 20 GB headroom." }
            } else {
                pullProc.model = root.pullReq
                root.pull = { model: root.pullReq, status: "starting\u2026", total: 0, done: 0 }
                pullProc.running = true
            }
        }
    }

    // ─────────────────────────── formatting ───────────────────────────
    function gb(kb) { return (kb / 1048576).toFixed(1) }
    function bytes(b) { return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : (b / 1e6).toFixed(0) + " MB" }
    function gpuInfo() {
        const f = (sys.gpu || "").split(",").map(s => s.trim())
        if (f.length < 7) return null
        return { name: f[0].replace("NVIDIA GeForce ", ""), util: +f[1], used: +f[2], total: +f[3], temp: +f[4], power: parseFloat(f[5]), driver: f[6] }
    }
    readonly property var gpu: (sys.gpu, gpuInfo())
    function mods(m) { const r = []; if (m & 64) r.push("Super"); if (m & 4) r.push("Ctrl"); if (m & 8) r.push("Alt"); if (m & 1) r.push("Shift"); return r }
    function modeList(m) {
        const out = []
        for (const s of (m.availableModes || [])) { const x = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s); if (x) out.push({ w: +x[1], h: +x[2], hz: parseFloat(x[3]) }) }
        return out
    }
    function resChips(m) {
        const seen = {}, r = []
        for (const x of modeList(m)) { const k = x.w + "x" + x.h; if (!seen[k]) { seen[k] = 1; r.push({ v: k, l: k }) } }
        return r
    }
    function hzChips(m, res) {
        const seen = {}, r = []
        for (const x of modeList(m)) if (x.w + "x" + x.h === res && !seen[Math.round(x.hz)]) { seen[Math.round(x.hz)] = 1; r.push({ v: x.hz, l: Math.round(x.hz) + " Hz" }) }
        return r
    }
    function scaleChips(m) {
        const base = [1, 1.25, 1.5, 1.75, 2, 2.5]
        if (base.indexOf(Math.round(m.scale * 100) / 100) < 0) base.push(Math.round(m.scale * 100) / 100)
        return base.sort((a, b) => a - b).map(v => ({ v: v, l: v + "×" }))
    }
    function applyMonitor(m, res, hz, scale) {
        const mode = res + "@" + Number(hz).toFixed(2), pos = m.x + "x" + m.y
        store.monitors[m.name] = { mode: mode, position: pos, scale: scale }
        hyprRun("monitor", m.name + "," + mode + "," + pos + "," + scale,
            'hl.monitor({ output = "' + m.name + '", mode = "' + mode + '", position = "' + pos + '", scale = ' + scale + " })")
        queueSave(); after(900, hyprRefresh)
    }
    function aiSet(k, v) { const s = Object.assign({}, store); s.ai = Object.assign({}, store.ai); s.ai[k] = v; store = s; queueSave() }

    // ═══════════════════════════ widgets ═══════════════════════════
    component T: Text { color: pal.text; font.family: root.uiFont; font.pixelSize: 13; elide: Text.ElideRight }
    component Dim: T { color: pal.dim; font.pixelSize: 12 }
    component Mono: T { font.family: root.monoFont; font.pixelSize: 11 }
    component Ico: Text { font.family: root.iconFont; font.pixelSize: 19; color: pal.dim; clip: true; horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: 24; Layout.maximumWidth: 24 }

    component Pill: Rectangle {
        property string text: ""
        property color tone: pal.primary
        property bool solid: false
        implicitWidth: pl.implicitWidth + 16; implicitHeight: 20; radius: 10
        color: solid ? tone : Qt.rgba(tone.r, tone.g, tone.b, 0.16)
        Mono { id: pl; anchors.centerIn: parent; text: parent.text; font.pixelSize: 10; font.bold: true; color: parent.solid ? pal.ink : parent.tone }
    }

    component Bar: Rectangle {
        property real value: 0
        property color tone: pal.primary
        Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: pal.surfaceHi
        Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.value)); height: parent.height; radius: 3; color: parent.tone
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
    }

    component Tgl: Rectangle {
        id: tg
        property bool on: false
        signal flipped(bool v)
        implicitWidth: 42; implicitHeight: 24; radius: 12
        color: on ? pal.primary : pal.surfaceHi
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            y: 3; x: tg.on ? 21 : 3; width: 18; height: 18; radius: 9
            color: tg.on ? pal.ink : pal.dim
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.flipped(!tg.on) }
    }

    component Sld: Item {
        id: s
        property real from: 0
        property real to: 100
        property real value: 0
        property real step: 1
        property real tmp: 0
        signal moved(real v)
        signal committed(real v)
        readonly property real vis: ma.pressed ? tmp : value
        readonly property real frac: to > from ? Math.max(0, Math.min(1, (vis - from) / (to - from))) : 0
        implicitWidth: 200; implicitHeight: 24
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: pal.surfaceHi
            Rectangle { width: parent.width * s.frac; height: parent.height; radius: 3; color: pal.primary } }
        Rectangle { x: s.frac * (s.width - width); anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8
            color: pal.text; border.width: 2; border.color: pal.primary }
        MouseArea {
            id: ma
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            function upd(mx) {
                const f = Math.max(0, Math.min(1, (mx - 8) / (width - 16)))
                let v = s.from + f * (s.to - s.from)
                v = Math.round(v / s.step) * s.step
                s.tmp = Math.max(s.from, Math.min(s.to, v)); s.moved(s.tmp)
            }
            onPressed: m => upd(m.x)
            onPositionChanged: m => { if (pressed) upd(m.x) }
            onReleased: s.committed(s.tmp)
        }
    }

    component Chips: Flow {
        id: ch
        property var model: []          // [{v, l}]
        property var current
        signal picked(var v)
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: ch.model
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: String(modelData.v) === String(ch.current)
                implicitWidth: lb.implicitWidth + 22; implicitHeight: 28; radius: 14
                color: sel ? pal.primary : pal.surfaceHi
                T { id: lb; anchors.centerIn: parent; text: parent.modelData.l; font.pixelSize: 12; color: parent.sel ? pal.ink : pal.text }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.picked(parent.modelData.v) }
            }
        }
    }

    component Btn: Rectangle {
        id: b
        property string text: ""
        property string icon: ""
        property bool accent: false
        property bool danger: false
        signal clicked()
        implicitWidth: rw.implicitWidth + 24; implicitHeight: 30; radius: 15
        color: accent ? pal.primary : danger ? Qt.rgba(pal.error.r, pal.error.g, pal.error.b, 0.2) : pal.surfaceHi
        opacity: ma.containsMouse ? 0.85 : 1
        RowLayout { id: rw; anchors.centerIn: parent; spacing: 6
            Ico { visible: b.icon !== ""; text: b.icon; font.pixelSize: 16; color: b.accent ? pal.ink : b.danger ? pal.error : pal.text }
            T { visible: b.text !== ""; text: b.text; font.pixelSize: 12; color: b.accent ? pal.ink : b.danger ? pal.error : pal.text } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    component Field: Rectangle {
        id: f
        property string text: ""
        property string hint: ""
        property bool secret: false
        signal accepted(string t)
        implicitWidth: 200; implicitHeight: 30; radius: 15; color: pal.surfaceHi
        border.width: ti.activeFocus ? 1 : 0; border.color: pal.primary
        T { visible: ti.text === "" && !ti.activeFocus; anchors.verticalCenter: parent.verticalCenter; x: 12; text: f.hint; color: pal.dim; font.pixelSize: 12 }
        TextInput {
            id: ti
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
            text: f.text; color: pal.text; font.family: root.uiFont; font.pixelSize: 12; clip: true
            echoMode: f.secret ? TextInput.Password : TextInput.Normal; selectByMouse: true
            onAccepted: f.accepted(text)
            onActiveFocusChanged: if (!activeFocus && text !== f.text) f.accepted(text)
        }
    }

    component Card: Rectangle {
        id: card
        property string title: ""
        property string icon: ""
        property string badge: ""
        default property alias body: bodyCol.data
        Layout.fillWidth: true
        radius: 18; color: pal.surface
        implicitHeight: inner.implicitHeight + 28
        ColumnLayout {
            id: inner
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
            spacing: 10
            RowLayout { visible: card.title !== ""; spacing: 8
                Ico { visible: card.icon !== ""; text: card.icon; color: pal.primary }
                T { text: card.title; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Pill { visible: card.badge !== ""; text: card.badge } }
            ColumnLayout { id: bodyCol; Layout.fillWidth: true; spacing: 10 }
        }
    }

    component SRow: RowLayout {
        property string label: ""
        property string desc: ""
        default property alias ctl: slot.data
        Layout.fillWidth: true; spacing: 12
        ColumnLayout { Layout.fillWidth: true; spacing: 1
            T { text: parent.parent.label; Layout.fillWidth: true }
            Dim { visible: parent.parent.desc !== ""; text: parent.parent.desc; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone } }
        RowLayout { id: slot; spacing: 8 }
    }

    component Stat: Rectangle {
        property string title: ""
        property string icon: ""
        property string value: "—"
        property string sub: ""
        property string foot: ""
        property real bar: -1
        property color tone: pal.primary
        Layout.fillWidth: true; Layout.fillHeight: true
        radius: 18; color: pal.surface; implicitHeight: sc.implicitHeight + 28
        ColumnLayout { id: sc; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 4
            RowLayout { Mono { text: parent.parent.parent.title.toUpperCase(); color: pal.dim; Layout.fillWidth: true }
                Ico { text: parent.parent.parent.icon; color: parent.parent.parent.tone } }
            T { text: parent.parent.value; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Dim { text: parent.parent.sub; Layout.fillWidth: true }
            Bar { visible: parent.parent.bar >= 0; value: parent.parent.bar; tone: parent.parent.tone; Layout.topMargin: 4 }
            Mono { text: parent.parent.foot; color: parent.parent.tone; Layout.fillWidth: true } }
    }

    component PageBase: Flickable {
        id: pb
        default property alias content: col.data
        property string title: ""
        property string sub: ""
        contentWidth: width; contentHeight: col.implicitHeight + 24
        clip: true; boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.VerticalFlick
        ColumnLayout { id: col; x: 0; width: pb.width - 6; spacing: 12 }
    }

    // generic row driven by the schema
    component OptRow: SRow {
        id: r
        required property var modelData
        readonly property var def: modelData
        readonly property var val: root.opt[def.key]
        label: def.label; desc: def.desc || ""
        visible: val !== undefined
        Tgl { visible: r.def.type === "bool"; on: r.val === true; onFlipped: v => root.commitOpt(r.def, v) }
        Dim { visible: r.def.type === "int" || r.def.type === "float"; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
            text: r.val === undefined ? "" : (r.def.type === "float" ? Number(r.val).toFixed(2) : r.val) + (r.def.unit ? " " + r.def.unit : "") }
        Sld { visible: r.def.type === "int" || r.def.type === "float"; Layout.preferredWidth: 190
            from: r.def.min || 0; to: r.def.max || 1; step: r.def.step || 1; value: r.val === undefined ? 0 : r.val
            onMoved: v => root.setOpt(r.def, v); onCommitted: v => root.commitOpt(r.def, v) }
        Chips { visible: r.def.type === "enum"; Layout.preferredWidth: 300; model: r.def.opts || []; current: r.val; onPicked: v => root.commitOpt(r.def, v) }
        Field { visible: r.def.type === "str"; Layout.preferredWidth: 220; text: r.val === undefined ? "" : String(r.val); onAccepted: t => { if (t !== r.val) root.commitOpt(r.def, t) } }
    }
    component OptCard: Card {
        property string group: ""
        property string ic: ""
        title: group; icon: ic
        visible: root.schema.some(d => d.group === group && root.opt[d.key] !== undefined)
        Repeater { model: root.schema.filter(d => d.group === group); delegate: OptRow {} }
    }

    // ═══════════════════════════ window ═══════════════════════════
    readonly property var pages: [
        { icon: "dashboard", title: "Overview", sub: "Live status of this machine" },
        { icon: "monitor", title: "Display", sub: "Monitors, resolution, refresh rate, scaling" },
        { icon: "palette", title: "Appearance", sub: "Wallpaper palette, gaps, rounding, blur" },
        { icon: "keyboard", title: "Input", sub: "Keyboard, mouse and touchpad" },
        { icon: "volume_up", title: "Audio", sub: "PipeWire devices and app volumes" },
        { icon: "wifi", title: "Network", sub: "Wi-Fi and Bluetooth" },
        { icon: "bolt", title: "Power & GPU", sub: "Profiles, battery, NVIDIA telemetry" },
        { icon: "psychology", title: "AI & Models", sub: "Local inference engines and models" },
        { icon: "keyboard_command_key", title: "Keybinds", sub: "Every bind Hyprland has loaded" },
        { icon: "memory", title: "System", sub: "Services, tools, config integration" },
        { icon: "health_and_safety", title: "System Health", sub: "Session essentials and doctor diagnostics" }
    ]

    IpcHandler {
        target: "settings"
        function toggle() { root.shown = !root.shown }
        function open(name: string) {
            const i = root.pages.findIndex(p => p.title.toLowerCase().indexOf(name.toLowerCase()) === 0)
            if (i >= 0) root.page = i
            root.shown = true
        }
    }

    FloatingWindow {
        id: win
        visible: root.shown
        onVisibleChanged: root.shown = visible
        title: "Settings Hub"
        implicitWidth: 1120; implicitHeight: 720
        color: "transparent"

        Rectangle {
            anchors.fill: parent; color: pal.bg; opacity: 0.97
        }

        RowLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 12

            // ───────── sidebar ─────────
            Rectangle {
                Layout.preferredWidth: 220; Layout.fillHeight: true; radius: 20; color: pal.surface
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 4
                    RowLayout { Layout.bottomMargin: 10; Layout.leftMargin: 4; spacing: 8
                        Ico { text: "tune"; color: pal.primary; font.pixelSize: 22 }
                        T { text: "Settings Hub"; font.pixelSize: 17; font.weight: Font.DemiBold } }
                    Repeater {
                        model: root.pages
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool sel: root.page === index
                            Layout.fillWidth: true; implicitHeight: 38; radius: 19
                            color: sel ? pal.primary : (hv.containsMouse ? pal.surfaceHi : "transparent")
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 12; spacing: 10
                                Ico { text: parent.parent.modelData.icon; color: parent.parent.sel ? pal.ink : pal.dim; font.pixelSize: 18 }
                                T { text: parent.parent.modelData.title; color: parent.parent.sel ? pal.ink : pal.text; Layout.fillWidth: true } }
                            MouseArea { id: hv; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.page = parent.index }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    // GPU memory budget (only when an NVIDIA GPU is detected)
                    ColumnLayout { visible: root.gpu !== null; Layout.fillWidth: true; spacing: 4
                        RowLayout { Mono { text: "VRAM"; color: pal.dim; Layout.fillWidth: true }
                            Mono { text: root.gpu ? (root.gpu.used / 1024).toFixed(1) + " / " + (root.gpu.total / 1024).toFixed(1) + " GB" : ""; color: pal.primary } }
                        Bar { value: root.gpu ? root.gpu.used / root.gpu.total : 0; tone: pal.secondary }
                        Mono { text: root.gpu ? root.gpu.name : ""; color: pal.dim; Layout.fillWidth: true } }
                }
            }

            // ───────── content ─────────
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10

                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 64; radius: 20; color: pal.surface
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 10
                        ColumnLayout { spacing: 0; Layout.fillWidth: true
                            Mono { text: "SUBSYSTEM · " + root.pages[root.page].title.toUpperCase(); color: pal.primary; font.pixelSize: 10 }
                            T { text: root.pages[root.page].sub; font.pixelSize: 18; font.weight: Font.DemiBold } }
                        Pill { text: root.saved === "" ? "live" : root.saved; tone: root.saved === "saving…" ? pal.tertiary : pal.primary }
                        Pill { visible: root.hyprVersion !== ""; text: "hyprland " + root.hyprVersion; tone: pal.secondary }
                        Pill { text: root.luaMode ? "lua config" : "hyprlang"; tone: pal.tertiary }
                        Btn { icon: "close"; onClicked: root.shown = false } }
                }

                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: root.page

                    // ════════ 0 · OVERVIEW ════════
                    PageBase {
                        GridLayout { columns: 3; uniformCellWidths: true; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                            Stat { title: "Device"; icon: "laptop"; value: root.sys.model || root.sys.host || "—"; sub: "kernel " + (root.sys.kernel || "—"); foot: "up " + (root.sys.uptime || "—") }
                            Stat { title: "CPU"; icon: "developer_board"; tone: pal.secondary
                                value: (root.sys.cpu || "—").replace(/\((R|TM)\)/g, "").replace(/\s+CPU.*$/, "")
                                sub: (root.sys.threads || "?") + " threads · " + (root.sys.gov || "n/a") + " · load " + (root.sys.load || "?")
                                foot: root.sys.cputemp ? root.sys.cputemp + " °C" : ""; bar: root.sys.cputemp ? root.sys.cputemp / 100 : -1 }
                            Stat { title: "Memory"; icon: "memory"; tone: pal.tertiary
                                value: root.gb(+root.sys.memused || 0) + " / " + root.gb(+root.sys.memtotal || 0) + " GB"
                                sub: "swap " + root.gb(+root.sys.swapused || 0) + " / " + root.gb(+root.sys.swaptotal || 0) + " GB"
                                bar: (+root.sys.memtotal) ? root.sys.memused / root.sys.memtotal : 0 }
                            Stat { title: "GPU"; icon: "view_in_ar"; visible: root.gpu !== null
                                value: root.gpu ? root.gpu.name : "—"; sub: root.gpu ? "driver " + root.gpu.driver + " · " + root.gpu.util + "% load" : ""
                                foot: root.gpu ? root.gpu.temp + " °C · " + root.gpu.power.toFixed(0) + " W" : ""; bar: root.gpu ? root.gpu.util / 100 : -1 }
                            Stat { title: "Display"; icon: "monitor"; tone: pal.secondary; visible: root.mon !== null
                                value: root.mon ? root.mon.name + " · " + root.mon.width + "×" + root.mon.height : "—"
                                sub: root.mon ? Number(root.mon.refreshRate).toFixed(0) + " Hz · scale " + root.mon.scale + "×" : ""
                                foot: root.mon ? "logical " + Math.round(root.mon.width / root.mon.scale) + "×" + Math.round(root.mon.height / root.mon.scale) : "" }
                            Stat { title: "Power"; icon: "battery_charging_full"; tone: pal.tertiary; visible: !!root.sys.bat
                                value: (root.sys.bat || "?") + "% · " + (root.sys.batstatus || "")
                                sub: "profile " + (root.sys.profile || "n/a"); bar: root.sys.bat ? root.sys.bat / 100 : -1 }
                        }
                        Card { title: "Quick toggles"; icon: "toggle_on"
                            SRow { label: "Wi-Fi"; visible: root.sys["has_nmcli"] === "1"
                                Tgl { on: root.wifiRadio === "enabled"; onFlipped: v => { root.sh("nmcli radio wifi " + (v ? "on" : "off")); root.wifiRadio = v ? "enabled" : "disabled" } } }
                            SRow { label: "Bluetooth"; visible: root.adapter !== null
                                Tgl { on: root.adapter ? root.adapter.enabled : false; onFlipped: v => { if (root.adapter) root.adapter.enabled = v } } }
                            SRow { label: "Night light"; desc: "hyprsunset"; visible: root.sys["has_hyprsunset"] === "1"
                                Tgl { on: root.sys.run_hyprsunset === "1"; onFlipped: v => root.nightLight(v, 4500) } }
                            SRow { label: "Idle lock & suspend"; desc: "hypridle"; visible: root.sys["has_hypridle"] === "1"
                                Tgl { on: root.sys.run_hypridle === "1"; onFlipped: v => root.daemon("hypridle", v) } }
                            SRow { label: "Animations"; visible: root.opt["animations:enabled"] !== undefined
                                Tgl { on: root.opt["animations:enabled"] === true; onFlipped: v => root.commitOpt(root.schema.find(d => d.key === "animations:enabled"), v) } }
                            SRow { label: "Background blur"; visible: root.opt["decoration:blur:enabled"] !== undefined
                                Tgl { on: root.opt["decoration:blur:enabled"] === true; onFlipped: v => root.commitOpt(root.schema.find(d => d.key === "decoration:blur:enabled"), v) } }
                            SRow { label: "Brightness"; visible: Brightness.available
                                Dim { text: Brightness.percent + "%"; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 220; from: 1; to: 100; value: Brightness.percent
                                    onCommitted: v => Brightness.setPercent(Math.round(v)) } }
                        }
                    }

                    // ════════ 1 · DISPLAY ════════
                    PageBase {
                        Card { title: "Monitors"; icon: "monitor"; badge: root.mons.length + " detected"
                            Chips { visible: root.mons.length > 1; model: root.mons.map((m, i) => ({ v: i, l: m.name + (m.model ? " · " + m.model : "") })); current: root.monIdx
                                onPicked: v => { root.monIdx = v; root.pickRes = root.mons[v].width + "x" + root.mons[v].height } }
                            Dim { visible: root.mon !== null; Layout.fillWidth: true
                                text: root.mon ? (root.mon.description || root.mon.name) + " · position " + root.mon.x + "×" + root.mon.y : "" }
                            Dim { visible: root.mon === null; text: "No monitor data — is hyprctl available?" }
                        }
                        Card { title: "Mode"; icon: "aspect_ratio"; visible: root.mon !== null
                            T { text: "Resolution" }
                            Chips { model: root.mon ? root.resChips(root.mon) : []; current: root.pickRes; onPicked: v => root.pickRes = v }
                            T { text: "Refresh rate" }
                            Chips { model: root.mon ? root.hzChips(root.mon, root.pickRes) : []
                                current: root.mon && root.pickRes === root.mon.width + "x" + root.mon.height ? root.mon.refreshRate : -1
                                onPicked: v => root.applyMonitor(root.mon, root.pickRes, v, root.mon.scale) }
                            T { text: "Scale" }
                            Chips { model: root.mon ? root.scaleChips(root.mon) : []; current: root.mon ? Math.round(root.mon.scale * 100) / 100 : 1
                                onPicked: v => root.applyMonitor(root.mon, root.mon.width + "x" + root.mon.height, root.mon.refreshRate, v) }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: root.mon ? "Pick a resolution, then a refresh rate to apply it. Current: " + root.mon.width + "×" + root.mon.height + " @ " + Number(root.mon.refreshRate).toFixed(2) + " Hz, logical " + Math.round(root.mon.width / root.mon.scale) + "×" + Math.round(root.mon.height / root.mon.scale) : "" }
                        }
                        Card { title: "Brightness & colour"; icon: "brightness_6"
                            SRow { label: "Screen brightness"; visible: Brightness.available
                                Dim { text: Brightness.percent + "%"; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 240; from: 1; to: 100; value: Brightness.percent
                                    onCommitted: v => Brightness.setPercent(Math.round(v)) } }
                            Dim { visible: !Brightness.available; text: "No adjustable backlight device found." }
                            SRow { label: "Night light"; desc: "Warm colour temperature via hyprsunset"; visible: root.sys["has_hyprsunset"] === "1"
                                Tgl { on: root.sys.run_hyprsunset === "1"; onFlipped: v => root.nightLight(v, 4500) } }
                        }
                        OptCard { group: "Display & Sync"; ic: "sync" }
                    }

                    // ════════ 2 · APPEARANCE ════════
                    PageBase {
                        Card { title: "Wallpaper palette"; icon: "palette"; badge: root.paletteSource
                            RowLayout { spacing: 10
                                Repeater { model: [pal.primary, pal.secondary, pal.tertiary, pal.error, pal.surfaceHi, pal.surface, pal.bg]
                                    delegate: Rectangle { required property var modelData; width: 34; height: 34; radius: 17; color: modelData; border.width: 1; border.color: pal.line } }
                                Item { Layout.fillWidth: true } }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: root.palettePath !== "" ? "Following " + root.palettePath + " — colours update the moment your wallpaper tool rewrites it." : "No palette file found (looked for ~/.config/quickshell/gps-theme.json, pywal colors.json and Caelestia scheme.json). Using the built-in fallback." } }
                        OptCard { group: "Layout & Gaps"; ic: "grid_view" }
                        OptCard { group: "Decoration"; ic: "rounded_corner" }
                        OptCard { group: "Effects"; ic: "blur_on" }
                    }

                    // ════════ 3 · INPUT ════════
                    PageBase {
                        OptCard { group: "Keyboard"; ic: "keyboard" }
                        OptCard { group: "Mouse & Touchpad"; ic: "mouse" }
                    }

                    // ════════ 4 · AUDIO ════════
                    PageBase {
                        PwObjectTracker { objects: Pipewire.nodes.values }
                        Card { title: "Output"; icon: "volume_up"; badge: root.sink ? root.sink.description : "no sink"
                            SRow { label: "Volume"; visible: root.sink !== null && root.sink.audio !== null
                                Dim { text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : ""; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 240; from: 0; to: 1.5; step: 0.01; value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                                    onMoved: v => { if (root.sink && root.sink.audio) root.sink.audio.volume = v } }
                                Tgl { on: root.sink && root.sink.audio ? !root.sink.audio.muted : false; onFlipped: v => { if (root.sink && root.sink.audio) root.sink.audio.muted = !v } } }
                            Chips { model: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream).map(n => ({ v: n.id, l: n.description || n.name }))
                                current: root.sink ? root.sink.id : -1
                                onPicked: v => { const n = Pipewire.nodes.values.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSink = n } } }
                        Card { title: "Input"; icon: "mic"; badge: root.source ? root.source.description : "no source"
                            SRow { label: "Microphone"; visible: root.source !== null && root.source.audio !== null
                                Dim { text: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) + "%" : ""; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 240; from: 0; to: 1.5; step: 0.01; value: root.source && root.source.audio ? root.source.audio.volume : 0
                                    onMoved: v => { if (root.source && root.source.audio) root.source.audio.volume = v } }
                                Tgl { on: root.source && root.source.audio ? !root.source.audio.muted : false; onFlipped: v => { if (root.source && root.source.audio) root.source.audio.muted = !v } } }
                            Chips { model: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream).map(n => ({ v: n.id, l: n.description || n.name }))
                                current: root.source ? root.source.id : -1
                                onPicked: v => { const n = Pipewire.nodes.values.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSource = n } } }
                        Card { title: "Applications"; icon: "apps"
                            Repeater { model: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
                                delegate: SRow {
                                    required property var modelData
                                    label: modelData.properties["application.name"] || modelData.description || modelData.name
                                    desc: modelData.properties["media.name"] || ""
                                    Sld { Layout.preferredWidth: 220; from: 0; to: 1.5; step: 0.01; value: modelData.audio.volume; onMoved: v => modelData.audio.volume = v }
                                    Tgl { on: !modelData.audio.muted; onFlipped: v => modelData.audio.muted = !v } } }
                            Dim { visible: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink).length === 0; text: "Nothing is playing audio right now." } }
                    }

                    // ════════ 5 · NETWORK ════════
                    PageBase {
                        Card { title: "Wi-Fi"; icon: "wifi"; badge: root.wifiIp
                            visible: root.sys["has_nmcli"] === "1"
                            SRow { label: "Wi-Fi radio"
                                Btn { icon: "refresh"; text: "Scan"; onClicked: { root.sh("nmcli dev wifi rescan"); root.after(2500, cmdWifi.go) } }
                                Tgl { on: root.wifiRadio === "enabled"; onFlipped: v => { root.sh("nmcli radio wifi " + (v ? "on" : "off")); root.wifiRadio = v ? "enabled" : "disabled"; root.after(1500, cmdWifi.go) } } }
                            Repeater { model: root.wifi
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true; implicitHeight: 38; radius: 12
                                    color: modelData.active ? Qt.rgba(pal.primary.r, pal.primary.g, pal.primary.b, 0.14) : (root.wifiSel === modelData.ssid ? pal.surfaceHi : "transparent")
                                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                        Ico { text: parent.parent.modelData.signal > 66 ? "network_wifi" : parent.parent.modelData.signal > 33 ? "network_wifi_3_bar" : "network_wifi_1_bar"; color: parent.parent.modelData.active ? pal.primary : pal.dim }
                                        T { text: parent.parent.modelData.ssid; Layout.fillWidth: true }
                                        Ico { visible: parent.parent.modelData.sec !== ""; text: "lock"; font.pixelSize: 15 }
                                        Dim { text: parent.parent.modelData.signal + "%" }
                                        Pill { visible: parent.parent.modelData.active; text: "connected" } }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.wifiSel = parent.modelData.ssid } } }
                            RowLayout { visible: root.wifiSel !== ""; spacing: 8
                                T { text: root.wifiSel; font.weight: Font.DemiBold }
                                Field { id: wifiPass; hint: "password (leave empty for saved)"; secret: true; Layout.preferredWidth: 230 }
                                Btn { accent: true; text: "Connect"; onClicked: {
                                    root.sh('nmcli -w 20 dev wifi connect "$1" ${2:+password "$2"} >/dev/null 2>&1 || { command -v notify-send >/dev/null && notify-send "Wi-Fi" "Could not connect to $1"; }', [root.wifiSel, wifiPass.text])
                                    root.after(4000, cmdWifi.go) } }
                                Btn { text: "Disconnect"; onClicked: { root.sh('nmcli dev disconnect "$(nmcli -t -f DEVICE,TYPE dev | awk -F: \'$2=="wifi"{print $1; exit}\')"'); root.after(1500, cmdWifi.go) } } } }
                        Dim { visible: root.sys["has_nmcli"] !== "1"; text: "NetworkManager (nmcli) was not found." }
                        Card { title: "Bluetooth"; icon: "bluetooth"; badge: root.adapter ? root.adapter.name || "" : "no adapter"
                            visible: root.adapter !== null
                            SRow { label: "Bluetooth power"
                                Btn { icon: root.adapter && root.adapter.discovering ? "stop" : "search"; text: root.adapter && root.adapter.discovering ? "Stop scan" : "Scan"
                                    onClicked: { if (root.adapter) root.adapter.discovering = !root.adapter.discovering } }
                                Tgl { on: root.adapter ? root.adapter.enabled : false; onFlipped: v => { if (root.adapter) root.adapter.enabled = v } } }
                            Repeater { model: root.adapter ? root.adapter.devices.values : []
                                delegate: SRow {
                                    required property var modelData
                                    label: modelData.name || modelData.address
                                    desc: (modelData.paired ? "paired" : "new device") + (modelData.batteryAvailable ? " · battery " + Math.round(modelData.battery * 100) + "%" : "")
                                    Btn { accent: !modelData.connected; text: modelData.connected ? "Disconnect" : "Connect"; onClicked: modelData.connected = !modelData.connected } } } }
                    }

                    // ════════ 6 · POWER & GPU ════════
                    PageBase {
                        Card { title: "Power profile"; icon: "speed"; badge: root.sys.profile || "n/a"
                            visible: root.sys["has_powerprofilesctl"] === "1"
                            Chips { model: (root.sys.profiles || "").split(",").filter(s => s !== "").map(s => ({ v: s, l: s }))
                                current: root.sys.profile; onPicked: v => { root.sh("powerprofilesctl set " + v); root.after(500, cmdSys.go) } }
                            Dim { visible: !!root.sys.gov; text: "CPU governor: " + root.sys.gov } }
                        Card { title: "Battery"; icon: "battery_full"; visible: !!root.sys.bat
                            Bar { value: (+root.sys.bat || 0) / 100; tone: (+root.sys.bat) < 20 ? pal.error : pal.primary }
                            T { text: root.sys.bat + "% · " + root.sys.batstatus }
                            Dim { visible: !!root.sys.batlimit; text: "Charge limit: " + root.sys.batlimit + "% (set by firmware / a root service)" } }
                        Card { title: "NVIDIA GPU"; icon: "view_in_ar"; badge: root.gpu ? root.gpu.name : "not detected"
                            visible: root.gpu !== null
                            GridLayout { columns: 2; Layout.fillWidth: true; columnSpacing: 20; rowSpacing: 6
                                Dim { text: "Utilisation" } T { text: root.gpu ? root.gpu.util + " %" : ""; Layout.alignment: Qt.AlignRight }
                                Dim { text: "VRAM" } T { text: root.gpu ? root.gpu.used + " / " + root.gpu.total + " MiB" : ""; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Temperature" } T { text: root.gpu ? root.gpu.temp + " °C" : ""; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Power draw" } T { text: root.gpu ? root.gpu.power.toFixed(1) + " W" : ""; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Driver" } T { text: root.gpu ? root.gpu.driver : ""; Layout.alignment: Qt.AlignRight }
                                Dim { visible: !!root.sys.gpumode; text: "Graphics mode" } T { visible: !!root.sys.gpumode; text: root.sys.gpumode || ""; Layout.alignment: Qt.AlignRight } }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: root.sys.gpumode ? "Switching graphics mode needs root and a reboot — run it in a terminal (Fish): sudo envycontrol -s hybrid" : "No envycontrol/supergfxctl found, so GPU mode is managed by the firmware/driver." } }
                        Card { title: "Idle daemon"; icon: "bedtime"; visible: root.sys["has_hypridle"] === "1"
                            SRow { label: "hypridle"; desc: "Locks and suspends after inactivity"
                                Tgl { on: root.sys.run_hypridle === "1"; onFlipped: v => root.daemon("hypridle", v) } } }
                        OptCard { group: "NVIDIA & Rendering"; ic: "tune" }
                    }

                    // ════════ 7 · AI & MODELS ════════
                    PageBase {
                        Card { title: "Inference engines"; icon: "hub"
                            SRow { label: "Ollama"; desc: root.ai.ollama ? "v" + root.ai.version + " · " + root.aiEndpoint + " · service: " + (root.sys.ollama_svc || "n/a") : "not reachable at " + root.aiEndpoint + " · service: " + (root.sys.ollama_svc || "n/a")
                                Pill { text: root.ai.ollama ? "online" : root.sys["has_ollama"] === "1" ? (root.sys.ollama_svc === "active" ? "service active · no answer" : "service stopped") : "missing"; tone: root.ai.ollama ? pal.primary : pal.tertiary }
                                Btn { visible: !root.ai.ollama && root.sys["has_ollama"] === "1"; text: "Start service"; onClicked: { root.sh("systemctl --user start ollama"); root.after(1800, root.aiRefresh) } }
                                Btn { visible: root.ai.ollama || root.sys.ollama_svc === "active"; danger: true; text: "Stop service"; onClicked: { root.sh("systemctl --user stop ollama"); root.after(1200, root.aiRefresh) } } }
                            SRow { label: "Endpoint"; desc: "Probe target for this page. The chat bridge is fixed to loopback 127.0.0.1:11434; only loopback URLs are accepted here."
                                Field { Layout.preferredWidth: 260; text: root.aiEndpoint; onAccepted: t => { const v = t.trim(); if (v === root.aiEndpoint) return; if (/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/.test(v)) { root.aiMsg = ""; root.aiSet("endpoint", v) } else root.aiMsg = "Rejected: only loopback URLs (127.0.0.1 / localhost / [::1]) are allowed."; root.after(300, root.aiRefresh) } } }
                            Dim { visible: root.aiMsg !== ""; text: root.aiMsg; color: pal.error; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                            SRow { label: "LM Studio"; desc: "OpenAI-compatible · port 1234"; Pill { text: root.ai.lmstudio ? "online" : "offline"; tone: root.ai.lmstudio ? pal.primary : pal.dim } }
                            SRow { label: "llama.cpp server"; desc: "OpenAI-compatible · port 8080"; Pill { text: root.ai.llamacpp ? "online" : "offline"; tone: root.ai.llamacpp ? pal.primary : pal.dim } }
                            RowLayout { spacing: 8
                                Dim { text: "Cloud keys in environment:" }
                                Pill { text: "anthropic"; tone: root.sys.key_anthropic === "1" ? pal.primary : pal.dim }
                                Pill { text: "openai"; tone: root.sys.key_openai === "1" ? pal.primary : pal.dim }
                                Pill { text: "openrouter"; tone: root.sys.key_openrouter === "1" ? pal.primary : pal.dim } } }
                        Card { title: "Local models"; icon: "deployed_code"; badge: root.ai.models.length + " pulled"
                            Repeater { model: root.ai.models
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 10
                                    ColumnLayout { spacing: 0; Layout.fillWidth: true
                                        T { text: parent.parent.modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Dim { text: [parent.parent.modelData.params, parent.parent.modelData.quant, root.bytes(parent.parent.modelData.size)].filter(s => s).join(" · ")
                                            + (parent.parent.modelData.loaded ? " · " + root.bytes(parent.parent.modelData.vram) + " in VRAM" : ""); Layout.fillWidth: true } }
                                    Pill { visible: store.ai.model === parent.modelData.name; text: "default" ; tone: pal.secondary }
                                    Btn { text: parent.modelData.loaded ? "Unload" : "Load"
                                        onClicked: root.ollamaPost("/api/generate", { model: parent.modelData.name, keep_alive: parent.modelData.loaded ? 0 : "30m" }) }
                                    Btn { danger: true; icon: "delete"; text: root.confirmDel === parent.modelData.name ? "Sure?" : ""
                                        onClicked: {
                                            if (root.confirmDel === parent.modelData.name) {
                                                root.sh('curl -s -X DELETE "$1/api/delete" -d "$2" >/dev/null', [root.aiEndpoint, JSON.stringify({ model: parent.modelData.name })])
                                                root.confirmDel = ""; root.after(900, root.aiRefresh)
                                            } else root.confirmDel = parent.modelData.name } } } }
                            Dim { visible: root.ai.models.length === 0; text: root.ai.ollama ? "No models pulled yet." : "Start Ollama to list models." }
                            RowLayout { spacing: 8; Layout.topMargin: 6
                                Field { id: pullName; hint: "model to pull, e.g. llama3.2:3b"; Layout.fillWidth: true }
                                Btn { accent: true; icon: "download"; text: root.pullReq !== "" && !root.pull.finished ? "Pulling…" : "Pull"
                                    onClicked: { if (pullName.text !== "" && !pullProc.running) { root.pullReq = pullName.text.trim(); root.pull = { model: root.pullReq, status: "checking disk\u2026", total: 0, done: 0 }; cmdSpace.go() } } } }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: "Pulls run against the local Ollama service and free space on " + root.modelsDir + " is verified before the download starts." }
                            ColumnLayout { visible: root.pull.model !== undefined && !root.pull.finished; Layout.fillWidth: true; spacing: 3
                                Mono { text: (root.pull.model || "") + " · " + (root.pull.err || root.pull.status || ""); Layout.fillWidth: true; color: root.pull.err ? pal.error : pal.text }
                                Bar { value: root.pull.total > 0 ? root.pull.done / root.pull.total : 0 } } }
                        Card { title: "Assistant defaults"; icon: "tune"; badge: "for your assistant"
                            T { text: "Default model" }
                            Chips { model: root.ai.models.map(m => ({ v: m.name, l: m.name })); current: store.ai.model; onPicked: v => root.aiSet("model", v) }
                            SRow { label: "Context window"
                                Dim { text: (store.ai.ctx || 8192) + " tokens"; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 240; from: 2048; to: 32768; step: 1024; value: store.ai.ctx || 8192; onCommitted: v => root.aiSet("ctx", v) } }
                            SRow { label: "Temperature"
                                Dim { text: Number(store.ai.temp === undefined ? 0.7 : store.ai.temp).toFixed(2); Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                                Sld { Layout.preferredWidth: 240; from: 0; to: 1.5; step: 0.05; value: store.ai.temp === undefined ? 0.7 : store.ai.temp; onCommitted: v => root.aiSet("temp", Math.round(v * 100) / 100) } }
                            T { text: "System prompt" }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 110; radius: 14; color: pal.surfaceHi
                                TextEdit { anchors.fill: parent; anchors.margins: 10; wrapMode: TextEdit.Wrap; selectByMouse: true
                                    color: pal.text; font.family: root.monoFont; font.pixelSize: 11
                                    text: store.ai.system || ""
                                    onActiveFocusChanged: if (!activeFocus && text !== (store.ai.system || "")) root.aiSet("system", text) } }
                            Dim { text: "Stored in " + root.storePath + " under \"ai\"."; Layout.fillWidth: true }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: "The AI chat panel applies these live and writes your in-panel dropdown choice back here." }
                            RowLayout { spacing: 8
                                Btn { icon: "chat"; text: "Open chat"; onClicked: root.sh('quickshell ipc -p "$1" call aichat open 2>/dev/null', [root.shellPath]) }
                                Btn { icon: "stop_circle"; text: "Stop generation"; onClicked: root.sh('quickshell ipc -p "$1" call aichat stop 2>/dev/null', [root.shellPath]) } } }
                    }

                    // ════════ 8 · KEYBINDS ════════
                    PageBase {
                        Card { title: "Loaded binds"; icon: "keyboard_command_key"; badge: root.binds.length + " total"
                            Field { Layout.fillWidth: true; hint: "filter by key, dispatcher or description…"; text: root.bindFilter; onAccepted: t => root.bindFilter = t.toLowerCase() }
                            Repeater {
                                model: root.binds.filter(b => root.bindFilter === "" || (b.key + " " + b.dispatcher + " " + b.arg + " " + b.description).toLowerCase().indexOf(root.bindFilter) >= 0).slice(0, 200)
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 6
                                    Repeater { model: root.mods(parent.modelData.modmask).concat([parent.modelData.key || ("code:" + parent.modelData.keycode)])
                                        delegate: Rectangle { required property var modelData; implicitWidth: kt.implicitWidth + 14; implicitHeight: 22; radius: 6; color: pal.surfaceHi
                                            Mono { id: kt; anchors.centerIn: parent; text: parent.modelData } } }
                                    T { text: parent.modelData.description || (parent.modelData.dispatcher + (parent.modelData.arg ? "  " + parent.modelData.arg : "")); Layout.fillWidth: true; Layout.leftMargin: 8; color: pal.dim } } } }
                    }

                    // ════════ 9 · SYSTEM ════════
                    PageBase {
                        Card { title: "This machine"; icon: "info"
                            GridLayout { columns: 2; Layout.fillWidth: true; columnSpacing: 20; rowSpacing: 6
                                Dim { text: "Model" } T { text: root.sys.model || "—"; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Host" } T { text: root.sys.host || "—"; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Kernel" } T { text: root.sys.kernel || "—"; Layout.alignment: Qt.AlignRight }
                                Dim { text: "CPU" } T { text: root.sys.cpu || "—"; Layout.maximumWidth: 460; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Memory" } T { text: root.gb(+root.sys.memtotal || 0) + " GB"; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Hyprland" } T { text: root.hyprVersion || "—"; Layout.alignment: Qt.AlignRight }
                                Dim { text: "Config format" } T { text: root.luaMode ? "Lua (hyprland.lua)" : "hyprlang (hyprland.conf)"; Layout.alignment: Qt.AlignRight }
                            } }
                        Card { title: "Make settings persistent"; icon: "save"
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: "Changes apply instantly. To keep them after a reboot, add this one line to the END of your Hyprland config, then reload:" }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 34; radius: 12; color: pal.surfaceHi
                                Mono { anchors.fill: parent; anchors.margins: 10; verticalAlignment: Text.AlignVCenter; text: root.includeLine } }
                            RowLayout { spacing: 8
                                Btn { visible: root.sys["has_wl-copy"] === "1"; icon: "content_copy"; text: "Copy line"; onClicked: root.sh('printf %s "$1" | wl-copy', [root.includeLine]) }
                                Btn { visible: root.sys.inc !== "1"; icon: "playlist_add"; text: "Add include line (with backup)"; onClicked: root.addInclude() }
                                Pill { visible: root.sys.inc === "1"; text: "include line detected"; tone: pal.primary }
                                Btn { icon: "refresh"; text: "Reload Hyprland"; onClicked: { root.sh("hyprctl reload"); root.after(900, root.hyprRefresh) } }
                                Btn { icon: "bug_report"; text: "Show config errors"; onClicked: cmdErr.go() } }
                            Mono { visible: root.cfgErrors !== ""; text: root.cfgErrors; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: pal.tertiary } }
                        Card { title: "Detected tools"; icon: "build"
                            Dim { visible: !root.iconOk; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: pal.error
                                text: "Material Symbols icon font not found — icons show as words. Install one (AUR, Fish): paru -S ttf-material-symbols-variable-git" }
                            Flow { Layout.fillWidth: true; spacing: 6
                                Repeater { model: ["hyprctl", "nvidia-smi", "brightnessctl", "nmcli", "powerprofilesctl", "curl", "ollama", "hypridle", "hyprsunset", "sensors", "wl-copy", "notify-send"]
                                    delegate: Pill { required property var modelData; text: modelData; tone: root.sys["has_" + modelData] === "1" ? pal.primary : pal.error } } }
                            Dim { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                text: "Red means missing — the matching controls hide themselves. Install with (Fish): sudo pacman -S --needed brightnessctl networkmanager power-profiles-daemon curl lm_sensors wl-clipboard libnotify" } }
                        Card { title: "Running user services"; icon: "settings_applications"; badge: root.services.length + ""
                            Btn { icon: "refresh"; text: "Refresh list"; onClicked: cmdSvc.go() }
                            Repeater { model: root.services
                                delegate: SRow { required property var modelData; label: modelData
                                    Btn { icon: "restart_alt"; text: "Restart"; onClicked: root.sh('systemctl --user restart "$1"', [modelData]) } } } }
                    }

                    // ════════ 10 · SYSTEM HEALTH ════════
                    PageBase {
                        Card { title: "System Health"; icon: "health_and_safety"
                            RowLayout { Layout.fillWidth: true; spacing: 10
                                Pill {
                                    text: (root.healthReport && root.healthReport.summary) ? root.healthReport.summary.ok + " OK" : "—"
                                    tone: pal.primary
                                }
                                Pill {
                                    text: (root.healthReport && root.healthReport.summary) ? root.healthReport.summary.warn + " WARN" : "—"
                                    tone: pal.secondary
                                }
                                Pill {
                                    text: (root.healthReport && root.healthReport.summary) ? root.healthReport.summary.missing + " MISSING" : "—"
                                    tone: (root.healthReport && root.healthReport.summary && root.healthReport.summary.missing > 0) ? pal.error : pal.surfaceHi
                                }
                                Item { Layout.fillWidth: true }
                                Btn { icon: "refresh"; text: "Refresh"; onClicked: cmdHealth.go() }
                            }
                            Dim {
                                visible: root.healthReport === null
                                text: "Loading doctor diagnostics\u2026"
                            }
                            Dim {
                                visible: root.healthReport !== null
                                text: "GPS doctor audits session daemons, portals, polkit, D-Bus ownership and QuickShell processes."
                            }
                        }
                        Card {
                            title: "Diagnostic Checks"
                            icon: "checklist"
                            visible: root.healthReport !== null && root.healthReport.checks !== undefined
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: (root.healthReport && root.healthReport.checks) || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true; implicitHeight: col.implicitHeight + 14; radius: 10; color: pal.surfaceHi
                                        ColumnLayout {
                                            id: col
                                            anchors.fill: parent; anchors.margins: 8; spacing: 3
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 8
                                                Pill {
                                                    text: parent.parent.parent.modelData.status || "UNKNOWN"
                                                    tone: parent.parent.parent.modelData.status === "OK" ? pal.primary : (parent.parent.parent.modelData.status === "WARN" ? pal.secondary : pal.error)
                                                }
                                                T { text: parent.parent.parent.modelData.label || parent.parent.parent.modelData.name; font.weight: Font.DemiBold }
                                                Item { Layout.fillWidth: true }
                                            }
                                            Dim {
                                                text: parent.parent.modelData.details || ""
                                                Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: 11
                                            }
                                            Mono {
                                                visible: !!parent.parent.modelData.action
                                                text: "Action: " + (parent.parent.modelData.action || "")
                                                color: pal.tertiary; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone; font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────────────────────── system actions ─────────────────────────
    // Append the include line to the END of the active Hyprland config so
    // saved settings win over config defaults, with a timestamped backup.
    function addInclude() {
        const f = luaMode ? home + "/.config/hypr/hyprland.lua" : home + "/.config/hypr/hyprland.conf"
        sh('f="$1"; [ -f "$f" ] || touch "$f"; cp -a "$f" "$f.bak-include-$(date +%Y%m%d-%H%M%S)" && printf "\\n# my-rice settings (added by Settings Hub)\\n%s\\n" "$2" >> "$f"', [f, includeLine])
        after(700, cmdSys.go)
    }
    function daemon(name, on) {
        const s = Object.assign({}, sys); s["run_" + name] = on ? "1" : "0"; sys = s
        if (name === "hypridle") {
            sh(on ? 'command -v gps-idle >/dev/null && gps-idle start || "$HOME/Projects/my-rice/scripts/gps-idle" start' : 'command -v gps-idle >/dev/null && gps-idle stop || "$HOME/Projects/my-rice/scripts/gps-idle" stop')
        } else {
            sh(on ? 'setsid "$1" >/dev/null 2>&1 &' : 'pkill -x "$1"', [name])
        }
        after(800, cmdSys.go)
    }
    function nightLight(on, kelvin) {
        const s = Object.assign({}, sys); s.run_hyprsunset = on ? "1" : "0"; sys = s
        sh(on ? 'pkill -x hyprsunset; setsid hyprsunset -t "$1" >/dev/null 2>&1 &' : 'pkill -x hyprsunset', [String(kelvin)]); after(800, cmdSys.go)
    }
    onPageChanged: {
        if (page === 9) cmdSvc.go()
        if (page === 10) cmdHealth.go()
    }
}
