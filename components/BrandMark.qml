import QtQuick
import qs.config

Item {
    id: root

    implicitWidth: emblemBox.width + 14 + brandTexts.implicitWidth
    implicitHeight: Math.max(emblemBox.height, brandTexts.implicitHeight)

    Rectangle {
        id: emblemBox
        width: 44
        height: 44
        radius: Theme.radiusEmblem
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        color: Theme.brandAccent

        Text {
            anchors.centerIn: parent
            text: "✦"
            color: Theme.brandAccentFg
            font.pixelSize: Theme.fontSizeEmblem
        }
    }

    Column {
        id: brandTexts
        anchors.left: emblemBox.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingLeftColumn

        Text {
            text: "GPS"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeGps
            font.bold: true
            font.letterSpacing: Theme.letterSpacingGps
        }

        Text {
            text: "Your space. Your rules."
            color: Theme.textOnAccent
            font.pixelSize: Theme.fontSizeTagline
            font.bold: true
        }
    }
}
