import QtQuick
import qs.config

// GPS Reusable Icon Button
// Configurable button with hover states, active indicators, tooltips, and scroll events.
Rectangle {
    id: root

    property string icon: ""
    property bool isSymbol: false
    property real iconSize: Theme.iconSm
    property real size: Theme.controlHeightMd
    property color accentColor: Theme.brandAccent
    property color textColor: Theme.textMain
    property color baseColor: "transparent"
    property bool active: false
    property bool danger: false
    property string tooltipText: ""
    property real cornerRadius: Theme.radiusSm

    readonly property bool containsMouse: mouseArea.containsMouse
    readonly property bool pressed: mouseArea.pressed

    signal clicked()
    signal scrolledUp()
    signal scrolledDown()

    implicitWidth: size
    implicitHeight: size
    radius: cornerRadius

    color: danger
        ? (active
            ? Theme.statusDangerBorder
            : (containsMouse ? Theme.statusDangerBg : Qt.alpha(Theme.statusDangerBg, 0.45)))
        : (active
            ? Qt.alpha(accentColor, 0.22)
            : (containsMouse ? Qt.alpha(accentColor, 0.12) : baseColor))

    border.width: (active || containsMouse || danger) ? Theme.borderWidth : 0
    border.color: danger
        ? (active || containsMouse ? Theme.statusDangerBorder : Qt.alpha(Theme.statusDangerBorder, 0.45))
        : (active ? accentColor : (containsMouse ? Qt.alpha(accentColor, 0.50) : "transparent"))

    scale: pressed ? 0.94 : (containsMouse ? 1.04 : 1.0)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.danger
            ? (root.active ? "#FFFFFF" : Theme.statusDangerFg)
            : (root.active ? root.accentColor : (root.containsMouse ? root.textColor : Theme.textDim))
        font.family: root.isSymbol ? "Material Symbols Rounded" : Theme.fontUi
        font.pixelSize: root.iconSize
        font.bold: root.active
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onWheel: (wheel) => {
            if (wheel.angleDelta.y > 0) root.scrolledUp()
            else if (wheel.angleDelta.y < 0) root.scrolledDown()
        }
    }
}
