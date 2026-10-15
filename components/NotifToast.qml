import Quickshell
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null
    readonly property bool toastOpen: hub !== null && hub.toastVisible

    anchors { top: true; horizontalCenter: true }
    margins { top: 24 }
    implicitWidth: 440
    implicitHeight: 96
    color: "transparent"
    visible: opacity > 0.01
    opacity: root.toastOpen ? 1 : 0
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Timer {
        id: dismissTimer
        interval: 8000
        repeat: false
        running: root.toastOpen
        onTriggered: if (root.hub) root.hub.toastVisible = false
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.brandAccent

        Row {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Rectangle {
                width: 38; height: 38; radius: Theme.radiusPill
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.brandAccent
                Text { anchors.centerIn: parent; text: "🍵"; font.pixelSize: 18 }
            }
            Column {
                width: 220
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { text: root.hub && root.hub.toastSummary !== "" ? root.hub.toastSummary : "Pomodoro Break Alert"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
                Text { text: root.hub && root.hub.toastBody !== "" ? root.hub.toastBody : "Time for a 5-min breather! 🍵"; color: Theme.textMuted; font.family: Theme.fontUi; font.pixelSize: 10; elide: Text.ElideRight }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                ToastButton { label: "Take Break"; onClicked: if (root.hub) root.hub.toastVisible = false }
                ToastButton { label: "Snooze 5m"; onClicked: if (root.hub) root.hub.toastVisible = false }
            }
        }
    }

    component ToastButton: Rectangle {
        property string label: ""
        signal clicked()
        width: 96; height: 26; radius: Theme.radiusPill
        color: mouse.containsMouse ? Theme.brandAccent : Theme.card
        border.width: 1; border.color: Theme.brandAccent
        Text { anchors.centerIn: parent; text: label; color: mouse.containsMouse ? Theme.brandAccentFg : Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 9; font.bold: true }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }
}
