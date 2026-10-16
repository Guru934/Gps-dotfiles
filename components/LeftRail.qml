import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config

PanelWindow {
    id: root
    property var hub: null
    property var notifications: null
    property var dashboard: null
    property var wallpaperCarousel: null
    property var settingsHub: null

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

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
            RailButton { glyph: "󰕾"; tooltip: "Audio mute"; onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) }
            RailButton { glyph: "󰂚"; tooltip: "Notifications (Super+N)"; onClicked: if (root.notifications) root.notifications.toggle() }
            RailButton { glyph: "󰸉"; tooltip: "Wallpaper carousel (Super+W)"; onClicked: if (root.wallpaperCarousel) root.wallpaperCarousel.toggle() }
            RailButton {
                glyph: "󰒓"
                tooltip: "Settings (Super+,)"
                onClicked: {
                    if (root.settingsHub) root.settingsHub.toggle()
                    else Quickshell.execDetached(["quickshell", "ipc", "call", "settings", "toggle"])
                }
            }
        }

        Column {
            anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
            spacing: 6
            Text {
                width: 36
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatTime(new Date(), "HH\nmm")
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 9
                lineHeight: 0.9
            }
            RailButton { glyph: "󰐥"; tooltip: "Power menu"; onClicked: Quickshell.execDetached(["rofi", "-show", "power-menu"]) }
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
