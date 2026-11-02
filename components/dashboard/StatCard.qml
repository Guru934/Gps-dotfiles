import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.dashboard

// Telemetry chip from the home design: caps label with an optional colored
// pill, a bold value line and a hairline progress bar in the accent color.
Item {
    id: root
    property string label: ""
    property string value: ""
    property string pill: ""
    property real fraction: 0
    property color accent: Theme.accentPrimary

    implicitHeight: column.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        color: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.55)
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 8
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.label.toUpperCase()
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
                font.letterSpacing: 0.6
            }

            Rectangle {
                visible: root.pill.length > 0
                implicitWidth: pillText.implicitWidth + 10
                implicitHeight: 13
                radius: 7
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)

                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: root.pill
                    color: root.accent
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                    font.bold: true
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.value
            color: Theme.textMain
            font.family: Theme.fontMono
            font.pixelSize: Theme.dashboardText(13)
            font.bold: true
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            radius: 1.5
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.fraction))
                height: parent.height
                radius: parent.radius
                color: root.accent
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }
}
