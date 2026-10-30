import QtQuick
import qs.config
import qs.components.dashboard

// Segmented tab strip. Model entries: { key, label, icon }. Purely a
// presentational selector: currentIndex is owned by the caller, activation
// emits tabSelected(key, index).
Item {
    id: root
    property var tabs: []
    property int currentIndex: 0

    signal tabSelected(string key, int index)

    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl + 2
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.outlineSoft
    }

    Row {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 3

        Repeater {
            model: root.tabs

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                readonly property bool active: cell.index === root.currentIndex

                width: (root.width - 6 - 3 * Math.max(0, root.tabs.length - 1)) / Math.max(1, root.tabs.length)
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusControl
                    color: cell.active
                        ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.16)
                        : (cellHover.hovered ? Theme.surfaceVariant : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    DashIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: cell.modelData.icon
                        filled: cell.active
                        color: cell.active
                            ? Theme.accentPrimary
                            : (cellHover.hovered ? Theme.textMain : Theme.textDim)
                        font.pixelSize: 15
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.label
                        color: cell.active
                            ? Theme.accentPrimary
                            : (cellHover.hovered ? Theme.textMain : Theme.textDim)
                        font.family: Theme.fontMono
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }

                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.tabSelected(cell.modelData.key, cell.index) }
            }
        }
    }
}
