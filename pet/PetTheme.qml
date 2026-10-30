import QtQuick
import qs.config

// Colour tokens copied from the Stitch design (Tide Island). Instantiate once, pass around.
QtObject {
    readonly property color bg: (typeof Theme !== "undefined" && Theme.surfaceDeep) ? Theme.surfaceDeep : "#0b0e16"
    readonly property color surface: (typeof Theme !== "undefined" && Theme.surface) ? Theme.surface : "#10131b"
    readonly property color card: (typeof Theme !== "undefined" && Theme.card) ? Theme.card : "#181b24"
    readonly property color cardHi: (typeof Theme !== "undefined" && Theme.cardHover) ? Theme.cardHover : "#272a32"
    readonly property color cardTop: (typeof Theme !== "undefined" && Theme.surfaceVariant) ? Theme.surfaceVariant : "#32353d"
    readonly property color line: (typeof Theme !== "undefined" && Theme.border) ? Theme.border : "#3c4a46"
    readonly property color text: (typeof Theme !== "undefined" && Theme.textMain) ? Theme.textMain : "#e0e2ed"
    readonly property color dim: (typeof Theme !== "undefined" && Theme.textMuted) ? Theme.textMuted : "#bacac5"
    readonly property color mute: (typeof Theme !== "undefined" && Theme.textDim) ? Theme.textDim : "#859490"
    readonly property color primary: (typeof Theme !== "undefined" && Theme.brandAccent) ? Theme.brandAccent : "#57f1db"
    readonly property color inkOnPrimary: (typeof Theme !== "undefined" && Theme.brandAccentFg) ? Theme.brandAccentFg : "#003731"
    readonly property color secondary: (typeof Theme !== "undefined" && Theme.accentSecondary) ? Theme.accentSecondary : "#ddb8ff"
    readonly property color tertiary: (typeof Theme !== "undefined" && Theme.accentTertiary) ? Theme.accentTertiary : "#ffd47b"
    readonly property color error: (typeof Theme !== "undefined" && Theme.statusDanger) ? Theme.statusDanger : "#ffb4ab"
    readonly property color coral: (typeof Theme !== "undefined" && Theme.statusDangerFg) ? Theme.statusDangerFg : "#ff5d7a"
    readonly property string mono: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "JetBrains Mono"
    readonly property string head: (typeof Theme !== "undefined" && Theme.fontUi) ? Theme.fontUi : "Plus Jakarta Sans"
    readonly property string body: (typeof Theme !== "undefined" && Theme.fontUi) ? Theme.fontUi : "Plus Jakarta Sans"
}
