import Quickshell
import QtQuick
import qs.config

PanelWindow {
    id: root

    property var hub: null

    // Anchored to the LEFT side of the screen (reserves 58px automatically)
    anchors {
        top: true
        bottom: true
        left: true
    }

    implicitWidth: Theme.sidebarWindowWidth
    color: "transparent"

    Rectangle {
        id: barSurface
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            topMargin: 8
            bottomMargin: 8
            leftMargin: 8
        }
        width: Theme.sidebarBarWidth
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // Top Cluster: GPS Launcher + Vertical Workspaces
        Column {
            id: topCluster
            anchors {
                top: parent.top
                topMargin: 8
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 8

            BrandMark {
            }

            WorkspaceIndicator {
            }
        }

        // Bottom Cluster: StatusPills
        StatusPills {
            id: bottomCluster
            hub: root.hub
            anchors {
                bottom: parent.bottom
                bottomMargin: 8
                horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
