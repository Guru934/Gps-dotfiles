// Island state: music — compact (326×40) · deck (420×150, on hover) · lyrics (420×190) · paused look
// Everything is live: MPRIS title / artist / cover / position, PipeWire volume, spectrum from core,
// lyrics from the shared, cached LRCLIB provider. Hub-local playback is bridged
// across the Island process by MediaNowPlaying.
// Nothing is hard-coded; a field with no data hides. No "FLAC/96K" badge: MPRIS doesn't expose it.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import qs.config
import "PetSprites.js" as S

Item {
    id: st
    required property var core
    readonly property string key: "music"
    readonly property bool expanded: core.hovered
    property bool showLyrics: false
    readonly property bool lyricsView: expanded && showLyrics && core.lyricsEnabled
    readonly property real w: expanded ? 420 : 326
    readonly property real h: !expanded ? 40 : (lyricsView ? 190 : 150)
    readonly property color accent: core.playing ? core.lav : core.dim
    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)
    onExpandedChanged: if (!expanded) showLyrics = false

    // ───────────────── lyrics engine (LRCLIB) ─────────────────
    property var lines: []              // [{t: seconds, s: text}]
    property string plain: ""
    property string lstatus: "idle"     // idle · loading · synced · plain · none · error
    property string loadedKey: ""
    property int idx: -1
    readonly property string trackKey: core.artist + "|" + core.title + "|"
        + (core.player ? core.player.trackAlbum : "") + "|" + Math.round(core.length)
    readonly property bool want: lyricsView && core.hasMedia

    onWantChanged: { maybeFetch(); updateIdx() }
    onTrackKeyChanged: { lines = []; plain = ""; lstatus = "idle"; idx = -1; loadedKey = ""; maybeFetch() }

    function maybeFetch() {
        if (!want || loadedKey === trackKey) return
        const album = core.player ? core.player.trackAlbum : ""
        const key = MediaLyrics.keyFor(core.artist, core.title, album, core.length)
        loadedKey = trackKey
        if (core.title.trim() === "") { lstatus = "none"; return }
        if (MediaLyrics.resultKey === key) { syncLyrics(); return }
        lstatus = "loading"
        MediaLyrics.lookup(core.artist, core.title, album, core.length)
        syncLyrics()
    }
    function syncLyrics() {
        const album = core.player ? core.player.trackAlbum : ""
        const key = MediaLyrics.keyFor(core.artist, core.title, album, core.length)
        if (MediaLyrics.resultKey === key) {
            const result = MediaLyrics.result
            lines = result.status === "synced" ? result.lines : []
            plain = result.status === "plain" ? result.plain : ""
            lstatus = result.status
            updateIdx()
        } else if (MediaLyrics.errorKey === key) {
            lstatus = "error"
        } else if (MediaLyrics.loading && MediaLyrics.requestKey === key) {
            lstatus = "loading"
        }
    }
    function updateIdx() {
        if (lstatus !== "synced") { idx = -1; return }
        const p = core.position + 0.15
        let i = -1
        for (let k = 0; k < lines.length; k++) { if (lines[k].t <= p) i = k; else break }
        if (i !== idx) idx = i
    }
    Connections {
        target: MediaLyrics
        function onResultKeyChanged() { st.syncLyrics() }
        function onRequestKeyChanged() { st.syncLyrics() }
        function onErrorKeyChanged() { st.syncLyrics() }
        function onLoadingChanged() { st.syncLyrics() }
    }
    Timer {
        interval: 250; repeat: true
        running: st.want && st.core.playing && st.lstatus === "synced" && st.core.player !== null
        onTriggered: st.updateIdx()
    }

    readonly property string curText: lstatus === "synced" ? (idx >= 0 ? (lines[idx].s || "♪") : "♪")
                                    : lstatus === "plain" ? plain
                                    : lstatus === "loading" ? "Searching lyrics…"
                                    : lstatus === "none" ? "No lyrics found for this track"
                                    : lstatus === "error" ? "Lyrics unavailable (offline?)" : ""
    readonly property string nextText: lstatus === "synced" && idx + 1 < lines.length ? (lines[idx + 1].s || "♪") : ""
    readonly property string statusLabel: lstatus === "synced" ? "LRCLIB · SYNCED" : lstatus === "plain" ? "LRCLIB · NO TIMING"
                                        : lstatus === "loading" ? "SEARCHING…" : lstatus === "none" ? "NO LYRICS FOUND"
                                        : lstatus === "error" ? "OFFLINE" : ""

    // ───────────────── small local widgets ─────────────────
    component Txt: Text { color: st.core.text; font.family: st.core.uiFont; font.pixelSize: 13; elide: Text.ElideRight }
    component Mono: Text { color: st.core.dim; font.family: st.core.monoFont; font.pixelSize: 10; elide: Text.ElideRight }
    component Ico: Text {
        property string alt: ""
        property string name: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 17; color: st.core.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    component RoundBtn: Rectangle {
        id: rb
        property string name: ""
        property string alt: ""
        property bool primary: false
        property bool on: true
        property int size: 28
        signal clicked()
        implicitWidth: size; implicitHeight: size; radius: size / 2
        color: primary ? st.core.teal : Qt.rgba(1, 1, 1, 0.08)
        opacity: on ? (rbm.containsMouse ? 0.85 : 1) : 0.35
        scale: rbm.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Ico { anchors.centerIn: parent; name: rb.name; alt: rb.alt; font.pixelSize: Math.round(rb.size * 0.57); color: rb.primary ? "#00201c" : st.core.text }
        MouseArea { id: rbm; anchors.fill: parent; hoverEnabled: true; enabled: rb.on; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
    component Art: Item {
        id: art
        property int size: 28
        property bool gray: false
        implicitWidth: size; implicitHeight: size
        Rectangle { id: artMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        Rectangle {
            anchors.fill: parent; radius: width / 2; color: "#14171f"; visible: img.status !== Image.Ready
            Rectangle { anchors.centerIn: parent; width: art.size * 0.38; height: width; radius: width / 2; color: "#000000"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.35; height: width; radius: width / 2; color: st.core.teal } }
        }
        Image {
            id: img
            anchors.fill: parent; visible: status === Image.Ready
            source: st.core.artUrl; cache: false; asynchronous: true; fillMode: Image.PreserveAspectCrop
            sourceSize.width: art.size * 2; sourceSize.height: art.size * 2
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; saturation: art.gray ? -1.0 : 0.0 }
        }
    }
    // scrolls long titles; static when they fit
    component Marquee: Item {
        id: mq
        property string text: ""
        property color color: st.core.text
        property int px: 12
        property bool bold: true
        property bool run: true
        clip: true
        implicitHeight: t1.implicitHeight
        readonly property bool over: t1.implicitWidth > width
        onTextChanged: strip.x = 0
        onOverChanged: strip.x = 0
        Row {
            id: strip
            spacing: 32
            Text { id: t1; text: mq.text; color: mq.color; font.family: st.core.uiFont; font.pixelSize: mq.px; font.weight: mq.bold ? Font.DemiBold : Font.Normal }
            Text { visible: mq.over; text: mq.text; color: mq.color; font.family: st.core.uiFont; font.pixelSize: mq.px; font.weight: mq.bold ? Font.DemiBold : Font.Normal }
        }
        NumberAnimation {
            target: strip; property: "x"; from: 0; to: -(t1.implicitWidth + 32)
            duration: Math.max(5000, (t1.implicitWidth + 32) * 26); loops: Animation.Infinite
            running: mq.over && mq.run && st.visible
            onRunningChanged: if (!running) strip.x = 0
        }
    }
    // five little bars: real spectrum while playing, flat dots when paused
    component Bars: Row {
        property var picks: [0, 2, 4, 5, 7]
        spacing: 2.5; height: 18
        Repeater {
            model: 5
            delegate: Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 2; radius: 1
                height: st.core.playing ? 4 + (st.core.bars[parent.picks[index]] || 0) / 100 * 14 : 2
                color: st.core.playing ? st.core.teal : st.core.dim
                Behavior on height { NumberAnimation { duration: 90 } }
            }
        }
    }
    // Local pixel mascot; only the shared sprite data and island clock are reused.
    component PixelPet: Canvas {
        property string pose: "sit"
        property int tick: st.visible && !st.expanded && st.core.playing ? st.core.petTick : 0
        readonly property string skin: st.core.petSkin
        implicitWidth: S.W + 2
        implicitHeight: S.H + 2
        antialiasing: false
        Component.onCompleted: requestPaint()
        onPoseChanged: requestPaint()
        onTickChanged: requestPaint()
        onSkinChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: S.draw(getContext("2d"), skin, pose, tick, 1, false, false)
    }

    // ═══════════════ 1 · compact / paused (326×40) ═══════════════
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12
        spacing: 10
        opacity: !st.expanded ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Art { size: 28; gray: !st.core.playing; Layout.alignment: Qt.AlignVCenter }
        PixelPet {
            pose: st.core.playing ? "groove" : "sit"
            tick: st.visible && !st.expanded && st.core.playing ? st.core.petTick : 0
            Layout.alignment: Qt.AlignVCenter
        }
        Marquee {
            Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
            text: st.core.playing ? st.core.title : st.core.title + "  [paused]"
            color: st.core.playing ? st.core.text : Qt.rgba(st.core.text.r, st.core.text.g, st.core.text.b, 0.6)
            bold: st.core.playing; run: st.core.playing
        }
        Bars { Layout.alignment: Qt.AlignVCenter }
        RoundBtn {
            visible: !st.core.playing; size: 22; Layout.alignment: Qt.AlignVCenter
            name: "play_arrow"; alt: "▶"; on: st.core.player !== null && st.core.player.canTogglePlaying
            onClicked: st.core.player.togglePlaying()
        }
    }

    // ═══════════════ 2 · deck (420×150) ═══════════════
    RowLayout {
        anchors.fill: parent; anchors.margins: 14; spacing: 16
        opacity: st.expanded && !st.lyricsView ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Item {
            Layout.preferredWidth: 100; Layout.preferredHeight: 100; Layout.alignment: Qt.AlignVCenter
            Item {
                anchors.fill: parent
                RotationAnimator on rotation { from: 0; to: 360; duration: 14000; loops: Animation.Infinite; running: st.core.playing && st.expanded && st.visible }
                Shape {
                    anchors.fill: parent; layer.enabled: true; layer.samples: 4
                    ShapePath {
                        strokeColor: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.65); strokeWidth: 1
                        fillColor: "transparent"; strokeStyle: ShapePath.DashLine; dashPattern: [8, 6]
                        PathAngleArc { centerX: 50; centerY: 50; radiusX: 47; radiusY: 47; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Rectangle { x: 47.5; y: 0.5; width: 5; height: 5; radius: 2.5; color: st.core.teal }
                Rectangle { x: 48.5; y: 94.5; width: 3; height: 3; radius: 1.5; color: st.core.amber }
            }
            Art { anchors.centerIn: parent; size: 84; gray: !st.core.playing }
            Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: "#000000"
                Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.35) } }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 3
            Marquee { Layout.fillWidth: true; text: st.core.title; px: 15; run: st.core.playing && st.visible }
            Txt { visible: st.core.artist !== ""; text: st.core.artist; color: st.core.dim; font.pixelSize: 12; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3; visible: st.core.length > 0
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 10
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.1)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, st.core.length > 0 ? st.core.position / st.core.length : 0)); height: parent.height; radius: 2
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: st.core.teal } GradientStop { position: 1; color: st.core.lav } }
                        } }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        enabled: st.core.player !== null && st.core.player.canSeek
                        onClicked: m => {
                            const target = (m.x / width) * st.core.length
                            if (typeof st.core.player.seekTo === "function")
                                st.core.player.seekTo(target)
                            else
                                st.core.player.position = target
                        }
                    }
                }
                RowLayout { Layout.fillWidth: true
                    Mono { text: st.core.fmt(st.core.position); color: st.core.text }
                    Item { Layout.fillWidth: true }
                    Mono { text: st.core.fmt(st.core.length) } }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                RoundBtn { name: "skip_previous"; alt: "◀◀"; on: st.core.player !== null && st.core.player.canGoPrevious; onClicked: st.core.player.previous() }
                RoundBtn { primary: true; size: 32; name: st.core.playing ? "pause" : "play_arrow"; alt: st.core.playing ? "II" : "▶"; on: st.core.player !== null && st.core.player.canTogglePlaying; onClicked: st.core.player.togglePlaying() }
                RoundBtn { name: "skip_next"; alt: "▶▶"; on: st.core.player !== null && st.core.player.canGoNext; onClicked: st.core.player.next() }
                Item { Layout.fillWidth: true }
                RoundBtn { visible: st.core.lyricsEnabled; size: 26; name: "lyrics"; alt: "♫"; onClicked: st.showLyrics = true }
                Rectangle {
                    visible: st.core.sinkAudio !== null
                    implicitHeight: 26; implicitWidth: vr.implicitWidth + 18; radius: 13; color: Qt.rgba(1, 1, 1, 0.08)
                    RowLayout { id: vr; anchors.centerIn: parent; spacing: 5
                        Ico { name: st.core.volIcon(); alt: st.core.muted ? "×" : "♪"; font.pixelSize: 14; color: st.core.dim }
                        Mono { text: st.core.muted ? "MUTE" : Math.round(st.core.volume * 100) + "%"; font.pixelSize: 10; font.weight: Font.DemiBold } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (st.core.sinkAudio) st.core.sinkAudio.muted = !st.core.sinkAudio.muted } }
                }
            }
        }
    }

    // ═══════════════ 3 · lyrics (420×190) ═══════════════
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 6
        opacity: st.lyricsView ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Art { size: 32; gray: !st.core.playing }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Txt { text: st.core.title; font.weight: Font.Bold; Layout.fillWidth: true }
                Mono { text: st.core.fmt(st.core.position) + " / " + st.core.fmt(st.core.length); visible: st.core.length > 0 }
            }
            RowLayout {
                spacing: 6
                RoundBtn { size: 24; name: "skip_previous"; alt: "◀◀"; on: st.core.player !== null && st.core.player.canGoPrevious; onClicked: st.core.player.previous() }
                RoundBtn { size: 24; primary: true; name: st.core.playing ? "pause" : "play_arrow"; alt: st.core.playing ? "II" : "▶"; on: st.core.player !== null && st.core.player.canTogglePlaying; onClicked: st.core.player.togglePlaying() }
                RoundBtn { size: 24; name: "skip_next"; alt: "▶▶"; on: st.core.player !== null && st.core.player.canGoNext; onClicked: st.core.player.next() }
            }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            Flickable {
                anchors.fill: parent
                visible: st.lstatus === "plain"
                contentWidth: width
                contentHeight: plainLyrics.implicitHeight
                clip: true
                Text {
                    id: plainLyrics
                    width: parent.width
                    text: st.plain
                    color: st.core.dim
                    font.family: st.core.uiFont
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            ColumnLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                visible: st.lstatus !== "plain"
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 5; width: 6; height: 6; radius: 3; color: st.core.teal
                        SequentialAnimation on opacity { loops: Animation.Infinite; running: st.lyricsView && st.core.playing
                            NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                    Text {
                        id: curLine
                        Layout.fillWidth: true; text: st.curText; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        color: st.lstatus === "synced" ? st.core.teal : st.core.dim
                        font.family: st.core.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold
                        onTextChanged: curFade.restart()
                        NumberAnimation { id: curFade; target: curLine; property: "opacity"; from: 0.15; to: 1; duration: 260 }
                    }
                }
                Txt { Layout.fillWidth: true; Layout.leftMargin: 14; text: st.nextText; visible: st.nextText !== ""; color: st.core.dim; opacity: 0.6; font.pixelSize: 11 }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Rectangle {
                visible: st.statusLabel !== ""
                implicitHeight: 20; implicitWidth: sr.implicitWidth + 18; radius: 10; color: Qt.rgba(1, 1, 1, 0.07)
                RowLayout { id: sr; anchors.centerIn: parent; spacing: 6
                    Rectangle { width: 6; height: 6; radius: 3; color: st.lstatus === "synced" ? st.core.teal : st.lstatus === "error" ? st.core.coral : st.core.amber }
                    Mono { text: st.statusLabel; font.letterSpacing: 1; font.weight: Font.DemiBold; font.pixelSize: 9 } }
            }
            Item { Layout.fillWidth: true }
            Mono { visible: st.lstatus === "synced" && st.idx >= 0; text: (st.idx + 1) + " / " + st.lines.length }
            RoundBtn { size: 22; name: "keyboard_arrow_up"; alt: "▲"; onClicked: st.showLyrics = false }
        }
    }
}
