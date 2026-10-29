import QtQuick
import "../Theme.js" as Theme

Column {
    id: root
    spacing: 6

    property var currentTime: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentTime = new Date()
        }
    }

    Text {
        id: timeText
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(root.currentTime, "hh:mm")
        font.pixelSize: 58
        font.weight: Font.DemiBold
        font.family: Theme.palette.fontUi
        color: Theme.palette.textMain
        renderType: Text.NativeRendering
    }

    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(root.currentTime, "dddd, MMMM d")
        font.pixelSize: 14
        font.weight: Font.Normal
        font.family: Theme.palette.fontUi
        color: Theme.palette.accentSecondary
        opacity: 0.92
        renderType: Text.NativeRendering
    }
}
