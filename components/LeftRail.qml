import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null

    anchors { top: true; bottom: true; left: true }
    // A positive fixed width prevents layer-shell from stretching the rail.
    implicitWidth: 54
    color: "transparent"

    Rectangle {
        anchors { fill: parent; topMargin: 10; bottomMargin: 10; leftMargin: 8; rightMargin: 8 }
        radius: Theme.radiusPanel
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Column {
            anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
            spacing: 10
            BrandMark {}
            WorkspaceIndicator { hub: root.hub }
        }

        Column {
            anchors.centerIn: parent
            spacing: 6
            RailButton { glyph: "󰸉"; tooltip: "Wallpaper picker (Super+W)"; onClicked: if (root.hub) root.hub.cycleWallpaper() }
            RailButton { glyph: "󰅌"; tooltip: "Clipboard (Super+V)"; onClicked: Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "call", "tide", "openClipboard"]) }
            RailButton { glyph: "󰂚"; tooltip: "Notifications (Super+N)"; onClicked: Quickshell.execDetached(["env", "LC_CTYPE=C.UTF-8", "quickshell", "ipc", "call", "tide", "openNotificationCenter"]) }
        }

        Column {
            anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
            spacing: 6
            RailButton { glyph: "󰍜"; tooltip: "Quick settings"; onClicked: if (root.hub) root.hub.toggleDashboard() }
            RailButton { glyph: "󰐥"; tooltip: "Power menu"; onClicked: if (root.hub) root.hub.openPowerMenu() }
        }
    }

    component RailButton: Rectangle {
        id: button
        property string glyph: "•"
        property string tooltip: ""
        signal clicked()
        width: 36
        height: 32
        radius: Theme.radiusPill
        color: mouse.containsMouse ? Theme.cardHover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: mouse.containsMouse ? Theme.brandAccent : Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 16
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.hub) root.hub.setTooltip(button.tooltip)
            onExited: if (root.hub) root.hub.clearTooltip()
            onClicked: button.clicked()
        }
    }
}
