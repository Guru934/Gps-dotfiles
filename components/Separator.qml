import QtQuick
import qs.config

// GPS Reusable Separator
// Consistent 1px divider for panels, cards, and toolbars.
Rectangle {
    id: root

    property int orientation: Qt.Horizontal // Qt.Horizontal | Qt.Vertical
    property color strokeColor: Theme.outlineSoft

    implicitWidth: orientation === Qt.Horizontal ? (parent ? parent.width : 100) : Theme.borderWidth
    implicitHeight: orientation === Qt.Horizontal ? Theme.borderWidth : (parent ? parent.height : 100)

    color: strokeColor
    opacity: 0.65
}
