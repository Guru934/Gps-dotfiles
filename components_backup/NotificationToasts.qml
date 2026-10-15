import Quickshell
import QtQuick
import qs.config

PanelWindow {
    id: root

    required property var hub
    visible: root.hub !== null
        && !root.hub.dndEnabled
        && !root.hub.dashboardOpen
        && !root.hub.powerMenuOpen
        && root.hub.toastVisible

    anchors {
        top: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    margins {
        top: 14
        right: 14
    }

    implicitWidth: 320
    implicitHeight: toastCol.implicitHeight + 24
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.surface
        border.width: 1
        border.color: (root.hub && root.hub.toastUrgent) ? Theme.statusDanger : Theme.brandAccent

        Column {
            id: toastCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 4

            Row {
                width: parent.width
                spacing: 6

                Text {
                    text: "󰂚"
                    color: (root.hub && root.hub.toastUrgent) ? Theme.statusDanger : Theme.brandAccent
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }

                Text {
                    width: parent.width - 44
                    elide: Text.ElideRight
                    text: (root.hub && root.hub.toastApp !== "") ? root.hub.toastApp.toUpperCase() : "NOTIFICATION"
                    color: Theme.brandAccent
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Text {
                    text: "✕"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.hub ? root.hub.toastSummary : ""
                color: Theme.textMain
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                visible: root.hub !== null && root.hub.toastBody !== ""
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: root.hub ? root.hub.toastBody : ""
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 11
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.hub) root.hub.dismissToast()
        }
    }
}
