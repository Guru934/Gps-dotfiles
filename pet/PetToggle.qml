import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled(bool value)

    Layout.fillWidth: true
    implicitHeight: hint ? 38 : 28

    Column {
        anchors.left: parent.left
        anchors.right: sw.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text { text: root.label; color: root.theme.text; font.family: root.theme.body; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
        Text { visible: root.hint !== ""; text: root.hint; color: root.theme.mute; font.family: root.theme.body; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
    }

    Rectangle {
        id: sw
        width: 38; height: 22; radius: 11
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? root.theme.primary : root.theme.cardTop
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3; x: root.checked ? 19 : 3
            color: root.checked ? root.theme.inkOnPrimary : root.theme.dim
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
