import QtQuick
import "PetSprites.js" as S

// Renders one pet frame on a Canvas. `px` = screen pixels per sprite cell (use whole numbers).
Item {
    id: root
    property string skin: "cat"
    property string pose: "sit"
    property int tick: 0
    property int px: 3
    property bool flip: false
    property bool autoTick: false      // previews animate themselves

    width: (S.W + 2) * px
    height: (S.H + 2) * px

    property string _lastSignature: ""

    function checkRepaint() {
        var fr = S.build(root.skin, root.pose, root.tick);
        var sig = root.skin + "|" + root.pose + "|" + root.px + "|" + (root.flip ? "1" : "0") + "|" + JSON.stringify(fr.rects);
        if (sig !== root._lastSignature) {
            root._lastSignature = sig;
            cv.requestPaint();
        }
    }

    onSkinChanged: checkRepaint()
    onPoseChanged: checkRepaint()
    onTickChanged: checkRepaint()
    onPxChanged: checkRepaint()
    onFlipChanged: checkRepaint()

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: false
        onPaint: {
            var ctx = getContext("2d");
            S.draw(ctx, root.skin, root.pose, root.tick, root.px, root.flip);
        }
        Component.onCompleted: root.checkRepaint()
    }

    Timer {
        interval: 125
        repeat: true
        running: root.autoTick && root.visible
        onTriggered: root.tick++
    }
}
