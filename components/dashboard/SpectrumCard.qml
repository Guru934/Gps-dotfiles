import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.dashboard

// Live audio spectrum card. Real band levels come from the shared
// AudioSpectrum sampler (scripts/audio-spectrum.py, numpy FFT over parec),
// which captures only while at least one dashboard consumer is alive. On
// silence the helper reports zeros and the bars settle to a still baseline.
DashSurface {
    id: root
    property bool isOpen: false

    readonly property int barCount: AudioSpectrum.barCount

    fill: Qt.rgba(Theme.surfaceBase.r, Theme.surfaceBase.g, Theme.surfaceBase.b, 0.7)
    radius: 14
    implicitHeight: 84

    Component.onCompleted: AudioSpectrum.acquire()
    Component.onDestruction: AudioSpectrum.release()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: Theme.dashboardSpacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dashboardSpacingSm

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "equalizer"
                color: Theme.accentPrimary
                font.pixelSize: Theme.dashboardText(14)
            }

            Text {
                Layout.fillWidth: true
                text: "PIPEWIRE MONITOR"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: AudioSpectrum.streaming ? "48.0 kHz // s16le" : "stream idle"
                color: AudioSpectrum.streaming ? Theme.accentPrimary : Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 10
            color: Qt.rgba(Theme.surfaceDeep.r, Theme.surfaceDeep.g, Theme.surfaceDeep.b, 0.8)

            SpectrumBars {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                barCount: root.barCount
                levels: AudioSpectrum.levels
            }
        }
    }
}
