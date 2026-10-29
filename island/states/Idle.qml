// Island state: idle. Loaded by Island.qml, which passes in `core` (live data + theme).
import QtQuick
import QtQuick.Layouts
import "PetSprites.js" as S
Item {
    id: st
    required property var core
    readonly property string key: "idle"
    readonly property real w: Math.max(190, wsBadge.implicitWidth + 140)
    readonly property real h: 34
    readonly property color accent: core.teal
    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    // ── small local widgets (each state file is self-contained) ──
    component Txt: Text { color: st.core.text; font.family: st.core.uiFont; font.pixelSize: 13; elide: Text.ElideRight }
    component Mono: Text { color: st.core.dim; font.family: st.core.monoFont; font.pixelSize: 10; elide: Text.ElideRight }
    component Ico: Text {
        property string alt: ""
        property string name: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 17; color: st.core.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    component Chip: Rectangle {
        property color tone: st.core.teal
        property string name: ""
        property string alt: ""
        implicitWidth: 32; implicitHeight: 32; radius: 16
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.15); border.width: 1; border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.35)
        Ico { anchors.centerIn: parent; name: parent.name; alt: parent.alt; color: parent.tone }
    }
    component Track: Rectangle {
        property real value: 0
        property color tone: st.core.teal
        implicitHeight: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.1)
        Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.value)); height: parent.height; radius: 3; color: parent.tone
            Behavior on width { NumberAnimation { duration: 90 } } }
    }
    Item {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
        Rectangle {
            id: wsBadge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: 20
            radius: 10
            color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.35)
            implicitWidth: Math.max(20, wsLabel.implicitWidth + 12)

            Txt {
                id: wsLabel
                anchors.centerIn: parent
                text: st.core.currentWsLabel
                color: st.core.teal
                font.family: st.core.monoFont
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
        Txt { anchors.centerIn: parent; text: st.core.timeText; font.family: st.core.monoFont; font.pixelSize: 11; font.weight: Font.DemiBold }
        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Canvas {
                id: pet
                property string pose: "sleep"
                property int tick: st.visible ? st.core.petTick : 0
                readonly property string skin: st.core.petSkin
                implicitWidth: S.W + 2
                implicitHeight: S.H + 2
                antialiasing: false
                Layout.alignment: Qt.AlignVCenter
                Component.onCompleted: requestPaint()
                onPoseChanged: requestPaint()
                onTickChanged: requestPaint()
                onSkinChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: S.draw(getContext("2d"), skin, pose, tick, 1, false, false)
            }
            Mono {
                visible: st.core.showTemp && st.core.temp > 0
                text: st.core.temp + "°C"
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
