import QtQuick
import QtQuick.Layouts
import qs.config

// GPS Reusable Section Header
// Standardizes uppercase category labels, subtitles, glyphs, and action tags.
RowLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property string tag: ""
    property color tagColor: Theme.brandAccent
    property color titleColor: Theme.textMain

    spacing: Theme.spacingSm

    Text {
        visible: root.icon !== ""
        text: root.icon
        color: root.tagColor
        font.family: Theme.fontUi
        font.pixelSize: Theme.fontSizeHeading
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1

        Text {
            Layout.fillWidth: true
            text: root.title
            color: root.titleColor
            font.family: Theme.fontUi
            font.pixelSize: Theme.fontSizeSubheading
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            visible: root.subtitle !== ""
            Layout.fillWidth: true
            text: root.subtitle
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            font.letterSpacing: 0.8
            elide: Text.ElideRight
        }
    }

    Rectangle {
        visible: root.tag !== ""
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: tagText.implicitWidth + 12
        implicitHeight: 18
        radius: Theme.radiusPill
        color: Qt.alpha(root.tagColor, 0.16)
        border.width: 1
        border.color: Qt.alpha(root.tagColor, 0.45)

        Text {
            id: tagText
            anchors.centerIn: parent
            text: root.tag
            color: root.tagColor
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }
    }
}
