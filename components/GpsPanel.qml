import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

PanelWindow {
    id: root

    property var hub: null

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.panelWindowHeight
    color: "transparent"

    Rectangle {
        id: barSurface
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 8
            leftMargin: 12
            rightMargin: 12
        }
        height: Theme.panelBarHeight
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // Left Cluster: BrandMark + Workspaces
        Row {
            id: leftCluster
            anchors {
                left: parent.left
                leftMargin: 7
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            BrandMark {
                showTagline: false
            }

            WorkspaceIndicator {
            }
        }

        // Middle Zone: Active Window Title (or Workspace status when empty)
        Item {
            anchors {
                left: leftCluster.right
                right: rightCluster.left
                leftMargin: 12
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            height: Theme.pillHeight

            Text {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                readonly property bool hasWindow: Hyprland.activeToplevel !== null
                    && Hyprland.activeToplevel.title !== ""
                readonly property int wsId: Hyprland.focusedWorkspace !== null
                    ? Hyprland.focusedWorkspace.id
                    : 1
                text: hasWindow
                    ? Hyprland.activeToplevel.title
                    : ("Workspace " + wsId + "  ·  Desktop")
                color: hasWindow ? Theme.textMain : Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.bold: hasWindow
            }
        }

        // Right Cluster: StatusPills
        StatusPills {
            id: rightCluster
            hub: root.hub
            anchors {
                right: parent.right
                rightMargin: 7
                verticalCenter: parent.verticalCenter
            }
        }
    }
}
