// Island state: workspace transient indicator. Loaded by Island.qml.
import QtQuick
import QtQuick.Layouts

Item {
    id: st
    required property var core
    readonly property string key: "workspace"
    readonly property real w: Math.max(160, contentRow.implicitWidth + 32)
    readonly property real h: 34
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    // ── small local widgets ──
    component Txt: Text { color: st.core.text; font.family: st.core.uiFont; font.pixelSize: 13; elide: Text.ElideRight }
    component Mono: Text { color: st.core.dim; font.family: st.core.monoFont; font.pixelSize: 10; elide: Text.ElideRight }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 12

            // Workspace number + name badge
            Rectangle {
                id: wsBadge
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

            // Row of workspace dots with sliding highlight
            Item {
                id: dotsTrack
                anchors.verticalCenter: parent.verticalCenter
                readonly property var list: st.core.allWorkspaces && st.core.allWorkspaces.length > 0 ? st.core.allWorkspaces : [1, 2, 3, 4, 5]
                readonly property real slotW: 13
                implicitWidth: list.length * slotW
                implicitHeight: 16

                // Inactive dots for all workspaces
                Repeater {
                    model: dotsTrack.list
                    delegate: Item {
                        required property int index
                        required property int modelData
                        x: index * dotsTrack.slotW
                        width: dotsTrack.slotW
                        height: dotsTrack.height

                        Rectangle {
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Qt.rgba(1, 1, 1, 0.22)
                        }
                    }
                }

                // Active highlight capsule sliding in direction of change
                Rectangle {
                    id: highlight
                    readonly property int activeIdx: {
                        const idx = dotsTrack.list.indexOf(st.core.wsId)
                        return idx >= 0 ? idx : 0
                    }
                    width: 13
                    height: 5
                    radius: 2.5
                    color: st.core.teal
                    anchors.verticalCenter: parent.verticalCenter
                    x: activeIdx * dotsTrack.slotW + (dotsTrack.slotW - width) / 2

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
