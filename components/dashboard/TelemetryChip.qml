import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.dashboard

// Mono readout chip: small caps label above a bold mono value, optional icon.
Rectangle {
    id: root
    property string label: ""
    property string value: ""
    property string icon: ""
    property color accent: Theme.textMain
    property color fill: Theme.surfaceHigh
    property color stroke: Theme.outlineSoft

    implicitWidth: chipRow.implicitWidth + 20
    implicitHeight: Math.max(42, chipRow.implicitHeight + 12)
    radius: Theme.radiusControl
    color: root.fill
    border.width: 1
    border.color: root.stroke

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 8

        DashIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: root.icon.length > 0
            name: root.icon
            color: root.accent
            font.pixelSize: 16
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.label.toUpperCase()
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                Layout.fillWidth: true
                text: root.value
                color: root.accent
                font.family: Theme.fontMono
                font.pixelSize: 13
                font.bold: true
            }
        }
    }
}
