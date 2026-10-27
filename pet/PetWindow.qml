import QtQuick
import Quickshell
import Quickshell.Wayland

// Transparent full-screen overlay. Only the pet itself takes mouse input (mask), everything else passes through.
PanelWindow {
    id: win

    required property var brain
    required property var settings
    required property var theme
    property string wantScreenName: ""
    property bool shown: true

    signal openPanel()

    screen: {
        var list = Quickshell.screens;
        for (var i = 0; i < list.length; i++) if (list[i].name === wantScreenName) return list[i];
        return list.length ? list[0] : null;
    }
    color: "transparent"
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "pet"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: hit }

    // ---- floating effects (hearts, zzz, notes, !) ------------------------------
    ListModel { id: fxModel }
    function addEffect(kind, x, y) {
        if (fxModel.count > 24) fxModel.remove(0);
        fxModel.append({ kind: kind, ex: x, ey: y });
    }

    Repeater {
        model: fxModel
        delegate: Item {
            id: e
            required property int index
            required property string kind
            required property real ex
            required property real ey
            x: ex; y: ey
            readonly property var glyph: ({ heart: "♥", zzz: "z", note: "♪", bang: "!", sparkle: "✦", poof: "" })
            readonly property var tint: ({ heart: win.theme.coral, zzz: win.theme.primary, note: win.theme.secondary,
                                           bang: win.theme.coral, sparkle: win.theme.tertiary, poof: win.theme.dim })
            Text {
                visible: e.kind !== "poof"
                text: e.glyph[e.kind]
                color: e.tint[e.kind]
                font.family: win.theme.mono
                font.pixelSize: e.kind === "bang" ? win.settings.scale * 7 : win.settings.scale * 5
                font.bold: true
            }
            Rectangle {
                visible: e.kind === "poof"
                id: puff
                width: 10; height: 10; radius: 5; anchors.centerIn: parent
                color: win.theme.dim
            }
            ParallelAnimation {
                running: true
                NumberAnimation { target: e; property: "y"; to: e.ey - (e.kind === "bang" ? 10 : 34); duration: e.kind === "poof" ? 500 : 1300; easing.type: Easing.OutCubic }
                NumberAnimation { target: e; property: "opacity"; from: 1; to: 0; duration: e.kind === "poof" ? 500 : 1300 }
                NumberAnimation { target: puff; property: "scale"; from: 0.5; to: 4; duration: 500; easing.type: Easing.OutCubic }
                onFinished: if (e.index >= 0 && e.index < fxModel.count) fxModel.remove(e.index)
            }
        }
    }

    // ---- the pet ---------------------------------------------------------------
    Item {
        id: hit
        width: sprite.width
        height: sprite.height
        x: win.brain.px - width / 2
        y: win.brain.py - height + sprite.px

        PetSprite {
            id: sprite
            skin: win.settings.character
            pose: win.brain.pose
            tick: win.brain.tick
            px: win.settings.scale
            flip: win.brain.facing < 0
            opacity: win.brain.mode === "sleep" ? 0.85 : 1
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property bool dragging: false
            property bool wasDragged: false
            property real pressX: 0
            property real pressY: 0
            onPressed: mouse => { pressX = mouse.x; pressY = mouse.y; dragging = false; wasDragged = false }
            onPositionChanged: mouse => {
                if (!(pressedButtons & Qt.LeftButton)) return;
                if (!dragging && (Math.abs(mouse.x - pressX) > 6 || Math.abs(mouse.y - pressY) > 6)) {
                    dragging = true; wasDragged = true;
                    win.brain.beginDrag();
                }
                if (dragging) {
                    var p = ma.mapToItem(win.contentItem, mouse.x, mouse.y);
                    win.brain.dragTo(p.x, p.y + hit.height * 0.45);
                }
            }
            onReleased: mouse => { if (dragging) { dragging = false; win.brain.endDrag() } }
            onClicked: mouse => {
                if (wasDragged) return;
                if (mouse.button === Qt.RightButton) win.openPanel();
                else win.brain.pet();
            }
            onDoubleClicked: mouse => { if (!wasDragged && mouse.button === Qt.LeftButton) win.openPanel() }
        }
    }
}
