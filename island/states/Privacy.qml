// Island state: privacy — mic in use (120×34) · camera in use (120×34) · screen sharing (130×34) · multi-sensor pill (190×34) · expanded attribution card (320×90)
// Live PipeWire audio/video node & V4L2 /dev/video* telemetry from Island.qml (`core`).
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: st
    required property var core
    readonly property string key: "privacy"

    readonly property bool active: core.mode === key
    readonly property var items: core.privacyItems || []
    // Keep one representative row per sensor kind so a second stream from
    // the same sensor can never hide camera or screen sharing in the matrix.
    readonly property var displayItems: [micItem, camItem, screenItem].filter(i => i !== null)
    readonly property int count: displayItems.length

    readonly property var micItem: items.find(i => i.kind === "mic") || null
    readonly property var camItem: items.find(i => i.kind === "cam") || null
    readonly property var screenItem: items.find(i => i.kind === "screen") || null

    readonly property bool hasMic: micItem !== null
    readonly property bool hasCam: camItem !== null
    readonly property bool hasScreen: screenItem !== null
    readonly property int kindCount: (hasMic ? 1 : 0) + (hasCam ? 1 : 0) + (hasScreen ? 1 : 0)

    readonly property bool expanded: (core.hovered || Boolean(core.privacyExpanded)) && count > 0
    readonly property bool showExpanded: expanded
    readonly property bool showMulti: !expanded && (count > 1 || kindCount > 1)
    readonly property bool showScreen: !expanded && !showMulti && hasScreen
    readonly property bool showCam: !expanded && !showMulti && !hasScreen && hasCam
    readonly property bool showMic: !expanded && !showMulti && !hasScreen && !hasCam

    readonly property string micApp: micItem && micItem.app ? String(micItem.app) : ""
    readonly property string camApp: camItem && camItem.app ? String(camItem.app) : ""

    readonly property real w: showExpanded ? 320 : showMulti ? 190 : showScreen ? 130 : 120
    readonly property real h: showExpanded ? 90 : 34
    readonly property color tone: (showMulti || (showExpanded && count > 1))
        ? core.lav
        : hasScreen
            ? core.coral
            : hasCam
                ? core.teal
                : core.amber
    readonly property color accent: tone

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function sensorColor(kind) {
        if (kind === "screen") return core.coral
        if (kind === "cam") return core.teal
        return core.amber
    }

    function sensorIcon(kind) {
        if (kind === "screen") return "screen_share"
        if (kind === "cam") return "videocam"
        return "mic"
    }

    function sensorAlt(kind) {
        if (kind === "screen") return "S"
        if (kind === "cam") return "C"
        return "M"
    }

    function focusClient(entry) {
        if (!entry || !entry.pid || Number(entry.pid) <= 0) return
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "pid:" + Number(entry.pid)])
    }

    // ── small local widgets ──
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    component Ico: Text {
        property string name: ""
        property string alt: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 15
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component Beacon: Item {
        id: bc
        property color dotColor: st.core.amber
        property bool activePulse: false
        implicitWidth: 12
        implicitHeight: 12

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: bc.dotColor
            opacity: 0.75
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: st.visible && bc.activePulse
                NumberAnimation { from: 1.0; to: 1.8; duration: 900 }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: st.visible && bc.activePulse
                NumberAnimation { from: 0.75; to: 0.0; duration: 900 }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: 3
            color: bc.dotColor
        }
    }

    // ═══════════ STATE 01: MICROPHONE IN USE (120×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showMic ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.focusClient(st.micItem)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 6

            Beacon {
                dotColor: st.core.amber
                activePulse: st.showMic
            }

            Ico {
                name: "mic"
                alt: "M"
                font.pixelSize: 15
                color: st.core.amber
            }

            Mono {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                visible: st.micApp !== ""
                text: st.micApp
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: st.core.dim
            }
        }
    }

    // ═══════════ STATE 02: CAMERA IN USE (120×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showCam ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.focusClient(st.camItem)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 6

            Beacon {
                dotColor: st.core.teal
                activePulse: st.showCam
            }

            Ico {
                name: "videocam"
                alt: "C"
                font.pixelSize: 15
                color: st.core.teal
            }

            Mono {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                visible: st.camApp !== ""
                text: st.camApp
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: st.core.dim
            }
        }
    }

    // ═══════════ STATE 03: SCREEN SHARING (130×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showScreen ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.focusClient(st.screenItem)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 10
            spacing: 6

            Beacon {
                dotColor: st.core.coral
                activePulse: st.showScreen
            }

            Ico {
                name: "screen_share"
                alt: "S"
                font.pixelSize: 15
                color: st.core.coral
            }

            Mono {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: "sharing"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: st.core.dim
            }
        }
    }

    // ═══════════ STATE 04A: MULTI-SENSOR COMPOUND PILL (190×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showMulti ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // Tri-Color Dot Cluster
            RowLayout {
                spacing: 6

                Rectangle {
                    visible: st.hasMic
                    width: 6
                    height: 6
                    radius: 3
                    color: st.core.amber
                }

                Rectangle {
                    visible: st.hasCam
                    width: 6
                    height: 6
                    radius: 3
                    color: st.core.teal
                }

                Rectangle {
                    visible: st.hasScreen
                    width: 6
                    height: 6
                    radius: 3
                    color: st.core.coral
                }
            }

            Item { Layout.fillWidth: true }

            // Glyph Array
            RowLayout {
                spacing: 4

                Ico {
                    visible: st.hasMic
                    name: "mic"
                    alt: "M"
                    font.pixelSize: 13
                    color: st.core.amber
                }

                Ico {
                    visible: st.hasCam
                    name: "videocam"
                    alt: "C"
                    font.pixelSize: 13
                    color: st.core.teal
                }

                Ico {
                    visible: st.hasScreen
                    name: "screen_share"
                    alt: "S"
                    font.pixelSize: 13
                    color: st.core.coral
                }
            }

            Item { Layout.fillWidth: true }

            // Counter Badge
            Rectangle {
                implicitHeight: 18
                implicitWidth: activeCntTxt.implicitWidth + 10
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.08)

                Mono {
                    id: activeCntTxt
                    anchors.centerIn: parent
                    text: st.count + " active"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: st.core.text
                }
            }
        }
    }

    // ═══════════ STATE 04B: EXPANDED ATTRIBUTION MATRIX (320×90) ═══════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2
        opacity: st.showExpanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Repeater {
            model: st.showExpanded ? st.displayItems : []

            delegate: Rectangle {
                id: attrRow
                required property var modelData
                required property int index
                readonly property color sColor: st.sensorColor(modelData.kind)
                readonly property string appName: modelData.app ? String(modelData.app) : ""
                readonly property string devName: modelData.detail ? String(modelData.detail) : ""

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: attrMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 6

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: attrRow.sColor
                    }

                    Ico {
                        name: st.sensorIcon(attrRow.modelData.kind)
                        alt: st.sensorAlt(attrRow.modelData.kind)
                        font.pixelSize: 14
                        color: attrRow.sColor
                    }

                    Mono {
                        visible: attrRow.appName !== ""
                        Layout.maximumWidth: 110
                        text: attrRow.appName
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: st.core.text
                    }

                    Mono {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        visible: attrRow.devName !== ""
                        text: attrRow.devName
                        font.pixelSize: 11
                        color: st.core.dim
                    }
                }

                MouseArea {
                    id: attrMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.focusClient(attrRow.modelData)
                }
            }
        }
    }
}
