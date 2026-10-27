import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    property string label: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real step: 0          // 0 = continuous
    property real value: 0
    signal moved(real value)

    Layout.fillWidth: true
    implicitHeight: 40

    Row {
        width: parent.width
        Text { id: l; text: root.label; color: root.theme.text; font.family: root.theme.body; font.pixelSize: 13 }
        Item { width: parent.width - l.width - v.width; height: 1 }
        Text { id: v; text: root.valueText; color: root.theme.primary; font.family: root.theme.mono; font.pixelSize: 11; font.weight: Font.DemiBold }
    }
    Rectangle {
        id: track
        y: 26; height: 4; radius: 2; width: parent.width
        color: root.theme.cardTop
        Rectangle {
            height: parent.height; radius: 2; color: root.theme.primary
            width: parent.width * Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from)))
        }
        Rectangle {
            width: 14; height: 14; radius: 7; color: root.theme.text
            anchors.verticalCenter: parent.verticalCenter
            x: (track.width - width) * Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from)))
        }
    }
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: 14
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) {
            var f = Math.max(0, Math.min(1, mx / width));
            var v = root.from + f * (root.to - root.from);
            if (root.step > 0) v = Math.round(v / root.step) * root.step;
            root.moved(v);
        }
        onPressed: mouse => setFrom(mouse.x)
        onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
    }
}
