import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.config
import qs.components.dashboard

// Circular track artwork with an orbiting accent arc. Extracted from the
// original NowPlayingCard implementation so the Home card and the Media tab
// share one disc. The image is cropped to a true circle via an alpha mask
// (rectangle clipping ignores rounded corners); aspect is preserved with a
// center crop. `orbiting` spins the arc (e.g. while the track is playing).
Item {
    id: root
    property string artUrl: ""
    property int diameter: 64
    property bool orbiting: false

    readonly property bool artReady: art.status === Image.Ready
    readonly property int innerSize: Math.max(8, root.diameter - 12)

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    Rectangle {
        anchors.fill: parent
        radius: root.diameter / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.45)
    }

    Shape {
        id: orbit
        anchors.fill: parent
        antialiasing: true

        NumberAnimation on rotation {
            running: root.orbiting
            from: 0
            to: 360
            duration: 18000
            loops: Animation.Infinite
        }

        ShapePath {
            strokeColor: Theme.accentPrimary
            strokeWidth: 2.5
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.diameter / 2
                centerY: root.diameter / 2
                radiusX: root.diameter / 2 - 1
                radiusY: root.diameter / 2 - 1
                startAngle: -90
                sweepAngle: 280
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.innerSize
        height: root.innerSize
        radius: root.innerSize / 2
        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.5)
        border.width: 1
        border.color: root.artReady
            ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.35)
            : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.6)

        Image {
            id: art
            anchors.fill: parent
            source: root.artUrl.length > 0 ? root.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }

        Item {
            id: artMask
            anchors.fill: parent
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "black"
            }
        }

        OpacityMask {
            anchors.fill: parent
            visible: root.artReady
            source: art
            maskSource: artMask
        }

        DashIcon {
            anchors.centerIn: parent
            visible: !root.artReady
            name: "music_note"
            color: Theme.textDim
            font.pixelSize: Math.round(root.diameter * 0.34)
        }
    }
}
