import QtQuick
import Quickshell
import Quickshell.Io

// Shared, lifecycle-aware system probe for the dashboard. `active` gates all
// work: while false, no timers run and no processes are spawned, so closing
// the dashboard costs nothing.
//
// One /bin/sh tick reads everything that lives in /proc plus hwmon readings,
// cpufreq, RAPL energy and `wpctl get-volume` (the native Pipewire volume API
// returns no channel data on this system, so wpctl is the reliable source).
// nvidia-smi runs on its own slower cadence and disables itself if absent.
// Storage (df) runs on a slow 30 s cadence since it changes rarely.
//
// `tickMs` is the configurable telemetry sampling interval (1 s default);
// the GPU cadence follows it but never goes below 3 s.
Item {
    id: root
    property bool active: false
    property int tickMs: 1000

    // -1 / "" / [] means "not available yet" (loading or unsupported).
    property real cpuUsage: -1
    property int cpuTempC: -1
    property string cpuModel: ""
    property string cpuModelLong: ""
    property string kernel: ""
    property var coreUsage: []
    property int coreCount: 0
    property int freqMhz: -1
    property int baseMhz: -1
    property int maxMhz: -1
    property real pkgWatts: -1
    property int fan1Rpm: -1
    property int fan2Rpm: -1
    property int nvmeTempC: -1
    property real memUsedGiB: -1
    property real memTotalGiB: -1
    property int memPct: -1
    property real uptimeSec: -1
    property real gpuUsage: -1
    property int gpuTempC: -1
    property string gpuName: ""
    property bool gpuAvailable: true
    property int gpuMemUsedMib: -1
    property int gpuMemTotalMib: -1
    property real gpuPowerW: -1
    property string fsDevice: ""
    property real fsTotalBytes: -1
    property real fsUsedBytes: -1
    property real fsFreeBytes: -1
    property real volume: -1
    property bool volumeMuted: false
    property bool volumeAvailable: false

    readonly property bool cpuReady: cpuUsage >= 0
    readonly property bool memReady: memTotalGiB > 0
    readonly property bool storageReady: fsTotalBytes > 0
    readonly property real storageFraction: fsTotalBytes > 0
        ? Math.max(0, Math.min(1, fsUsedBytes / fsTotalBytes))
        : 0

    property var prevCpu: null
    property var prevCores: ({})
    property real prevPkgE: -1
    property real prevPkgT: 0
    property bool hwmonTried: false
    property string coretempPath: ""
    property string nvmePath: ""
    property string fan1Path: ""
    property string fan2Path: ""

    function parseTick(text) {
        const lines = text.split("\n")
        const cores = []
        for (const line of lines) {
            if (line.startsWith("cpu ")) {
                const nums = line.slice(4).trim().split(/\s+/).map(Number)
                const idle = nums[3] + (nums[4] || 0)
                let total = 0
                for (const n of nums) total += n
                if (root.prevCpu) {
                    const dTotal = total - root.prevCpu.total
                    const dIdle = idle - root.prevCpu.idle
                    if (dTotal > 0)
                        root.cpuUsage = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
                }
                root.prevCpu = { total: total, idle: idle }
            } else if (line.startsWith("cpu")) {
                const m = /^cpu(\d+)\s+(.*)$/.exec(line)
                if (m) {
                    const nums = m[2].trim().split(/\s+/).map(Number)
                    const idle = nums[3] + (nums[4] || 0)
                    let total = 0
                    for (const n of nums) total += n
                    let pct = -1
                    const prev = root.prevCores[Number(m[1])]
                    if (prev) {
                        const dTotal = total - prev.total
                        const dIdle = idle - prev.idle
                        if (dTotal > 0)
                            pct = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
                    }
                    cores.push({ idx: Number(m[1]), total: total, idle: idle, pct: pct })
                }
            } else if (line.startsWith("MEM ")) {
                const p = line.slice(4).trim().split(/\s+/).map(Number)
                if (p.length >= 2 && p[0] > 0) {
                    root.memTotalGiB = p[0] / 1048576
                    root.memUsedGiB = (p[0] - p[1]) / 1048576
                    root.memPct = Math.round(100 * (p[0] - p[1]) / p[0])
                }
            } else if (line.startsWith("UP ")) {
                root.uptimeSec = parseFloat(line.slice(3))
            } else if (line.startsWith("TMP ")) {
                const v = parseInt(line.slice(4))
                root.cpuTempC = v > 0 ? Math.round(v / 1000) : -1
            } else if (line.startsWith("FREQ ")) {
                const v = Number(line.slice(5))
                root.freqMhz = v > 0 ? Math.round(v / 1000) : -1
            } else if (line.startsWith("PKG ")) {
                const e = Number(line.slice(4))
                if (e >= 0) {
                    const now = Date.now()
                    if (root.prevPkgE >= 0 && now > root.prevPkgT) {
                        const dUj = e - root.prevPkgE
                        const dtS = (now - root.prevPkgT) / 1000
                        // Counter wrap (or a reset) shows up as a negative
                        // delta; skip that sample instead of reporting junk.
                        if (dUj >= 0 && dtS > 0.2)
                            root.pkgWatts = Math.round((dUj / (dtS * 1000000)) * 10) / 10
                    }
                    root.prevPkgE = e
                    root.prevPkgT = now
                }
            } else if (line.startsWith("NTMP ")) {
                const v = parseInt(line.slice(5))
                root.nvmeTempC = v > 0 ? Math.round(v / 1000) : -1
            } else if (line.startsWith("FAN ")) {
                const p = line.slice(4).trim().split(/\s+/).map(Number)
                root.fan1Rpm = p[0] > 0 ? p[0] : -1
                root.fan2Rpm = p[1] > 0 ? p[1] : -1
            } else if (line.startsWith("BASE ")) {
                const v = Number(line.slice(5))
                root.baseMhz = v > 0 ? Math.round(v / 1000) : -1
            } else if (line.startsWith("MAXF ")) {
                const v = Number(line.slice(5))
                root.maxMhz = v > 0 ? Math.round(v / 1000) : -1
            } else if (line.startsWith("VOL ")) {
                const m = /Volume:\s*([\d.]+)(\s*\[MUTED\])?/.exec(line)
                if (m) {
                    root.volumeAvailable = true
                    root.volume = parseFloat(m[1])
                    root.volumeMuted = m[2] !== undefined
                }
            }
        }
        if (cores.length > 0) {
            root.coreCount = cores.length
            cores.sort((a, b) => a.idx - b.idx)
            root.coreUsage = cores.map(c => c.pct)
            const pc = {}
            for (const c of cores) pc[c.idx] = { total: c.total, idle: c.idle }
            root.prevCores = pc
        }
    }

    readonly property string tickScript: [
        "grep -E '^cpu' /proc/stat",
        "mt=0; ma=0",
        "while read -r k v r; do",
        "  case \"$k\" in",
        "    MemTotal:) mt=$v ;;",
        "    MemAvailable:) ma=$v ;;",
        "  esac",
        "done < /proc/meminfo",
        "read -r up _ < /proc/uptime",
        "tm=-1",
        "if [ -n \"$1\" ] && [ -r \"$1\" ]; then read -r tm < \"$1\"; fi",
        "echo \"MEM $mt $ma\"",
        "echo \"UP $up\"",
        "echo \"TMP $tm\"",
        "fq=-1",
        "f=$(awk '{s+=$1; n++} END {if (n>0) printf \"%d\", s/n}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)",
        "if [ -n \"$f\" ]; then fq=$f; fi",
        "echo \"FREQ $fq\"",
        "pk=-1",
        "if [ -r /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj ]; then read -r pk < /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj; fi",
        "echo \"PKG $pk\"",
        "nt=-1",
        "if [ -n \"$2\" ] && [ -r \"$2\" ]; then read -r nt < \"$2\"; fi",
        "echo \"NTMP $nt\"",
        "fa=-1; fb=-1",
        "if [ -n \"$3\" ] && [ -r \"$3\" ]; then read -r fa < \"$3\"; fi",
        "if [ -n \"$4\" ] && [ -r \"$4\" ]; then read -r fb < \"$4\"; fi",
        "echo \"FAN $fa $fb\"",
        "bf=-1",
        "if [ -r /sys/devices/system/cpu/cpu0/cpufreq/base_frequency ]; then read -r bf < /sys/devices/system/cpu/cpu0/cpufreq/base_frequency; fi",
        "echo \"BASE $bf\"",
        "mf=-1",
        "if [ -r /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq ]; then read -r mf < /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq; fi",
        "echo \"MAXF $mf\"",
        "vo=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)",
        "echo \"VOL $vo\""
    ].join("\n")

    Timer {
        id: tickTimer
        interval: root.tickMs
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!probeProc.running) probeProc.running = true
        }
    }

    Process {
        id: probeProc
        command: ["sh", "-c", root.tickScript, "sysprobe",
            root.coretempPath, root.nvmePath, root.fan1Path, root.fan2Path]
        stdout: StdioCollector {
            onStreamFinished: root.parseTick(text)
        }
    }

    // One-shot discovery of hwmon paths; hwmon numbering is not stable across
    // boots so paths are resolved by name, once per session.
    Process {
        id: hwmonPathProc
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do "
            + "n=$(cat \"$h/name\" 2>/dev/null); "
            + "case \"$n\" in "
            + "coretemp) echo \"CORE $h/temp1_input\" ;; "
            + "nvme) echo \"NVME $h/temp1_input\" ;; "
            + "acer) echo \"FAN $h/fan1_input $h/fan2_input\" ;; "
            + "esac; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                for (const line of lines) {
                    if (line.startsWith("CORE ")) root.coretempPath = line.slice(5).trim()
                    else if (line.startsWith("NVME ")) root.nvmePath = line.slice(5).trim()
                    else if (line.startsWith("FAN ")) {
                        const p = line.slice(4).trim().split(/\s+/)
                        root.fan1Path = p[0] || ""
                        root.fan2Path = p[1] || ""
                    }
                }
            }
        }
        onExited: root.hwmonTried = true
    }

    onActiveChanged: {
        if (root.active) {
            if (!root.hwmonTried && !hwmonPathProc.running) hwmonPathProc.running = true
        } else {
            probeProc.running = false
            gpuProc.running = false
            hwmonPathProc.running = false
            storageProc.running = false
        }
    }

    // Storage changes slowly; a 30 s cadence is plenty and keeps the tick
    // script free of extra processes.
    Timer {
        id: storageTimer
        interval: 30000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!storageProc.running) storageProc.running = true
        }
    }

    Process {
        id: storageProc
        command: ["sh", "-c", "df -B1 / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length >= 4) {
                    root.fsDevice = p[0]
                    root.fsTotalBytes = Number(p[1]) || -1
                    root.fsUsedBytes = Number(p[2]) || -1
                    root.fsFreeBytes = Number(p[3]) || -1
                }
            }
        }
    }

    Timer {
        id: gpuTimer
        interval: Math.max(3000, root.tickMs)
        repeat: true
        running: root.active && root.gpuAvailable
        triggeredOnStart: true
        onTriggered: {
            if (!gpuProc.running) gpuProc.running = true
        }
    }

    Process {
        id: gpuProc
        command: ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",").map(s => s.trim())
                if (parts.length >= 3) {
                    root.gpuName = parts[0]
                    const u = parseInt(parts[1])
                    root.gpuUsage = isNaN(u) ? -1 : u
                    const t = parseInt(parts[2])
                    root.gpuTempC = isNaN(t) ? -1 : t
                }
                if (parts.length >= 5) {
                    const mu = parseInt(parts[3])
                    const mt = parseInt(parts[4])
                    root.gpuMemUsedMib = isNaN(mu) ? -1 : mu
                    root.gpuMemTotalMib = isNaN(mt) ? -1 : mt
                }
                if (parts.length >= 6) {
                    const pw = parseFloat(parts[5])
                    root.gpuPowerW = isNaN(pw) ? -1 : pw
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) root.gpuAvailable = false
        }
    }

    FileView {
        path: "/proc/sys/kernel/osrelease"
        preload: true
        blockLoading: true
        onLoaded: root.kernel = text().trim()
    }

    FileView {
        path: "/proc/cpuinfo"
        preload: true
        blockLoading: true
        onLoaded: {
            const m = /model name\s*:\s*(.+)/.exec(text())
            if (m) {
                const shortModel = /Core\(TM\)\s+(.+)/.exec(m[1])
                root.cpuModel = shortModel ? shortModel[1].trim() : m[1].trim()
                root.cpuModelLong = m[1].replace(/\((R|TM)\)/g, "").replace(/\s+/g, " ").trim()
            }
        }
    }
}
