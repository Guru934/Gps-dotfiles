import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.config

// Screen-time card: today's per-application active time from the local
// ActivityWatch-compatible tracker (awatcher bundle, REST API on
// 127.0.0.1:5600). scripts/screen-time.py does the math (idle/afk intervals
// subtracted, overlapping events merged) and prints one JSON line. The fetcher
// runs only while the open Home pane exists and refreshes every 60 s; no
// window titles or URLs are shown, only application-level totals.
DashSurface {
    id: root
    property bool isOpen: false

    property var report: null      // last valid payload from the helper
    property string fetchState: "init"  // init | ok | stale | nodata | offline
    property double lastGoodAt: 0

    readonly property var accents: [
        Theme.accentPrimary,
        Theme.accentSecondary,
        Theme.accentTertiary,
        Theme.accentPrimaryDim,
        Theme.textDim
    ]

    readonly property string statusText: {
        if (root.fetchState === "ok") return "LIVE"
        if (root.fetchState === "stale") return "STALE"
        if (root.fetchState === "nodata") return "NO ACTIVITY YET"
        if (root.fetchState === "offline") return "TRACKER OFFLINE"
        return "\u2026"
    }

    readonly property color statusColor: {
        if (root.fetchState === "ok") return Theme.accentPrimary
        if (root.fetchState === "stale") return Theme.accentTertiary
        return Theme.textDim
    }

    function fmtTime(sec) {
        const s = Math.max(0, Math.round(sec))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return s + "s"
    }

    function refresh() {
        if (!fetchProc.running && root.isOpen)
            fetchProc.running = true
    }

    fill: Qt.rgba(Theme.surfaceBase.r, Theme.surfaceBase.g, Theme.surfaceBase.b, 0.7)
    radius: 14
    implicitHeight: body.implicitHeight + 24

    Process {
        id: fetchProc
        command: [
            "python3",
            Qt.resolvedUrl("../../scripts/screen-time.py").toString().replace(/^file:\/\//, ""),
            "5"
        ]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const obj = JSON.parse(line)
                    if (!obj || typeof obj.status !== "string") return
                    if (obj.status === "ok") {
                        root.report = obj
                        root.fetchState = "ok"
                        root.lastGoodAt = Date.now()
                    } else if (obj.status === "nodata") {
                        root.report = null
                        root.fetchState = "nodata"
                    } else {
                        root.fetchState = root.report !== null ? "stale" : "offline"
                    }
                } catch (e) {
                    root.fetchState = root.report !== null ? "stale" : "offline"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0)
                root.fetchState = root.report !== null ? "stale" : "offline"
        }
    }

    // One query per minute while Home is open; the helper itself is one-shot.
    Timer {
        interval: 60000
        repeat: true
        running: root.isOpen
        onTriggered: root.refresh()
    }

    Component.onCompleted: if (root.isOpen) root.refresh()
    onIsOpenChanged: {
        if (root.isOpen)
            root.refresh()
        else
            fetchProc.running = false
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 12
        spacing: Theme.dashboardSpacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dashboardSpacingSm

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "schedule"
                color: Theme.accentPrimary
                font.pixelSize: Theme.dashboardText(14)
            }

            Text {
                Layout.fillWidth: true
                text: "SCREEN TIME // TODAY"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.fetchState === "ok" || root.fetchState === "stale"
                text: root.lastGoodAt > 0 ? Qt.formatTime(new Date(root.lastGoodAt), "HH:mm") : ""
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.statusText
                color: root.statusColor
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
            }
        }

        Repeater {
            model: root.report ? root.report.apps : []

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dashboardSpacingSm

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.dashboardText(11)
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.fmtTime(modelData.seconds)
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.dashboardText(9)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, modelData.pct / 100))
                        height: parent.height
                        radius: parent.radius
                        color: root.accents[index % root.accents.length]
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            visible: root.report !== null
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.report !== null

            Text {
                Layout.fillWidth: true
                text: "TOTAL ACTIVE"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
                font.letterSpacing: 0.6
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.report !== null ? root.fmtTime(root.report.total_seconds) : ""
                color: Theme.accentPrimary
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(12)
                font.bold: true
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.report === null
            text: {
                if (root.fetchState === "init") return "Checking tracker\u2026"
                if (root.fetchState === "nodata") return "No activity recorded yet today"
                return "Tracker offline"
            }
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.dashboardText(9)
        }
    }
}
