import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.dashboard

// Quick-control card from the home design: round tinted icon, title and
// status subtitle on the left, a state dot on the right. Used by the Wi-Fi,
// Bluetooth, audio and night-light entries. Purely presentational: the caller
// owns state and performs the real action in onActivated.
Item {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color accent: Theme.accentPrimary
    property color dotColor: Theme.textDim
    property bool interactive: true
    property bool dimmed: false

    signal activated()

    implicitHeight: 54

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        color: root.interactive && hover.hovered ? Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.95) : Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.6)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 10
        spacing: Theme.dashboardSpacingSm
        opacity: root.dimmed ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 28
            implicitHeight: 28
            radius: 14
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)

            DashIcon {
                anchors.centerIn: parent
                name: root.icon
                color: root.accent
                font.pixelSize: Theme.dashboardText(15)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.textMain
                font.family: Theme.fontUi
                font.pixelSize: Theme.dashboardText(12)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.subtitle
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: root.dimmed ? Theme.surfaceVariant : root.dotColor
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.interactive
        onTapped: root.activated()
    }
}
