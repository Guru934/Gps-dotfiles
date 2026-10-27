import QtQuick
import QtQuick.Layouts
import Quickshell
import "PetSprites.js" as S

// The pet's own control panel: a normal floating window.
// Tip: give it a float rule in Hyprland by matching the window title "Pet Companion".
FloatingWindow {
    id: panel

    required property var brain
    required property var settings
    required property var theme
    property var actions: ({})      // set by Pet.qml: { callHere(), perch() , respawn() }
    property bool perchAvailable: false

    title: "Pet Companion"
    implicitWidth: 460
    implicitHeight: 700
    minimumSize: Qt.size(400, 420)
    color: theme.bg

    function skinLabel(id) { return S.skin(id).label }

    function groundLabel() {
        var g = brain.groundId;
        if (g === "") return "IN AIR";
        if (g === "floor") return "SCREEN FLOOR";
        if (g === "perch") return "ISLAND PERCH";
        return "WINDOW EDGE";
    }
    function napText() {
        var m = Math.floor(brain.sleepSeconds / 60);
        if (m < 60) return m + " min";
        return Math.floor(m / 60) + " h " + (m % 60) + " m";
    }
    function activityText(a) { return a < 0.7 ? "LAZY" : (a < 1.3 ? "NORMAL" : (a < 1.7 ? "ACTIVE" : "HYPER")) }
    function sleepText(s) { return s < 90 ? s + " s" : Math.round(s / 60) + " min" }

    Rectangle { anchors.fill: parent; color: panel.theme.bg }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 16; y: 16
            width: parent.width - 32
            spacing: 12

            // ---- header ----------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Rectangle { Layout.preferredWidth: 7; Layout.preferredHeight: 7; radius: 4; color: panel.theme.primary }
                Text { text: "PET // COMPANION"; color: panel.theme.text; font.family: panel.theme.head; font.pixelSize: 16; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                PetChip {
                    theme: panel.theme
                    text: panel.settings.enabled ? "ON" : "OFF"
                    accent: panel.settings.enabled ? panel.theme.primary : panel.theme.mute
                    onClicked: panel.settings.enabled = !panel.settings.enabled
                }
            }

            // ---- stage -------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "LIVE"
                tag: panel.groundLabel()
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Rectangle {
                        Layout.preferredWidth: 150; Layout.preferredHeight: 138
                        radius: 12; color: panel.theme.surface
                        PetSprite {
                            anchors.centerIn: parent
                            skin: panel.settings.character
                            pose: panel.brain.pose
                            tick: panel.brain.tick
                            px: 5
                            flip: panel.brain.facing < 0
                        }
                        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 14; anchors.horizontalCenter: parent.horizontalCenter; width: 110; height: 2; color: panel.theme.line }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextInput {
                            id: nameInput
                            Layout.fillWidth: true
                            text: panel.settings.petName
                            color: panel.theme.text
                            font.family: panel.theme.head; font.pixelSize: 18; font.weight: Font.DemiBold
                            selectByMouse: true
                            maximumLength: 24
                            onEditingFinished: panel.settings.petName = text
                            Text { visible: nameInput.text === "" && !nameInput.activeFocus; text: "Name your pet"; color: panel.theme.mute; font: nameInput.font }
                        }
                        Text { text: "STATE  " + panel.brain.mode.toUpperCase(); color: panel.theme.primary; font.family: panel.theme.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                        Text { text: panel.skinLabel(panel.settings.character).toUpperCase(); color: panel.theme.mute; font.family: panel.theme.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                        Item { Layout.fillHeight: true }
                        Text {
                            Layout.fillWidth: true
                            text: "Click = pet · drag = carry · double-click or right-click = this panel"
                            color: panel.theme.mute; font.family: panel.theme.body; font.pixelSize: 11; wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ---- skins ---------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "COMPANION SKINS"
                tag: S.order.length + " PRESETS"
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    rowSpacing: 8; columnSpacing: 8
                    Repeater {
                        model: S.order
                        delegate: Rectangle {
                            id: cell
                            required property string modelData
                            readonly property bool on: panel.settings.character === modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 84
                            radius: 12
                            color: on ? panel.theme.cardHi : panel.theme.surface
                            border.width: on ? 1 : 0
                            border.color: panel.theme.primary
                            PetSprite {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 6
                                skin: cell.modelData
                                pose: cell.on ? panel.brain.pose : (hover.containsMouse ? "happy" : "sit")
                                tick: cell.on ? panel.brain.tick : 0
                                autoTick: !cell.on && hover.containsMouse
                                px: 2
                            }
                            Text {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6; anchors.horizontalCenter: parent.horizontalCenter
                                text: panel.skinLabel(cell.modelData).split(" ")[0]
                                color: cell.on ? panel.theme.primary : panel.theme.mute
                                font.family: panel.theme.mono; font.pixelSize: 9
                            }
                            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.settings.character = cell.modelData }
                        }
                    }
                }
            }

            // ---- vitals --------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "VITALS"
                Repeater {
                    model: [
                        { n: "ENERGY", v: panel.brain.energy, c: panel.theme.primary },
                        { n: "MOOD", v: panel.brain.mood, c: panel.theme.coral }
                    ]
                    delegate: RowLayout {
                        id: vrow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Text { Layout.preferredWidth: 56; text: vrow.modelData.n; color: panel.theme.dim; font.family: panel.theme.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: panel.theme.cardTop
                            Rectangle { height: parent.height; radius: 3; color: vrow.modelData.c; width: parent.width * Math.max(0, Math.min(1, vrow.modelData.v / 100)) }
                        }
                        Text { Layout.preferredWidth: 28; horizontalAlignment: Text.AlignRight; text: Math.round(vrow.modelData.v); color: panel.theme.text; font.family: panel.theme.mono; font.pixelSize: 10 }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [
                            { n: "STEPS", v: Math.round(panel.brain.steps) },
                            { n: "PETTED", v: panel.brain.pets },
                            { n: "NAPS", v: panel.napText() }
                        ]
                        delegate: Rectangle {
                            id: stat
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 10; color: panel.theme.surface
                            Column {
                                anchors.centerIn: parent; spacing: 2
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: stat.modelData.v; color: panel.theme.text; font.family: panel.theme.mono; font.pixelSize: 13; font.weight: Font.DemiBold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: stat.modelData.n; color: panel.theme.mute; font.family: panel.theme.mono; font.pixelSize: 8; font.letterSpacing: 1 }
                            }
                        }
                    }
                }
            }

            // ---- actions ---------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "PLAY"
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    PetChip { theme: panel.theme; text: "COME HERE"; onClicked: panel.actions.callHere() }
                    PetChip { theme: panel.theme; text: "WAVE"; onClicked: panel.brain.wave() }
                    PetChip { theme: panel.theme; text: "HOP"; onClicked: panel.brain.hop() }
                    PetChip { theme: panel.theme; text: "DANCE"; accent: panel.theme.secondary; onClicked: panel.brain.dance() }
                    PetChip { theme: panel.theme; text: "NAP"; accent: panel.theme.tertiary; onClicked: panel.brain.doSleep() }
                    PetChip { theme: panel.theme; text: "PET"; accent: panel.theme.coral; onClicked: panel.brain.pet() }
                    PetChip { theme: panel.theme; text: "DROP IN"; onClicked: panel.brain.respawn() }
                    PetChip { theme: panel.theme; visible: panel.perchAvailable; text: "PERCH"; onClicked: panel.actions.perch() }
                }
            }

            // ---- behaviour ----------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "BEHAVIOUR"
                PetToggle { theme: panel.theme; label: "Roam around"; hint: "Wander, jump and explore on its own"; checked: panel.settings.roam; onToggled: v => panel.settings.roam = v }
                PetToggle { theme: panel.theme; label: "Walk on windows"; hint: "Use window edges as ledges"; checked: panel.settings.windowEdges; onToggled: v => panel.settings.windowEdges = v }
                PetToggle { theme: panel.theme; label: "Follow the cursor"; hint: "Looks at it, sometimes chases it"; checked: panel.settings.followCursor; onToggled: v => panel.settings.followCursor = v }
                PetToggle { theme: panel.theme; label: "Dance to music"; hint: "Any MPRIS player, e.g. Brave"; checked: panel.settings.reactMusic; onToggled: v => panel.settings.reactMusic = v }
                PetToggle { theme: panel.theme; label: "Sleep when idle"; hint: "Naps when you stop moving the mouse"; checked: panel.settings.sleepWhenIdle; onToggled: v => panel.settings.sleepWhenIdle = v }
                PetToggle { theme: panel.theme; label: "React to alerts"; hint: "Startles on agent permission requests"; checked: panel.settings.reactAlerts; onToggled: v => panel.settings.reactAlerts = v }
                PetToggle { theme: panel.theme; label: "Hide in fullscreen"; checked: panel.settings.hideFullscreen; onToggled: v => panel.settings.hideFullscreen = v }
                PetToggle { theme: panel.theme; label: "Drop in on workspace change"; checked: panel.settings.respawnOnWorkspace; onToggled: v => panel.settings.respawnOnWorkspace = v }
            }

            // ---- tuning ------------------------------------------------------------------------
            PetCard {
                theme: panel.theme
                title: "TUNING"
                PetSlider { theme: panel.theme; label: "Size"; valueText: panel.settings.scale + "×"; from: 2; to: 6; step: 1; value: panel.settings.scale; onMoved: v => panel.settings.scale = v }
                PetSlider { theme: panel.theme; label: "Energy of the pet"; valueText: panel.activityText(panel.settings.activity); from: 0.4; to: 2; step: 0.1; value: panel.settings.activity; onMoved: v => panel.settings.activity = v }
                PetSlider { theme: panel.theme; label: "Nap after idle"; valueText: panel.sleepText(panel.settings.sleepAfter); from: 20; to: 600; step: 10; value: panel.settings.sleepAfter; onMoved: v => panel.settings.sleepAfter = v }
            }

            Text {
                Layout.fillWidth: true
                text: "IPC  qs ipc call pet  ·  panel  toggle  wave  dance  hop  nap  callHere  respawn  perch  alert <sticky>  clear  skin <id>  status"
                color: panel.theme.mute; font.family: panel.theme.mono; font.pixelSize: 9; wrapMode: Text.WordWrap
            }
        }
    }
}
