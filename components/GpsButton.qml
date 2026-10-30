import QtQuick
import QtQuick.Layouts
import qs.config

// GPS Reusable Interactive Button (Layer 4)
// Provides consistent styling across primary, secondary, ghost, and danger variants.
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property bool isSymbol: false
    property string variant: "secondary" // "primary" | "secondary" | "ghost" | "danger"
    property string size: "md"           // "sm" (24) | "md" (32) | "lg" (40)
    property bool active: false
    property bool disabled: false
    property real customRadius: -1

    signal clicked()

    readonly property bool hovered: mouseArea.containsMouse && !disabled
    readonly property bool pressed: mouseArea.pressed && !disabled

    implicitHeight: size === "sm" ? Theme.controlHeightSm : (size === "lg" ? Theme.controlHeightLg : Theme.controlHeightMd)
    implicitWidth: contentRow.implicitWidth + (size === "sm" ? 16 : 24)
    radius: customRadius >= 0 ? customRadius : (size === "sm" ? Theme.radiusSm : Theme.radiusMd)

    color: {
        if (disabled) return Qt.alpha(Theme.card, 0.40)
        switch (variant) {
        case "primary":
            return pressed ? Qt.darker(Theme.brandAccent, 1.15) : (hovered ? Qt.lighter(Theme.brandAccent, 1.1) : Theme.brandAccent)
        case "danger":
            return pressed ? Qt.darker(Theme.statusDangerBorder, 1.2) : (hovered ? Theme.statusDangerBorder : Theme.statusDangerBg)
        case "ghost":
            return pressed ? Qt.alpha(Theme.cardHover, 0.7) : (hovered ? Theme.cardHover : "transparent")
        case "secondary":
        default:
            return pressed ? Theme.surfaceHigh : (hovered ? Theme.cardHover : Theme.card)
        }
    }

    border.width: Theme.borderWidth
    border.color: {
        if (disabled) return Theme.outlineSoft
        switch (variant) {
        case "primary":
            return "transparent"
        case "danger":
            return Theme.statusDangerBorder
        case "ghost":
            return hovered ? Theme.outlineSoft : "transparent"
        case "secondary":
        default:
            return active ? Theme.brandAccent : (hovered ? Qt.lighter(Theme.outlineSoft, 1.2) : Theme.outlineSoft)
        }
    }

    scale: pressed ? 0.97 : (hovered ? 1.01 : 1.0)

    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: Theme.spacingSm

        Text {
            visible: root.icon !== ""
            text: root.icon
            font.family: root.isSymbol ? "Material Symbols Rounded" : Theme.fontUi
            font.pixelSize: root.size === "sm" ? Theme.iconXs : Theme.iconSm
            color: root.textColor
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: root.text !== ""
            text: root.text
            color: root.textColor
            font.family: Theme.fontUi
            font.pixelSize: root.size === "sm" ? Theme.fontSizeSmall : (root.size === "lg" ? Theme.fontSizeBody : Theme.fontSizeSecondary)
            font.bold: root.variant === "primary" || root.variant === "danger"
            Layout.alignment: Qt.AlignVCenter
        }
    }

    readonly property color textColor: {
        if (disabled) return Theme.textDim
        switch (variant) {
        case "primary": return Theme.brandAccentFg
        case "danger": return hovered ? "#FFFFFF" : Theme.statusDangerFg
        case "ghost": return hovered ? Theme.textMain : Theme.textDim
        case "secondary":
        default:
            return active ? Theme.brandAccent : (hovered ? Theme.textMain : Theme.textDim)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
