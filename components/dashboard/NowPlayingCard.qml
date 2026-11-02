import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.config
import qs.components.dashboard

// "Now playing" card driven by the native MPRIS service. Shows the active
// player (the playing one wins, otherwise the first), real metadata and
// working transport controls gated by the player's advertised capabilities.
// When no player is present it renders an intentional idle state.
DashSurface {
    id: root
    property bool isOpen: false

    readonly property var player: MediaNowPlaying.player
    readonly property bool hasPlayer: root.player !== null
    readonly property bool hasProgress: root.hasPlayer
        && root.player.positionSupported && root.player.lengthSupported
        && root.player.length > 0
    readonly property real progressFraction: root.hasProgress
        ? Math.max(0, Math.min(1, root.displayPos / (root.player.length * 1000)))
        : 0

    // Playback position: anchored to the player's real samples (seconds on the
    // wire, converted to ms here), interpolated locally while playing so the
    // bar advances smoothly between updates.
    property real posBase: 0
    property real posStamp: 0
    property real tickNow: 0
    function syncPos() {
        if (root.player) {
            root.posBase = root.player.position * 1000
            root.posStamp = Date.now()
            root.tickNow = Date.now()
        }
    }
    onPlayerChanged: root.syncPos()
    readonly property real displayPos: {
        if (!root.hasPlayer || !root.player.positionSupported) return 0
        if (!root.player.isPlaying) return Math.max(0, root.player.position * 1000)
        let pos = root.posBase + Math.max(0, root.tickNow - root.posStamp)
        if (root.player.length > 0) pos = Math.min(pos, root.player.length * 1000)
        return Math.max(pos, root.player.position * 1000)
    }
    function fmt(ms) {
        const total = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const ss = (s < 10 ? "0" : "") + s
        return h > 0 ? (h + ":" + (m < 10 ? "0" : "") + m + ":" + ss) : (m + ":" + ss)
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.syncPos() }
        function onTrackTitleChanged() { root.syncPos() }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.isOpen && root.hasPlayer && root.player.isPlaying
        onTriggered: root.tickNow = Date.now()
    }

    // Compact round transport button used by the control row.
    component TransportButton: Item {
        id: tb
        property string icon: ""
        property bool interactable: false
        property bool highlight: false

        signal triggered()

        implicitWidth: tb.highlight ? 36 : 32
        implicitHeight: tb.highlight ? 36 : 32

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: tb.highlight
                ? Theme.accentPrimary
                : (tb.interactable && tbh.hovered ? Theme.surfaceVariant
                    : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.55))
            opacity: tb.highlight && !tb.interactable ? 0.35 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        DashIcon {
            anchors.centerIn: parent
            name: tb.icon
            color: tb.highlight ? Theme.onAccent : (tb.interactable ? Theme.textMain : Theme.textDim)
            opacity: tb.interactable || tb.highlight ? 1 : 0.4
            font.pixelSize: tb.highlight ? 20 : 17
        }

        HoverHandler { id: tbh; enabled: tb.interactable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: tb.interactable; onTapped: tb.triggered() }
    }

    fill: Qt.rgba(Theme.surfaceHigh.r, Theme.surfaceHigh.g, Theme.surfaceHigh.b, 0.7)
    radius: 14
    implicitHeight: root.hasPlayer ? 186 : 84

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: Theme.dashboardSpacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dashboardSpacingSm

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "podcasts"
                color: Theme.accentSecondary
                font.pixelSize: Theme.dashboardText(14)
            }

            Text {
                Layout.fillWidth: true
                text: "MPRIS // " + (root.hasPlayer
                    ? (root.player.isPlaying ? "PLAYING" : (root.player.playbackState === MprisPlaybackState.Paused ? "PAUSED" : "STOPPED"))
                    : "IDLE")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                font.bold: true
                font.letterSpacing: 0.8
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasPlayer
                text: root.hasPlayer ? root.player.identity : ""
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.dashboardText(8)
                elide: Text.ElideRight
                Layout.maximumWidth: 140
            }
        }

        // Idle state: no player at all.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: Theme.dashboardSpacingMd
            visible: !root.hasPlayer

            DashIcon {
                Layout.alignment: Qt.AlignVCenter
                name: "music_off"
                color: Theme.surfaceVariant
                font.pixelSize: Theme.dashboardText(26)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    text: "NO ACTIVE PLAYER"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(10)
                    font.bold: true
                    font.letterSpacing: 1
                }

                Text {
                    text: "playback controls appear here when a player connects"
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                }
            }
        }

        // Active player: artwork + metadata.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dashboardSpacingMd
            visible: root.hasPlayer

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 64
                implicitHeight: 64

                CircularArtwork {
                    id: disc
                    anchors.fill: parent
                    diameter: 64
                    artUrl: root.hasPlayer ? root.player.trackArtUrl : ""
                    orbiting: root.isOpen && root.hasPlayer && root.player.isPlaying
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: root.hasPlayer && root.player.trackTitle.length > 0 ? root.player.trackTitle : "Unknown title"
                    color: Theme.textMain
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.dashboardText(13)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hasPlayer
                        ? (root.player.trackArtist.length > 0 ? root.player.trackArtist : (root.player.trackAlbum.length > 0 ? root.player.trackAlbum : "\u2014"))
                        : ""
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(9)
                    elide: Text.ElideRight
                }
            }
        }

        // Progress scrubber (display only; seeking is not offered).
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            visible: root.hasProgress

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.4)

                Rectangle {
                    width: parent.width * root.progressFraction
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accentPrimary }
                        GradientStop { position: 1; color: Theme.accentSecondary }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.fmt(root.displayPos)
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.fmt(root.player ? root.player.length * 1000 : 0)
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.dashboardText(8)
                }
            }
        }

        // Transport controls, gated on advertised capabilities.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: Theme.dashboardSpacingSm
            visible: root.hasPlayer

            TransportButton {
                icon: "skip_previous"
                interactable: root.hasPlayer && root.player.canGoPrevious
                onTriggered: root.player.previous()
            }

            TransportButton {
                icon: root.hasPlayer && root.player.isPlaying ? "pause" : "play_arrow"
                highlight: true
                interactable: root.hasPlayer && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
                onTriggered: {
                    if (root.player.canTogglePlaying) root.player.togglePlaying()
                    else if (root.player.isPlaying && root.player.canPause) root.player.pause()
                    else if (!root.player.isPlaying && root.player.canPlay) root.player.play()
                }
            }

            TransportButton {
                icon: "skip_next"
                interactable: root.hasPlayer && root.player.canGoNext
                onTriggered: root.player.next()
            }
        }
    }
}
