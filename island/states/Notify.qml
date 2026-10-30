// Island state: notify — toast (410×72) · expanded (420×140, on hover) · stack (430×98 when several are waiting)
// Real notifications from the D-Bus server in Island.qml. Everything shown comes from the
// notification itself (app name, summary, body, icon/image, actions, urgency, age) — nothing is hard-coded.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Notifications
import "PetSprites.js" as S
import "PetFx.js" as PetFx

Item {
    id: st
    required property var core
    readonly property string key: "notify"
    readonly property var queue: core.notifQueue
    readonly property var item: queue.length > 0 ? queue[0] : null
    readonly property var n: item ? item.n : null
    readonly property int count: queue.length
    readonly property bool expanded: core.hovered && n !== null
    readonly property bool stack: count > 1 && !expanded
    readonly property real w: expanded ? 420 : stack ? 430 : 410
    readonly property real h: expanded ? 140 : stack ? 98 : 72
    readonly property color tone: !n ? core.teal : n.urgency === NotificationUrgency.Critical ? core.coral : n.urgency === NotificationUrgency.Low ? core.dim : core.teal
    readonly property color accent: tone
    property double waveStart: -1
    property real wavedTs: -1
    readonly property bool petWaving: !expanded && item !== null && PetFx.waving(waveStart, core.petTick)
    readonly property string petPose: petWaving ? "wave" : "sit"
    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function maybeWave() {
        if (!visible || expanded || !item) return
        if (item.ts === wavedTs) return
        wavedTs = item.ts
        waveStart = core.petTick
    }
    onItemChanged: maybeWave()
    onVisibleChanged: if (!visible) waveStart = -1; else maybeWave()
    onExpandedChanged: if (!expanded) maybeWave()

    function acts(q) {
        const r = []
        if (!q || !q.n) return r
        const note = q.n
        for (let i = 0; i < note.actions.length; i++) if (note.actions[i].identifier !== "default") r.push(note.actions[i])
        return r.slice(0, 2)
    }
    function defaultAction(note) {
        if (!note) return null
        for (let i = 0; i < note.actions.length; i++) if (note.actions[i].identifier === "default") return note.actions[i]
        return null
    }
    function open(q) {                       // click on the card: run the app's default action if it has one
        if (!q) return
        const d = defaultAction(q.n)
        if (d) st.core.invokeAction(q, d); else st.core.dismissNotif(q)
    }
    function title(q) {
        if (!q) return ""
        if (q.entry && q.entry.summary) return q.entry.summary
        const note = q.n
        return note ? (note.summary !== "" ? note.summary : note.appName) : ""
    }
    function bodyText(q) {
        if (!q) return ""
        if (q.entry && q.entry.body !== undefined) return q.entry.body
        const note = q.n
        return note ? (note.body !== "" ? note.body : note.appName) : ""
    }
    function appNameText(q) {
        if (!q) return ""
        if (q.entry && q.entry.appName) return q.entry.appName
        return q.n ? q.n.appName : ""
    }

    // ── small local widgets ──
    component Txt: Text { color: st.core.text; font.family: st.core.uiFont; font.pixelSize: 13; elide: Text.ElideRight; textFormat: Text.PlainText }
    component Mono: Text { color: st.core.dim; font.family: st.core.monoFont; font.pixelSize: 10; elide: Text.ElideRight; textFormat: Text.PlainText }
    component Ico: Text {
        property string alt: ""
        property string name: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 17; color: st.core.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    component Avatar: Item {
        id: av
        property int size: 36
        property var item: null
        property var note: null
        property color tone: st.core.teal
        implicitWidth: size; implicitHeight: size
        readonly property string src: item ? st.core.iconSrc(item.entry, item.n) : (note ? st.core.iconSrc(null, note) : "")
        Rectangle { id: avMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        Rectangle {
            anchors.fill: parent; radius: width / 2; visible: img.status !== Image.Ready
            color: Qt.rgba(av.tone.r, av.tone.g, av.tone.b, 0.15); border.width: 1; border.color: Qt.rgba(av.tone.r, av.tone.g, av.tone.b, 0.35)
            Ico { anchors.centerIn: parent; name: "notifications"; alt: "!"; color: av.tone; font.pixelSize: Math.round(av.size * 0.5) }
        }
        Image {
            id: img
            anchors.fill: parent; visible: status === Image.Ready
            source: av.src; asynchronous: true; fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.min(128, Math.max(32, av.size * 2))
            sourceSize.height: Math.min(128, Math.max(32, av.size * 2))
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: avMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        }
    }
    component CloseBtn: Rectangle {
        signal clicked()
        implicitWidth: 28; implicitHeight: 28; radius: 14; color: cm.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on color { ColorAnimation { duration: 100 } }
        Ico { anchors.centerIn: parent; name: "close"; alt: "×"; font.pixelSize: 15; color: st.core.dim }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    component Pillbtn: Rectangle {
        id: pb
        property string text: ""
        property bool primary: false
        signal clicked()
        implicitHeight: 26; implicitWidth: pt.implicitWidth + 26; radius: 13
        color: primary ? st.tone : Qt.rgba(1, 1, 1, 0.08)
        scale: pm.containsMouse ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Mono { id: pt; anchors.centerIn: parent; text: pb.text.toUpperCase(); font.letterSpacing: 1; font.weight: Font.DemiBold; color: pb.primary ? "#000000" : st.core.text }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
    // Local pixel mascot; only the shared sprite data and island clock are reused.
    component PixelPet: Canvas {
        property string pose: st.petPose
        property int tick: st.visible && st.petWaving ? st.core.petTick : 0
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

    // ═══════════ stack (several waiting): peeking cards + front card ═══════════
    Item {
        anchors.fill: parent
        opacity: st.stack ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 5; width: parent.width - 44; height: 60; radius: 20; color: Qt.rgba(1, 1, 1, 0.035) }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 10; width: parent.width - 22; height: 64; radius: 21; color: Qt.rgba(1, 1, 1, 0.06) }
        Rectangle {
            id: front
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
            width: parent.width; height: 80; radius: 24; color: "#000000"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.09)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                PixelPet { Layout.alignment: Qt.AlignVCenter }
                Avatar { size: 36; item: st.item; note: st.n; tone: st.tone }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    RowLayout {
                        spacing: 8
                        Txt { text: st.title(st.item); font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Mono { text: st.item ? st.core.ago(st.item.ts) : "" }
                    }
                    Txt { text: st.bodyText(st.item); color: st.core.dim; font.pixelSize: 12; Layout.fillWidth: true }
                }
                Rectangle {
                    implicitHeight: 24; implicitWidth: br.implicitWidth + 20; radius: 12
                    color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.15); border.width: 1; border.color: Qt.rgba(st.tone.r, st.tone.g, st.tone.b, 0.3)
                    RowLayout { id: br; anchors.centerIn: parent; spacing: 5
                        Rectangle { width: 6; height: 6; radius: 3; color: st.tone
                            SequentialAnimation on opacity { loops: Animation.Infinite; running: st.stack
                                NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                        Mono { text: "+" + (st.count - 1); color: st.tone; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Mono { text: "MORE"; color: st.tone; font.pixelSize: 9; opacity: 0.7; font.letterSpacing: 1 } }
                }
            }
            MouseArea { anchors.fill: parent; anchors.rightMargin: 120; cursorShape: Qt.PointingHandCursor; onClicked: if (st.item) st.open(st.item) }
        }
    }

    // ═══════════ single toast (380×72) ═══════════
    Item {
        anchors.fill: parent
        opacity: !st.expanded && !st.stack ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (st.item) st.open(st.item) }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
            PixelPet { Layout.alignment: Qt.AlignVCenter }
            Avatar { size: 36; item: st.item; note: st.n; tone: st.tone }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    spacing: 8
                    Txt { text: st.title(st.item); font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Mono { text: st.item ? st.core.ago(st.item.ts) : ""; font.letterSpacing: 1 }
                }
                Txt { text: st.bodyText(st.item); color: st.core.dim; font.pixelSize: 12; Layout.fillWidth: true }
            }
            CloseBtn { onClicked: if (st.item) st.core.dismissNotif(st.item) }
        }
    }

    // ═══════════ expanded (420×140) ═══════════
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 6
        opacity: st.expanded ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Avatar { size: 28; item: st.item; note: st.n; tone: st.tone }
            Mono { text: st.appNameText(st.item).toUpperCase(); color: st.tone; font.weight: Font.DemiBold; font.letterSpacing: 1; Layout.fillWidth: true }
            Mono { text: st.count > 1 ? "1 / " + st.count : ""; visible: st.count > 1 }
            Mono { text: st.item ? st.core.ago(st.item.ts) + " ago" : "" }
        }
        Txt { text: st.title(st.item); font.weight: Font.DemiBold; Layout.fillWidth: true }
        Text {
            Layout.fillWidth: true; Layout.fillHeight: true
            textFormat: Text.PlainText
            text: st.bodyText(st.item); color: st.core.dim; font.family: st.core.uiFont; font.pixelSize: 12
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; verticalAlignment: Text.AlignTop
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Pillbtn { visible: st.count > 1; text: "Clear all"; onClicked: st.core.dismissAllNotifs() }
            Item { Layout.fillWidth: true }
            Pillbtn { text: "Dismiss"; onClicked: if (st.item) st.core.dismissNotif(st.item) }
            Repeater {
                model: st.expanded ? st.acts(st.item) : []
                delegate: Pillbtn {
                    required property var modelData
                    required property int index
                    text: modelData.text; primary: index === 0
                    onClicked: st.core.invokeAction(st.item, modelData)
                }
            }
        }
    }
}
