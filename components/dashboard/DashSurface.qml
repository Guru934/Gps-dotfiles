import QtQuick
import qs.config

// Rounded panel surface with a 1px hairline. Callers may override the
// inherited Rectangle properties (radius, border.width, ...) directly.
Rectangle {
    property color fill: Theme.surfaceBase
    property color stroke: Theme.outlineSoft

    radius: Theme.radiusDrawer
    color: fill
    border.width: 1
    border.color: stroke
}
