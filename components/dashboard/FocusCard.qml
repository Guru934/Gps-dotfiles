import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components.dashboard

// Focus setup and live session view for the HOME tab. The session engine
// lives in island/Island.qml; this card only calls it over IPC and renders
// the state reported by focusState(). Closing the drawer never stops a run.
DashSurface {
    id: root
    property bool isOpen: false

    readonly property string repoRoot: Quickshell.env("GPS_ROOT") || ""
    readonly property string islandPath: root.repoRoot ? (root.repoRoot + "/island/IslandProduction.qml") : ""
    readonly property color tone: root.isBreak ? Theme.accentSecondary : Theme.accentPrimary

    property bool available: true
    property bool loaded: false
    property string stateError: ""
    property bool focusOn: false
    property bool paused: false
    property bool isBreak: false
    property real remaining: -1
    property int phaseSeconds: 0
    property int sessionIndex: 0
    property int sessionCount: 0
    property string sessionTitle: ""

    property string workInput: "25"
    property string breakInput: "5"
    property string sessionsInput: "4"
    property string titleInput: ""
    property string presetKey: "25/5"
    property string actionError: ""

    readonly property bool inputsValid:
        validNumber(workInput, 1, 10080)
        && validNumber(breakInput, 0, 10080)
        && validNumber(sessionsInput, 1, 1000)
    readonly property real progress:
        root.focusOn && root.phaseSeconds > 0
        ? Math.max(0, Math.min(1, 1 - root.remaining / root.phaseSeconds))
        : 0

    fill: Theme.surfaceBase
    radius: 14
    implicitHeight: body.implicitHeight + 20
    visible: true

    function validNumber(value, minimum, maximum) {
        if (typeof value !== "string" || !/^\d+$/.test(value)) return false
        const n = Number(value)
        return Number.isInteger(n) && n >= minimum && n <= maximum
    }

    function fmt(seconds) {
        const s = Math.max(0, Math.floor(seconds))
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    function applyPreset(work, rest, key) {
        root.workInput = String(work)
        root.breakInput = String(rest)
        root.presetKey = key
        root.actionError = ""
    }

    function refreshState() {
        if (!root.isOpen) return
        root.stateError = ""
        if (!stateProc.running) stateProc.running = true
    }

    function applyState(raw) {
        if (!raw || raw.trim() === "") return
        let data
        try {
            data = JSON.parse(raw)
        } catch (e) {
            root.available = false
            root.loaded = true
            root.stateError = "Focus state could not be read."
            return
        }
        if (!data || data.available !== true) {
            root.available = false
            root.loaded = true
            root.stateError = "The GPS island does not expose Focus."
            return
        }
        root.available = true
        root.loaded = true
        root.focusOn = data.focusOn === true
        root.paused = data.paused === true
        root.isBreak = data.isBreak === true
        root.remaining = Number(data.remaining)
        if (!Number.isFinite(root.remaining) || root.remaining < 0) root.remaining = 0
        root.phaseSeconds = Number(data.phaseSeconds) || 0
        root.sessionIndex = Number(data.sessionIndex) || 0
        root.sessionCount = Number(data.sessionCount) || 0
        root.sessionTitle = typeof data.title === "string" ? data.title : ""
    }

    function callIsland(fn, args) {
        root.actionError = ""
        const command = ["quickshell", "ipc", "--any-display", "-p", root.islandPath, "call", "island", fn]
        Quickshell.execDetached(command.concat(args || []))
        actionRefresh.restart()
    }

    function startFocus() {
        if (!root.inputsValid || !root.available) return
        root.callIsland("focusStart", [
            String(Number(root.workInput) * 60),
            String(Number(root.breakInput) * 60),
            String(Number(root.sessionsInput)),
            root.titleInput
        ])
    }

    function togglePause() {
        root.callIsland(root.paused ? "focusResume" : "focusPause", [])
    }

    function skipFocus() {
        root.callIsland("focusSkip", [])
    }

    function stopFocus() {
        root.callIsland("focusStop", [])
    }

    Process {
        id: stateProc
        command: ["quickshell", "ipc", "--any-display", "-p", root.islandPath, "call", "island", "focusState"]
        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.available = false
                root.loaded = true
                root.focusOn = false
                root.stateError = "GPS island is not reachable."
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.isOpen
        triggeredOnStart: true
        onTriggered: root.refreshState()
    }

    Timer {
        id: actionRefresh
        interval: 200
        repeat: false
        onTriggered: root.refreshState()
    }

    component FocusInput: ColumnLayout {
        id: field
        property string labelText: ""
        property string valueText: ""
        property bool numeric: true
        property bool syncing: false
        signal edited(string value)

        Layout.fillWidth: true
        spacing: 3

        onValueTextChanged: {
            if (fieldInput.text === field.valueText) return
            field.syncing = true
            fieldInput.text = field.valueText
            field.syncing = false
        }

        Component.onCompleted: {
            field.syncing = true
            fieldInput.text = field.valueText
            field.syncing = false
        }

        Text {
            text: field.labelText
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 8
            font.bold: true
            font.letterSpacing: 0.6
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 8
            color: Theme.surfaceDeep
            border.width: 1
            border.color: fieldInput.activeFocus ? root.tone : Theme.outlineSoft

            TextInput {
                id: fieldInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.textMain
                selectionColor: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.35)
                font.family: Theme.fontMono
                font.pixelSize: 11
                selectByMouse: true
                clip: true
                maximumLength: field.numeric ? 5 : 100
                inputMethodHints: field.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
                onTextChanged: {
                    if (!field.syncing) field.edited(text)
                }
            }
        }
    }

    component FocusButton: Rectangle {
        id: button
        property string labelText: ""
        property color tone: root.tone
        property bool primary: false
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 18
        Layout.preferredHeight: 28
        radius: 9
        color: !button.enabled
            ? Qt.rgba(1, 1, 1, 0.04)
            : button.primary
                ? (buttonHover.hovered ? Qt.lighter(button.tone, 1.08) : button.tone)
                : (buttonHover.hovered ? Qt.rgba(button.tone.r, button.tone.g, button.tone.b, 0.18)
                                       : Qt.rgba(button.tone.r, button.tone.g, button.tone.b, 0.09))
        border.width: button.primary ? 0 : 1
        border.color: Qt.rgba(button.tone.r, button.tone.g, button.tone.b, 0.30)
        opacity: button.enabled ? 1 : 0.42
        scale: buttonTap.pressed ? 0.97 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.labelText
            color: button.primary ? Theme.onAccent : Theme.textMain
            font.family: Theme.fontMono
            font.pixelSize: 9
            font.bold: true
        }

        HoverHandler {
            id: buttonHover
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            id: buttonTap
            enabled: button.enabled
            onTapped: button.clicked()
        }
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 8
                color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.14)

                DashIcon {
                    anchors.centerIn: parent
                    name: "timer"
                    color: root.tone
                    font.pixelSize: 15
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "FOCUS"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: !root.loaded
                        ? "Connecting to the GPS island\u2026"
                        : !root.available
                            ? (root.stateError !== "" ? root.stateError : "GPS island unavailable")
                            : root.focusOn
                                ? (root.isBreak ? "Break in progress" : "Work in progress")
                                : "Ready to start a session"
                    color: root.available ? Theme.textDim : Theme.statusDanger
                    font.family: Theme.fontMono
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: statusLabel.implicitWidth + 16
                Layout.preferredHeight: 20
                radius: 10
                color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.28)

                Text {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: !root.available && root.loaded
                        ? "OFFLINE"
                        : !root.focusOn
                            ? "READY"
                            : root.paused
                                ? "PAUSED"
                                : root.isBreak ? "BREAK" : "RUNNING"
                    color: !root.available && root.loaded ? Theme.statusDanger : root.tone
                    font.family: Theme.fontMono
                    font.pixelSize: 8
                    font.bold: true
                }
            }
        }

        ColumnLayout {
            visible: !root.focusOn
            Layout.fillWidth: true
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    text: "PRESETS"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 0.6
                }

                FocusButton {
                    labelText: "25 / 5"
                    primary: root.presetKey === "25/5"
                    onClicked: root.applyPreset(25, 5, "25/5")
                }

                FocusButton {
                    labelText: "50 / 10"
                    primary: root.presetKey === "50/10"
                    onClicked: root.applyPreset(50, 10, "50/10")
                }

                FocusButton {
                    labelText: "90 / 15"
                    primary: root.presetKey === "90/15"
                    onClicked: root.applyPreset(90, 15, "90/15")
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                FocusInput {
                    labelText: "WORK MIN"
                    valueText: root.workInput
                    onEdited: value => {
                        root.workInput = value
                        root.presetKey = ""
                        root.actionError = ""
                    }
                }

                FocusInput {
                    labelText: "BREAK MIN"
                    valueText: root.breakInput
                    onEdited: value => {
                        root.breakInput = value
                        root.presetKey = ""
                        root.actionError = ""
                    }
                }

                FocusInput {
                    labelText: "SESSIONS"
                    valueText: root.sessionsInput
                    onEdited: value => {
                        root.sessionsInput = value
                        root.actionError = ""
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                FocusInput {
                    Layout.fillWidth: true
                    labelText: "TITLE (OPTIONAL)"
                    numeric: false
                    valueText: root.titleInput
                    onEdited: value => root.titleInput = value
                }

                FocusButton {
                    Layout.alignment: Qt.AlignBottom
                    labelText: "START FOCUS"
                    primary: true
                    enabled: root.available && root.inputsValid
                    onClicked: root.startFocus()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.actionError !== "" || !root.inputsValid
                text: root.actionError !== ""
                    ? root.actionError
                    : "Use whole numbers: work 1\u201310080, break 0\u201310080, sessions 1\u20131000."
                color: root.actionError !== "" ? Theme.statusDanger : Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 8
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            visible: root.focusOn
            Layout.fillWidth: true
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.isBreak ? "BREAK" : "FOCUS"
                    color: root.tone
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8
                }

                Text {
                    Layout.fillWidth: true
                    text: root.paused
                        ? "Paused"
                        : "Session " + root.sessionIndex + " / " + root.sessionCount
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Text {
                    text: root.fmt(root.remaining)
                    color: Theme.textMain
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.09)

                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: parent.radius
                    color: root.tone
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.sessionTitle !== "" ? root.sessionTitle : "FOCUS SESSION"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                FocusButton {
                    labelText: root.paused ? "RESUME" : "PAUSE"
                    onClicked: root.togglePause()
                }

                FocusButton {
                    labelText: "SKIP"
                    tone: Theme.textMuted
                    onClicked: root.skipFocus()
                }

                FocusButton {
                    labelText: "STOP"
                    tone: Theme.statusDanger
                    onClicked: root.stopFocus()
                }
            }
        }
    }
}
