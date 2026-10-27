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

    onSkinChanged: cv.requestPaint()
    onPoseChanged: cv.requestPaint()
    onTickChanged: cv.requestPaint()
    onPxChanged: cv.requestPaint()
    onFlipChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: false
        onPaint: {
            var ctx = getContext("2d");
            S.draw(ctx, root.skin, root.pose, root.tick, root.px, root.flip);
        }
        Component.onCompleted: requestPaint()
    }

    Timer {
        interval: 125
        repeat: true
        running: root.autoTick && root.visible
        onTriggered: root.tick++
    }
}
