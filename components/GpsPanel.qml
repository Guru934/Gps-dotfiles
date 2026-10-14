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

        // True Screen-Centered Window Title (Hidden when no window is focused)
        Text {
            id: windowTitle
            readonly property bool hasWindow: Hyprland.activeToplevel !== null
                && Hyprland.activeToplevel.title !== ""
            visible: hasWindow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, 360)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: hasWindow ? Hyprland.activeToplevel.title : ""
            color: Theme.textMain
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.bold: true
        }

        // Right Cluster: Consolidated StatusPills
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
