import QtQuick
import qs.config

// Material Symbols icon. Ligature name goes in `name`; callers override the
// inherited Text properties (font.pixelSize, color) as usual.
Text {
    id: root
    property string name: ""
    property bool filled: false

    text: root.name
    color: Theme.textMuted
    font.family: "Material Symbols Rounded"
    font.pixelSize: Theme.iconMd
    font.variableAxes: { "FILL": root.filled ? 1.0 : 0.0 }
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
