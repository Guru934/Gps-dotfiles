import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property var theme
    property string title: ""
    property string tag: ""
    default property alias content: col.data

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 28
    radius: 14
    color: theme.card

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Text { text: card.title; color: card.theme.primary; font.family: card.theme.mono; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
            Item { Layout.fillWidth: true }
            Text { visible: card.tag !== ""; text: card.tag; color: card.theme.mute; font.family: card.theme.mono; font.pixelSize: 9; font.letterSpacing: 0.8 }
        }
    }
}
