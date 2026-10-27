import QtQuick
import QtQuick.Layouts
import qs.config

// Real-level spectrum bars. `levels` is the normalized 0..1 band array from
// the shared AudioSpectrum sampler; bars are bottom-anchored and follow the
// same geometry/animation as the original Home pipeline. Presentation only:
// the caller supplies the surrounding surface.
Item {
    id: root
    property var levels: []
    property int barCount: 18
    property int barSpacing: 3

    RowLayout {
        anchors.fill: parent
        spacing: root.barSpacing

        Repeater {
            model: root.barCount

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: Math.max(2, Math.round((root.levels[index] || 0) * (parent.height - 2)))
                    radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentSecondary }
                        GradientStop { position: 0.5; color: Theme.accentPrimary }
                        GradientStop { position: 1.0; color: Theme.accentPrimaryDim }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
