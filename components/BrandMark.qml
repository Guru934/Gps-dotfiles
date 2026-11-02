import Quickshell
import QtQuick
import QtQuick.Shapes
import qs.config

Rectangle {
    id: root

    property var hub: null

    width: 28
    height: 28
    radius: 8
    color: brandMouse.containsMouse
        ? Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, 0.20)
        : Qt.rgba(Theme.card.r, Theme.card.g, Theme.card.b, 0.45)
    border.width: 1
    border.color: brandMouse.containsMouse
        ? Theme.brandAccent
        : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.45)

    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }

    scale: brandMouse.pressed ? 0.92 : (brandMouse.containsMouse ? 1.08 : 1.0)
    Behavior on scale {
        enabled: Theme.animationsEnabled && !Theme.reducedMotion
        NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
    }

    // Subtle hover glow aura
    Rectangle {
        id: glowAura
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 12
        color: Theme.brandAccent
        opacity: brandMouse.containsMouse ? 0.28 : 0.0
        z: -1
        Behavior on opacity {
            enabled: Theme.animationsEnabled && !Theme.reducedMotion
            NumberAnimation { duration: 200 }
        }
    }

    // Crisp Vector Mark (Geometric Hexagonal Prism Emblem)
    Shape {
        id: markShape
        anchors.centerIn: parent
        width: 18
        height: 18
        layer.enabled: true
        layer.samples: 4

        // Outer Hexagon
        ShapePath {
            strokeColor: brandMouse.containsMouse ? Theme.brandAccent : Theme.accentSecondary
            strokeWidth: 1.5
            fillColor: Qt.rgba(Theme.brandAccent.r, Theme.brandAccent.g, Theme.brandAccent.b, brandMouse.containsMouse ? 0.40 : 0.18)
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            startX: 9; startY: 1
            PathLine { x: 17; y: 5.5 }
            PathLine { x: 17; y: 12.5 }
            PathLine { x: 9; y: 17 }
            PathLine { x: 1; y: 12.5 }
            PathLine { x: 1; y: 5.5 }
            PathLine { x: 9; y: 1 }
        }

        // Vertical Center Facet
        ShapePath {
            strokeColor: Theme.brandAccent
            strokeWidth: 1.2
            fillColor: "transparent"

            startX: 9; startY: 1
            PathLine { x: 9; y: 17 }
        }

        // Horizontal Cross Facet
        ShapePath {
            strokeColor: Theme.brandAccent
            strokeWidth: 1.0
            fillColor: "transparent"

            startX: 1; startY: 9
            PathLine { x: 17; y: 9 }
        }
    }

    MouseArea {
        id: brandMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.hub) root.hub.setTooltip("Application Launcher (Super)")
        onExited: if (root.hub) root.hub.clearTooltip()
        onClicked: {
            var script = (root.hub && root.hub.repoRoot) ? (root.hub.repoRoot + "/scripts/gps-ipc") : "gps-ipc"
            Quickshell.execDetached([script, "island", "launcher", "toggle"])
        }
    }
}
