// Island state: dnd — 120×34 pill shown while Do-Not-Disturb is on.
// Counts the notifications held back (they are released as a stack when DND turns off). Click to turn DND off.
// Toggle from a keybind:  qs -p <path-to-Island.qml> ipc call island dnd toggle
import QtQuick
import QtQuick.Layouts

Item {
    id: st
    required property var core
    readonly property string key: "dnd"
    readonly property real w: 120
    readonly property real h: 34
    readonly property color accent: core.amber
    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.core.setDnd(false) }
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 6
        Text {
            text: st.core.iconOk ? "bedtime" : "☾"
            font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont; font.pixelSize: 15; color: st.core.amber
        }
        Text { text: "DND"; color: st.core.amber; font.family: st.core.monoFont; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1; Layout.fillWidth: true }
        Rectangle {
            visible: st.core.held.length > 0
            width: 6; height: 6; radius: 3; color: st.core.coral
            SequentialAnimation on opacity { loops: Animation.Infinite; running: st.core.held.length > 0 && st.visible
                NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
        }
        Text { visible: st.core.held.length > 0; text: st.core.held.length; color: st.core.text; font.family: st.core.monoFont; font.pixelSize: 11; font.weight: Font.DemiBold }
    }
}
