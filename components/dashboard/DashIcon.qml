import QtQuick

// Material Symbols icon. Ligature name goes in `name`; callers override the
// inherited Text properties (font.pixelSize, color) as usual.
Text {
    id: root
    property string name: ""
    property bool filled: false

    text: root.name
    color: "#BACAC5"
    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    font.variableAxes: { "FILL": root.filled ? 1.0 : 0.0 }
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
