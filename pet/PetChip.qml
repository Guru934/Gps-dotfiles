import QtQuick

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property color accent: theme.primary
    signal clicked()
    implicitWidth: t.implicitWidth + 24
    implicitHeight: 28
    radius: 14
    color: ma.pressed ? accent : (ma.containsMouse ? theme.cardTop : theme.cardHi)
    Behavior on color { ColorAnimation { duration: 90 } }
    Text {
        id: t
        anchors.centerIn: parent
        text: root.text
        color: ma.pressed ? root.theme.inkOnPrimary : root.accent
        font.family: root.theme.mono; font.pixelSize: 10; font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
