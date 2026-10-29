// ============================================================================
//  Toolbox.qml  —  GPS Toolbox (standalone, self-contained Quickshell/QML item)
//
//  Qt 6.x / QtQuick + QtQuick.Controls (ScrollBar only) + QtQuick.Layouts.
//  No Quickshell imports, no processes, no network, no external assets.
//
//  WHAT THIS IS
//    A UI/interaction prototype. Local operations (create/edit/delete saved
//    items, collections, automations, routines, presets, search, filters,
//    toasts, dialogs) work in memory. Anything that would touch the real
//    system (run an action, open a URL, talk to a phone, create a timer) is
//    only *requested* through a signal and the UI says so honestly.
//    Nothing here claims a device is connected or a schedule is running.
//
//  PUBLIC INTERFACE (all optional — the UI renders with the defaults)
//    Status in : hostName, osName, compositorName, compositorState,
//                integrationAvailable, availableActionIds, supportedTriggers,
//                devices, sharedLinks, activityEvents, nextRunSummary
//    Data in/out (in-memory defaults, replace/observe from a backend):
//                savedItems, collections, automations, actionsData, routines,
//                presets, settings
//    Behaviour : showSampleData, reduceMotion, allowDirectUrlOpen
//    Signals   : openUrlRequested, savedItemSaved, savedItemDeleted,
//                actionRunRequested, automationSaved, automationDeleted,
//                automationStateChangeRequested, automationTestRequested,
//                scheduleCancelRequested, workflowSaved, workflowRunRequested,
//                presetActivateRequested, deviceActionRequested,
//                sharedLinkDismissed
//
//    devices item      : { id, name, state: "connected"|"disconnected"|
//                          "pairing"|"unavailable", battery: -1|0..100,
//                          lastSeen: "", capabilities: ["mirror","file",...] }
//    sharedLinks item  : { id, title, url, source, received }
//    activityEvents    : { id, ts (ms epoch or ISO), name, trigger, result:
//                          "completed"|"failed"|"cancelled"|"review",
//                          duration, category, automation, details }
//
//  Icons are plain Unicode glyphs (no icon pack). Swap them in one place:
//  the `navItems` array and the literal glyph strings passed to `icon:`.
//  Fonts: "Plus Jakarta Sans" / "JetBrains Mono" with automatic fallback.
// ============================================================================
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    implicitWidth: 1280
    implicitHeight: 800
    clip: true

    // ======================= PUBLIC API =====================================
    property string hostName: ""
    property string osName: ""
    property string compositorName: ""
    property string compositorState: "unknown"      // connected | disconnected | unknown
    property bool integrationAvailable: false
    property var availableActionIds: []
    property var supportedTriggers: ["manual", "once", "schedule", "delay"]
    property var devices: []
    property var sharedLinks: []
    property var activityEvents: []
    property string nextRunSummary: ""
    property bool showSampleData: true
    property bool reduceMotion: false
    property bool allowDirectUrlOpen: false
    property bool showCloseButton: false

    property var collections: ["Development", "Python Learning", "AI Tools", "Linux", "Websites", "Personal"]
    property var savedItems: sampleSavedItems()
    property var automations: sampleAutomations()
    property var actionsData: sampleActions()
    property var routines: sampleRoutines()
    property var presets: samplePresets()
    property var settings: ({ defaultCollection: "", defaultDir: "", scriptsDir: "", toasts: true,
                              confirmDelete: true, confirmRun: true, showDeviceChip: true,
                              retention: 30, reduceMotion: false })

    signal openUrlRequested(string url)
    signal savedItemSaved(var item)
    signal savedItemDeleted(string id)
    signal actionRunRequested(string actionId, var params)
    signal automationSaved(var automation)
    signal automationDeleted(string id)
    signal automationStateChangeRequested(string id, bool enabled)
    signal automationTestRequested(string id)
    signal scheduleCancelRequested(string id)
    signal workflowSaved(var routine)
    signal workflowRunRequested(string id)
    signal presetActivateRequested(string id)
    signal deviceActionRequested(string deviceId, string action, var params)
    signal sharedLinkDismissed(string id)
    signal closeRequested()

    // ======================= INTERNAL STATE =================================
    property int pageIndex: 0
    property int _seq: 1000
    property int unread: 0
    property var notifications: []
    property bool notifOpen: false
    property bool searchOpen: false
    readonly property var searchResults: searchAll(globalSearch.text)
    readonly property int animMs: (reduceMotion || settings.reduceMotion) ? 0 : 180
    readonly property bool compactNav: width < 980
    readonly property int navW: compactNav ? 60 : 212

    // saved space
    property string savedQuery: ""
    property string savedType: "all"
    property string savedColl: ""
    property string savedSort: "recent"
    property string capType: "bookmark"
    property string capEditId: ""
    property string capColl: ""
    property string capTrust: "needs-review"
    property bool capBadTitle: false
    property bool capBadContent: false
    property string capContentMsg: ""
    property string collMode: "new"
    property string collOld: ""
    property string collErr: ""

    // automations
    property string autoFilter: "all"
    property var expandedAuto: ({})
    property int wizStep: 0
    property var wiz: blankAuto()
    property string wizMsg: ""

    // actions
    property string actQuery: ""
    property string actCat: "All"
    property string inspId: ""
    property string actEditId: ""
    property string aeCat: "Custom Actions"
    property string aeTrust: "needs-review"
    property bool aeConfirm: true
    property string aeMsg: ""

    // routines
    property string rtSelId: "rt1"
    property var stepOpen: ({})
    property bool stepAddOpen: false

    // devices / presets / history
    property bool previewDevices: false
    property string devSel: ""
    property var dismissedLinks: []
    property string presetSel: ""
    property string presetEditId: ""
    property bool peDnd: false
    property string peTimer: "none"
    property bool previewActivity: false
    property string histStatus: "all"
    property string histRange: "any"
    property string histCat: "All"
    property string histAuto: "All"
    property var expandedEvt: ({})

    // dialogs
    property string cfTitle: ""
    property string cfMsg: ""
    property string cfLabel: "Confirm"
    property bool cfDanger: true
    property var cfFn: null
    property string pvTitle: ""
    property var pvSteps: []
    property string pvNote: ""
    property string pvId: ""
    property bool pvAllow: true

    readonly property var navItems: [
        { label: "Home", icon: "⌂" }, { label: "Saved Space", icon: "▤" },
        { label: "Automations", icon: "◔" }, { label: "Action Library", icon: "⌘" },
        { label: "Routine Builder", icon: "⎇" }, { label: "Device Bridge", icon: "▯" },
        { label: "Workspace Presets", icon: "▦" }, { label: "Activity & History", icon: "↺" }]
    readonly property var actionCategories: ["Desktop", "Applications", "Audio", "Display", "Network",
        "Development", "Media", "Phone & Devices", "Power", "Custom Actions"]
    readonly property var triggerTypes: [
        { k: "once", l: "One-time" }, { k: "schedule", l: "Daily / weekly" }, { k: "delay", l: "Delay" },
        { k: "manual", l: "Manual" }, { k: "battery", l: "Battery threshold" },
        { k: "device", l: "Device connection" }, { k: "event", l: "System event" }]
    readonly property var quickActions: [
        { k: "action", id: "lock_screen", icon: "⚿", name: "Lock Screen" },
        { k: "action", id: "open_terminal", icon: ">_", name: "Open Terminal" },
        { k: "action", id: "open_dev_ws", icon: "{ }", name: "Open Development Workspace" },
        { k: "action", id: "focus_start", icon: "◎", name: "Start Focus Session" },
        { k: "action", id: "scrcpy_launch", icon: "▭", name: "Launch scrcpy" },
        { k: "nav", target: 1, icon: "▤", name: "Open Saved Space" },
        { k: "action", id: "audio_controls", icon: "♪", name: "Audio Controls" },
        { k: "nav", target: 4, icon: "✚", name: "New Workflow", create: true }]
    readonly property var pageComps: [homePage, savedPage, autoPage, actionPage, routinePage, devicePage, presetPage, historyPage]

    ThemeData { id: th }
    ListModel { id: toastModel }
    TextEdit { id: clipHelper; visible: false }

    // ======================= INLINE COMPONENTS ==============================
    component ThemeData: QtObject {
        readonly property color bg: "#0f131c"
        readonly property color well: "#0a0e17"
        readonly property color panel: "#181b25"
        readonly property color panelHi: "#1c2029"
        readonly property color raised: "#262a34"
        readonly property color raisedHi: "#31353f"
        readonly property color line: "#2a2e3a"
        readonly property color text: "#dfe2ef"
        readonly property color dim: "#cac4d4"
        readonly property color mute: "#948e9d"
        readonly property color violet: "#a78bfa"
        readonly property color lilac: "#cebdff"
        readonly property color inkViolet: "#2a0f6b"
        readonly property color cyan: "#7bd0ff"
        readonly property color teal: "#3cddc7"
        readonly property color red: "#ffb4ab"
        readonly property color redDeep: "#93000a"
        readonly property color amber: "#f2c26b"
        readonly property string sans: "Plus Jakarta Sans"
        readonly property string mono: "JetBrains Mono"
        function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }
    }
    component Lbl: Text {
        color: "#dfe2ef"; font.family: "Plus Jakarta Sans"; font.pixelSize: 13
        elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
    }
    component Mono: Lbl { font.family: "JetBrains Mono"; font.pixelSize: 11 }
    component Cap: Mono { font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.8; color: "#948e9d" }
    component Txt: Lbl { Layout.fillWidth: true }
    component Wrap: Lbl { Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: "#cac4d4"; font.pixelSize: 12 }
    component Spacer: Item { Layout.fillWidth: true }
    component Rule: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#2a2e3a" }

    component Btn: Rectangle {
        id: b
        property string text: ""
        property string icon: ""
        property string kind: "soft"          // primary | soft | ghost | danger | cyan
        property bool compact: false
        property bool active: false
        property color tint: "transparent"
        signal clicked()
        readonly property ThemeData t: ThemeData {}
        readonly property bool hot: ma.containsMouse
        readonly property color fg: tint.a > 0 ? tint
            : kind === "primary" ? t.inkViolet : kind === "cyan" ? "#00354a"
            : kind === "danger" ? "#ffdad6" : (kind === "ghost" && !hot && !active) ? t.dim : t.text
        implicitHeight: compact ? 26 : 32
        implicitWidth: rw.implicitWidth + (compact ? 14 : 22)
        radius: 8
        opacity: enabled ? 1 : 0.4
        scale: ma.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 70 } }
        Behavior on color { ColorAnimation { duration: 90 } }
        color: kind === "primary" ? (hot ? Qt.lighter(t.violet, 1.12) : t.violet)
             : kind === "cyan" ? (hot ? Qt.lighter(t.cyan, 1.1) : t.cyan)
             : kind === "danger" ? t.a(t.redDeep, hot ? 0.9 : 0.6)
             : kind === "ghost" ? t.a(t.raised, (hot || active) ? 1 : 0)
             : (hot ? t.raisedHi : t.raised)
        Row {
            id: rw; anchors.centerIn: parent; spacing: 6
            Lbl { visible: b.icon !== ""; text: b.icon; color: b.fg; font.pixelSize: b.compact ? 12 : 14 }
            Lbl { visible: b.text !== ""; text: b.text; color: b.fg; font.pixelSize: b.compact ? 11 : 12; font.weight: Font.DemiBold }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    component Pill: Rectangle {
        id: p
        property string text: ""
        property string icon: ""
        property int count: -1
        property bool active: false
        property color tone: "#cebdff"
        signal clicked()
        implicitHeight: 28
        implicitWidth: pr.implicitWidth + 24
        radius: 14
        opacity: enabled ? 1 : 0.45
        color: active ? Qt.rgba(tone.r, tone.g, tone.b, 0.16) : (pma.containsMouse ? "#1c2029" : "transparent")
        border.width: 1
        border.color: active ? Qt.rgba(tone.r, tone.g, tone.b, 0.55) : "#2a2e3a"
        Behavior on color { ColorAnimation { duration: 90 } }
        Row {
            id: pr; anchors.centerIn: parent; spacing: 6
            Lbl { visible: p.icon !== ""; text: p.icon; color: p.active ? p.tone : "#948e9d"; font.pixelSize: 12 }
            Lbl { text: p.text; color: p.active ? p.tone : "#cac4d4"; font.pixelSize: 12; font.weight: p.active ? Font.DemiBold : Font.Normal }
            Mono { visible: p.count >= 0; text: p.count; color: p.active ? p.tone : "#948e9d"; font.pixelSize: 10 }
        }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.clicked() }
    }

    component Chip: Rectangle {
        id: c
        property string text: ""
        property color tone: "#948e9d"
        property bool dot: false
        implicitHeight: 20
        implicitWidth: cr.implicitWidth + 14
        radius: 10
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.14)
        Row {
            id: cr; anchors.centerIn: parent; spacing: 5
            Rectangle { visible: c.dot; width: 6; height: 6; radius: 3; color: c.tone; anchors.verticalCenter: parent.verticalCenter }
            Mono { text: c.text; color: c.tone; font.pixelSize: 10; font.bold: true }
        }
    }

    component Card: Rectangle {
        id: cd
        property int pad: 14
        property int gap: 10
        default property alias content: col.data
        implicitHeight: col.implicitHeight + 2 * pad
        radius: 12; color: "#181b25"; border.width: 1; border.color: "#252936"
        ColumnLayout { id: col; x: cd.pad; y: cd.pad; width: cd.width - 2 * cd.pad; spacing: cd.gap }
    }

    component Field: Rectangle {
        id: f
        property alias text: ti.text
        property alias input: ti
        property string placeholder: ""
        property string icon: ""
        property bool mono: false
        property bool invalid: false
        signal accepted()
        readonly property ThemeData t: ThemeData {}
        Layout.fillWidth: true
        implicitHeight: 34; radius: 8; color: t.well
        border.width: 1
        border.color: invalid ? t.red : (ti.activeFocus ? t.cyan : t.line)
        Behavior on border.color { ColorAnimation { duration: 100 } }
        Lbl { visible: f.icon !== ""; text: f.icon; color: f.t.mute; x: 10; anchors.verticalCenter: parent.verticalCenter }
        TextInput {
            id: ti
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: f.icon !== "" ? 30 : 10; rightMargin: 10 }
            color: f.t.text; clip: true; selectByMouse: true
            font.family: f.mono ? f.t.mono : f.t.sans; font.pixelSize: f.mono ? 12 : 13
            selectionColor: f.t.violet; selectedTextColor: f.t.inkViolet
            onAccepted: f.accepted()
        }
        Lbl {
            visible: ti.text === ""; text: f.placeholder; color: f.t.mute; opacity: 0.7
            font.family: f.mono ? f.t.mono : f.t.sans; font.pixelSize: f.mono ? 12 : 13
            anchors { left: ti.left; right: ti.right; verticalCenter: parent.verticalCenter }
        }
    }

    component Area: Rectangle {
        id: a
        property alias text: te.text
        property string placeholder: ""
        property bool mono: false
        property bool invalid: false
        readonly property ThemeData t: ThemeData {}
        Layout.fillWidth: true
        implicitHeight: 84; radius: 8; color: t.well
        border.width: 1; border.color: invalid ? t.red : (te.activeFocus ? t.cyan : t.line)
        Flickable {
            id: fl
            anchors { fill: parent; margins: 8 }
            clip: true; contentWidth: width; contentHeight: te.paintedHeight + 4
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: te
                width: fl.width; wrapMode: TextEdit.Wrap; color: a.t.text; selectByMouse: true
                font.family: a.mono ? a.t.mono : a.t.sans; font.pixelSize: a.mono ? 12 : 13
                selectionColor: a.t.violet; selectedTextColor: a.t.inkViolet
                onCursorRectangleChanged: {
                    if (fl.contentY > cursorRectangle.y) fl.contentY = cursorRectangle.y
                    else if (fl.contentY + fl.height < cursorRectangle.y + cursorRectangle.height)
                        fl.contentY = cursorRectangle.y + cursorRectangle.height - fl.height
                }
            }
        }
        Lbl {
            visible: te.text === ""; text: a.placeholder; color: a.t.mute; opacity: 0.7
            x: 8; y: 8; width: parent.width - 16
            font.family: a.mono ? a.t.mono : a.t.sans; font.pixelSize: a.mono ? 12 : 13
        }
    }

    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled(bool value)
        readonly property ThemeData t: ThemeData {}
        implicitWidth: 36; implicitHeight: 20; radius: 10
        opacity: enabled ? 1 : 0.4
        color: checked ? t.violet : t.raisedHi
        Behavior on color { ColorAnimation { duration: 110 } }
        Rectangle {
            width: 16; height: 16; radius: 8; y: 2; x: tg.checked ? 18 : 2
            color: tg.checked ? tg.t.inkViolet : tg.t.dim
            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.checked) }
    }

    component Check: Item {
        id: ck
        property bool checked: false
        property string text: ""
        property string sub: ""
        signal toggled(bool value)
        readonly property ThemeData t: ThemeData {}
        Layout.fillWidth: true
        implicitHeight: Math.max(22, lc.implicitHeight)
        opacity: enabled ? 1 : 0.5
        Rectangle {
            id: bx; width: 18; height: 18; radius: 5; y: 2
            color: ck.checked ? ck.t.violet : ck.t.well
            border.width: 1; border.color: ck.checked ? ck.t.violet : ck.t.mute
            Lbl { anchors.centerIn: parent; visible: ck.checked; text: "✓"; color: ck.t.inkViolet; font.pixelSize: 12; font.bold: true }
        }
        ColumnLayout {
            id: lc
            anchors { left: bx.right; leftMargin: 10; right: parent.right; top: parent.top }
            spacing: 1
            Wrap { text: ck.text; color: ck.t.text; font.pixelSize: 13 }
            Wrap { visible: ck.sub !== ""; text: ck.sub; color: ck.t.mute; font.pixelSize: 11 }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ck.toggled(!ck.checked) }
    }

    component PageScroll: Flickable {
        id: pg
        property int pad: 22
        default property alias content: col.data
        clip: true; boundsBehavior: Flickable.StopAtBounds
        contentWidth: width; contentHeight: col.implicitHeight + 2 * pad
        ScrollBar.vertical: ScrollBar {
            id: sb; policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: "#3a3f4d"; opacity: sb.pressed || sb.hovered ? 1 : 0.7 }
            background: Item {}
        }
        ColumnLayout { id: col; x: pg.pad; y: pg.pad; width: pg.width - 2 * pg.pad; spacing: 14 }
    }

    component PageHead: RowLayout {
        id: ph
        property string caps: ""
        property string title: ""
        property string desc: ""
        default property alias actions: act.data
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true; spacing: 3
            Cap { text: ph.caps; color: "#7bd0ff"; Layout.fillWidth: true }
            Lbl { text: ph.title; font.pixelSize: 26; font.weight: Font.Bold; Layout.fillWidth: true }
            Wrap { text: ph.desc }
        }
        RowLayout { id: act; spacing: 8; Layout.alignment: Qt.AlignTop }
    }

    component SecTitle: RowLayout {
        id: st
        property string text: ""
        property string icon: ""
        property color tone: "#cebdff"
        default property alias rightSide: rr.data
        Layout.fillWidth: true
        spacing: 8
        Lbl { visible: st.icon !== ""; text: st.icon; color: st.tone; font.pixelSize: 15 }
        Lbl { text: st.text; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
        RowLayout { id: rr; spacing: 6 }
    }

    component Empty: ColumnLayout {
        id: em
        property string icon: "◌"
        property string title: ""
        property string message: ""
        default property alias actions: ea.data
        Layout.fillWidth: true
        Layout.topMargin: 10; Layout.bottomMargin: 10
        spacing: 6
        Lbl { text: em.icon; color: "#494552"; font.pixelSize: 30; Layout.alignment: Qt.AlignHCenter }
        Lbl { text: em.title; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
        Wrap { text: em.message; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 420; Layout.alignment: Qt.AlignHCenter }
        RowLayout { id: ea; spacing: 8; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 4 }
    }

    component LayoutPreview: Rectangle {
        id: lp
        property var blocks: []
        readonly property var tones: ["#a78bfa", "#7bd0ff", "#3cddc7", "#f2c26b"]
        implicitHeight: 64; radius: 8; color: "#0a0e17"; border.width: 1; border.color: "#252936"
        Mono { visible: lp.blocks.length === 0; anchors.centerIn: parent; text: "no windows"; color: "#494552" }
        Repeater {
            model: lp.blocks
            Rectangle {
                readonly property color tc: lp.tones[index % 4]
                x: 5 + modelData.x * (lp.width - 10); y: 5 + modelData.y * (lp.height - 10)
                width: modelData.w * (lp.width - 10) - 3; height: modelData.h * (lp.height - 10) - 3
                radius: 4; color: Qt.rgba(tc.r, tc.g, tc.b, 0.2); border.width: 1; border.color: Qt.rgba(tc.r, tc.g, tc.b, 0.55)
                Mono { anchors.centerIn: parent; width: parent.width - 4; horizontalAlignment: Text.AlignHCenter; text: modelData.label; color: parent.tc; font.pixelSize: 9 }
            }
        }
    }

    component Modal: Item {
        id: m
        property bool open: false
        property string title: ""
        property string subtitle: ""
        property int dlgWidth: 580
        property int animMs: 160
        property bool hasFooter: true
        default property alias content: bodyCol.data
        property alias footer: footRow.data
        signal dismissed()
        readonly property ThemeData t: ThemeData {}
        anchors.fill: parent
        z: 50
        visible: opacity > 0.01
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: m.animMs; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; color: "#e6070a10"; MouseArea { anchors.fill: parent; onClicked: m.dismissed() } }
        Rectangle {
            id: dlg
            anchors.centerIn: parent
            width: Math.min(m.dlgWidth, m.width - 32)
            height: Math.min(m.height - 40, lay.implicitHeight + 36)
            radius: 14; color: m.t.panel; border.width: 1; border.color: m.t.line
            scale: m.open ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: m.animMs; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
                height: 2; radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: m.t.violet }
                    GradientStop { position: 0.6; color: m.t.cyan }
                    GradientStop { position: 1; color: m.t.teal }
                }
            }
            ColumnLayout {
                id: lay
                anchors { fill: parent; margins: 18 }
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Lbl { text: m.title; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Wrap { visible: m.subtitle !== ""; text: m.subtitle; color: m.t.mute }
                    }
                    Btn { icon: "✕"; kind: "ghost"; compact: true; onClicked: m.dismissed() }
                }
                Flickable {
                    id: bf
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredHeight: bodyCol.implicitHeight
                    contentWidth: width; contentHeight: bodyCol.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout { id: bodyCol; width: bf.width; spacing: 10 }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
                RowLayout { id: footRow; visible: m.hasFooter; Layout.fillWidth: true; spacing: 8 }
            }
        }
    }

    // ======================= HELPERS ========================================
    function uid() { _seq += 1; return "i" + _seq }
    function clone(o) { return JSON.parse(JSON.stringify(o)) }
    function byId(arr, id) { for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return arr[i]; return null }
    function patched(arr, id, patch) {
        var out = []
        for (var i = 0; i < arr.length; i++) {
            var it = arr[i]
            if (it.id === id) { it = clone(it); for (var k in patch) it[k] = patch[k] }
            out.push(it)
        }
        return out
    }
    function removed(arr, id) { var o = []; for (var i = 0; i < arr.length; i++) if (arr[i].id !== id) o.push(arr[i]); return o }
    function upserted(arr, obj, front) {
        var found = false, out = []
        for (var i = 0; i < arr.length; i++) { if (arr[i].id === obj.id) { out.push(obj); found = true } else out.push(arr[i]) }
        if (!found) { if (front) out.unshift(obj); else out.push(obj) }
        return out
    }
    function hasIn(arr, v) { return arr.indexOf(v) >= 0 }
    function toggled(arr, v) { var o = arr.slice(), i = o.indexOf(v); if (i >= 0) o.splice(i, 1); else o.push(v); return o }
    function flip(map, key) { var m = clone(map); m[key] = !m[key]; return m }
    function parseTags(s) {
        var parts = s.split(/[,\s]+/), out = []
        for (var i = 0; i < parts.length; i++) {
            var t = parts[i].replace(/^#+/, "").toLowerCase().trim()
            if (t !== "" && out.indexOf(t) < 0) out.push(t)
        }
        return out
    }
    function shown(arr) { var o = []; for (var i = 0; i < arr.length; i++) if (!(arr[i].sample && !showSampleData)) o.push(arr[i]); return o }
    function copyText(s) { clipHelper.text = s; clipHelper.selectAll(); clipHelper.copy(); clipHelper.text = "" }
    function setSetting(k, v) { var s = clone(settings); s[k] = v; settings = s }
    function go(i) { pageIndex = i; searchOpen = false; notifOpen = false }
    function ask(title, msg, label, danger, fn) { cfTitle = title; cfMsg = msg; cfLabel = label; cfDanger = danger; cfFn = fn; confirmDlg.open = true }
    function notify(title, msg, kind) {
        kind = kind || "info"
        notifications = [{ id: uid(), title: title, msg: msg, kind: kind, time: Qt.formatTime(new Date(), "hh:mm") }].concat(notifications)
        unread += 1
        if (settings.toasts || kind === "warn" || kind === "err")
            toastModel.append({ tid: uid(), title: title, msg: msg, kind: kind })
    }
    function sysRequest(label) {
        if (integrationAvailable) notify("Request sent", label + " was passed to the integration. Results appear in Activity when reported.", "info")
        else notify("Integration unavailable", label + " can’t run — no backend is connected to this component.", "warn")
    }
    function openUrl(u) {
        openUrlRequested(u)
        if (allowDirectUrlOpen) { Qt.openUrlExternally(u); notify("Opening link", u, "info") }
        else notify("Open requested", "No handler is attached. The parent must handle openUrlRequested.", "warn")
    }

    function stateLabel(s) { return s === "enabled" ? "Enabled" : s === "paused" ? "Paused" : s === "upcoming" ? "Upcoming" : s === "failed" ? "Failed" : "Requires Review" }
    function stateTone(s) { return s === "enabled" ? th.teal : s === "paused" ? th.mute : s === "upcoming" ? th.cyan : s === "failed" ? th.red : th.amber }
    function trustLabel(t) { return t === "reviewed" ? "Reviewed" : t === "restricted" ? "Restricted" : "Needs Review" }
    function trustTone(t) { return t === "reviewed" ? th.teal : t === "restricted" ? th.red : th.amber }
    function resLabel(r) { return r === "completed" ? "Completed" : r === "failed" ? "Failed" : r === "cancelled" ? "Cancelled" : "Needs Review" }
    function resTone(r) { return r === "completed" ? th.teal : r === "failed" ? th.red : r === "cancelled" ? th.mute : th.amber }
    function devLabel(s) { return s === "connected" ? "Connected" : s === "pairing" ? "Pairing Required" : s === "unavailable" ? "Unavailable" : "Disconnected" }
    function devTone(s) { return s === "connected" ? th.teal : s === "pairing" ? th.amber : s === "unavailable" ? th.red : th.mute }

    function allDevices() {
        var d = devices.slice()
        if (previewDevices) d.push({ id: "preview", name: "Placeholder device", state: "unavailable", battery: -1, lastSeen: "", capabilities: ["mirror", "file", "share", "find"], preview: true })
        return d
    }
    function connectedDevices() { var o = [], d = devices; for (var i = 0; i < d.length; i++) if (d[i].state === "connected") o.push(d[i]); return o }
    function firstConnected() { var c = connectedDevices(); return c.length ? c[0] : null }
    function compositorLabel() {
        if (compositorState === "connected") return compositorName !== "" ? compositorName : "Connected"
        if (compositorState === "disconnected") return "Disconnected"
        return compositorName !== "" ? compositorName + " (unverified)" : "Unknown"
    }
    function bridgeLabel() {
        var c = firstConnected()
        if (c) return c.name
        return devices.length ? "Disconnected" : "Not connected"
    }
    function statusStrip() {
        var c = firstConnected(), out = []
        out.push({ k: "HOST", v: hostName !== "" ? hostName : "Not connected", tone: hostName !== "" ? th.teal : th.mute })
        out.push({ k: "COMPOSITOR", v: compositorLabel(), tone: compositorState === "connected" ? th.teal : th.mute })
        out.push({ k: "DEVICE BRIDGE", v: bridgeLabel(), tone: c ? th.cyan : th.mute })
        if (c && c.battery >= 0) out.push({ k: "BATTERY", v: c.battery + "%", tone: th.lilac })
        out.push({ k: "INTEGRATION", v: integrationAvailable ? "Available" : "Unavailable", tone: integrationAvailable ? th.teal : th.amber })
        return out
    }

    // ---- actions / automations helpers
    function actionObj(id) { return byId(actionsData, id) }
    function actionName(id) { var a = actionObj(id); return a ? a.name : id }
    function backendOk(id) { return availableActionIds.indexOf(id) >= 0 }
    function hasPower(ids) { for (var i = 0; i < ids.length; i++) { var a = actionObj(ids[i]); if (a && a.category === "Power") return true } return false }
    function isPowerAuto(a) { return hasPower(a.actions) }
    function actionsSummary(a) { var n = []; for (var i = 0; i < a.actions.length; i++) n.push(actionName(a.actions[i])); return n.length ? n.join(" → ") : "No actions" }
    function powerText(ids) {
        var out = []
        for (var i = 0; i < ids.length; i++) {
            if (ids[i] === "suspend") out.push("Suspend puts the machine to sleep; programs that can’t handle suspend may lose unsaved work.")
            else if (ids[i] === "shutdown") out.push("Shutdown powers the machine off; unsaved work in open applications is lost.")
            else if (ids[i] === "reboot") out.push("Reboot restarts the machine; unsaved work in open applications is lost.")
            else if (ids[i] === "schedule_power") out.push("Schedule Power Action creates another consequential schedule.")
        }
        return out
    }
    function trigSummary(a) {
        var d = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        if (a.ttype === "once") return "Once · " + (a.tdate || "date not set") + " " + (a.ttime || "")
        if (a.ttype === "schedule") return (a.tdays.length === 0 || a.tdays.length === 7 ? "Daily" : a.tdays.join(", ")) + " at " + a.ttime
        if (a.ttype === "delay") return "After " + a.tminutes + " min"
        if (a.ttype === "manual") return "Manual only"
        if (a.ttype === "battery") return "Battery " + a.tdir + " " + a.tthreshold + "%"
        if (a.ttype === "device") return "When " + (a.tdevice !== "" ? a.tdevice : "a device") + " connects"
        return "System event: " + (a.tevent !== "" ? a.tevent : "unspecified")
    }
    function trigIcon(a) {
        return a.ttype === "manual" ? "▶" : a.ttype === "battery" ? "▮" : a.ttype === "device" ? "▯" : a.ttype === "event" ? "✱" : a.ttype === "once" ? "◷" : "◔"
    }
    function unsupportedTrigger(t) { return ["battery", "device", "event"].indexOf(t) >= 0 && supportedTriggers.indexOf(t) < 0 }
    function autoCount(f) {
        var n = 0, s = shown(automations)
        for (var i = 0; i < s.length; i++) {
            var st = s[i].state
            if (f === "all" || (f === "active" && st !== "paused") || (f === "upcoming" && st === "upcoming") || (f === "paused" && st === "paused")) n++
        }
        return n
    }
    function visibleAutos() {
        var s = shown(automations), o = []
        for (var i = 0; i < s.length; i++) {
            var st = s[i].state
            if (autoFilter === "all" || (autoFilter === "active" && st !== "paused") || (autoFilter === "upcoming" && st === "upcoming") || (autoFilter === "paused" && st === "paused")) o.push(s[i])
        }
        return o
    }

    // ---- saved space
    function visibleItems() {
        var q = savedQuery.toLowerCase().trim(), out = [], src = shown(savedItems)
        for (var i = 0; i < src.length; i++) {
            var it = src[i]
            if (savedType === "pinned" && !it.pinned) continue
            if (savedType === "favorite" && !it.favorite) continue
            if ((savedType === "bookmark" || savedType === "note" || savedType === "snippet") && it.type !== savedType) continue
            if (savedColl === "__none" && it.collection !== "") continue
            if (savedColl !== "" && savedColl !== "__none" && it.collection !== savedColl) continue
            if (q !== "") {
                var hay = (it.title + " " + it.url + " " + it.content + " " + it.description + " " + it.notes + " " + it.collection + " " + it.tags.join(" ")).toLowerCase()
                if (hay.indexOf(q) < 0) continue
            }
            out.push(it)
        }
        if (savedSort === "az") out.sort(function (a, b) { return a.title.localeCompare(b.title) })
        else if (savedSort === "pinned") out.sort(function (a, b) { return (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) })
        return out
    }
    function countType(t) {
        var n = 0, s = shown(savedItems)
        for (var i = 0; i < s.length; i++) {
            var it = s[i]
            if (t === "all" || it.type === t || (t === "pinned" && it.pinned) || (t === "favorite" && it.favorite)) n++
        }
        return n
    }
    function collCount(c) {
        var n = 0, s = shown(savedItems)
        for (var i = 0; i < s.length; i++) if (c === "__none" ? s[i].collection === "" : s[i].collection === c) n++
        return n
    }
    function collTone(i) { var t = [th.cyan, th.teal, th.lilac, th.amber, th.violet, th.red]; return t[i % t.length] }
    function openCapture(type, item, prefill) {
        var p = prefill || {}
        capEditId = item ? item.id : ""
        capType = item ? item.type : (type || "bookmark")
        capColl = item ? item.collection : (settings.defaultCollection || "")
        capTrust = item && item.trust ? item.trust : "needs-review"
        capBadTitle = false; capBadContent = false; capContentMsg = ""
        capTitle.text = item ? item.title : (p.title || "")
        capUrl.text = item ? item.url : (p.url || "")
        capBody.text = item ? item.content : ""
        capDesc.text = item ? item.description : ""
        capNotes.text = item ? item.notes : ""
        capTags.text = item ? item.tags.join(", ") : ""
        capDlg.open = true
        Qt.callLater(function () { capTitle.input.forceActiveFocus() })
    }
    function commitCapture() {
        var title = capTitle.text.trim(), isB = capType === "bookmark"
        var content = isB ? capUrl.text.trim() : capBody.text.trim()
        capBadTitle = title === ""
        capBadContent = false; capContentMsg = ""
        if (isB) {
            if (content !== "" && !/^[a-z][a-z0-9+.\-]*:\/\//i.test(content)) content = "https://" + content
            if (!/^https?:\/\/[^\s\/]+\.[^\s\/]+/i.test(content)) { capBadContent = true; capContentMsg = "Enter a valid web address, e.g. https://example.com" }
        } else if (content === "") {
            capBadContent = true; capContentMsg = capType === "note" ? "A note needs some text." : "A snippet needs a command."
        }
        if (capBadTitle || capBadContent) return
        var base = capEditId !== "" ? byId(savedItems, capEditId) : null
        var item = { id: base ? base.id : uid(), type: capType, title: title, url: isB ? content : "", content: isB ? "" : content,
                     description: capDesc.text.trim(), notes: capType === "snippet" ? capNotes.text.trim() : "",
                     collection: capColl, tags: parseTags(capTags.text), pinned: base ? base.pinned : false,
                     favorite: base ? base.favorite : false, trust: capType === "snippet" ? capTrust : "", sample: false }
        savedItems = upserted(savedItems, item, true)
        savedItemSaved(item)
        capDlg.open = false
        notify(base ? "Item updated" : "Saved to Space", "“" + title + "” is stored in memory only — it won’t survive a restart unless a backend handles savedItemSaved.", "ok")
    }
    function deleteItemAsk(it) {
        var doIt = function () { savedItems = removed(savedItems, it.id); savedItemDeleted(it.id); notify("Item deleted", it.title, "info") }
        if (settings.confirmDelete) ask("Delete “" + it.title + "”?", "This removes the item from the in-memory Saved Space.", "Delete", true, doIt)
        else doIt()
    }
    function openCollDlg(mode, old) { collMode = mode; collOld = old || ""; collErr = ""; collName.text = old || ""; collDlg.open = true; Qt.callLater(function () { collName.input.forceActiveFocus() }) }
    function commitColl() {
        var n = collName.text.trim()
        if (n === "") { collErr = "Enter a name."; return }
        for (var i = 0; i < collections.length; i++) if (collections[i].toLowerCase() === n.toLowerCase() && collections[i] !== collOld) { collErr = "A collection with that name exists."; return }
        if (collMode === "new") collections = collections.concat([n])
        else {
            var c = []; for (var j = 0; j < collections.length; j++) c.push(collections[j] === collOld ? n : collections[j])
            collections = c
            var its = clone(savedItems); for (var k = 0; k < its.length; k++) if (its[k].collection === collOld) its[k].collection = n
            savedItems = its
            if (savedColl === collOld) savedColl = n
        }
        collDlg.open = false
        notify(collMode === "new" ? "Collection created" : "Collection renamed", n, "ok")
    }
    function deleteCollAsk(c) {
        ask("Delete collection “" + c + "”?", "Its items are kept and become Unsorted.", "Delete collection", true, function () {
            var cs = []; for (var i = 0; i < collections.length; i++) if (collections[i] !== c) cs.push(collections[i])
            collections = cs
            var its = clone(savedItems); for (var k = 0; k < its.length; k++) if (its[k].collection === c) its[k].collection = ""
            savedItems = its
            if (savedColl === c) savedColl = ""
            notify("Collection deleted", c, "info")
        })
    }

    // ---- automations
    function blankAuto() {
        return { id: "", name: "", description: "", ttype: "schedule", ttime: "09:00", tdate: "", tdays: [], tminutes: "30",
                 tthreshold: "20", tdir: "below", tdevice: "", tevent: "", actions: [], conds: [], confirm: true, grace: 15,
                 notify: true, stopOnFail: true, ack: false, enable: false, state: "paused", nextRun: "", lastResult: "", sample: false }
    }
    function openWizard(a, asTemplate) {
        var w = a ? clone(a) : blankAuto()
        if (a && asTemplate) { w.id = ""; w.state = "paused"; w.sample = false }
        w.enable = a && !asTemplate ? (a.state === "enabled" || a.state === "upcoming") : false
        w.ack = false
        wiz = w; wizStep = 0; wizMsg = ""
        wName.text = w.name; wDesc.text = w.description; wTime.text = w.ttime; wDate.text = w.tdate
        wMin.text = w.tminutes; wThr.text = w.tthreshold; wDev.text = w.tdevice; wEvt.text = w.tevent
        autoDlg.open = true
    }
    function setWiz(k, v) { if (JSON.stringify(wiz[k]) === JSON.stringify(v)) return; var w = clone(wiz); w[k] = v; wiz = w }
    function wizError(step) {
        var w = wiz, tm = /^([01]\d|2[0-3]):[0-5]\d$/
        if (step === 0 && w.name.trim() === "") return "Give the automation a name."
        if (step === 1) {
            if (w.ttype === "once") { if (!/^\d{4}-\d{2}-\d{2}$/.test(w.tdate)) return "Enter the date as YYYY-MM-DD."; if (!tm.test(w.ttime)) return "Enter the time as HH:MM (24 h)." }
            if (w.ttype === "schedule" && !tm.test(w.ttime)) return "Enter the time as HH:MM (24 h)."
            if (w.ttype === "delay" && !(parseInt(w.tminutes) > 0)) return "Delay must be a positive number of minutes."
            if (w.ttype === "battery" && !(parseInt(w.tthreshold) >= 1 && parseInt(w.tthreshold) <= 99)) return "Threshold must be 1–99 %."
        }
        if (step === 2 && w.actions.length === 0) return "Select at least one action."
        if (step === 4 && hasPower(w.actions) && !w.ack) return "Acknowledge the consequence of the power action to continue."
        return ""
    }
    function wizNext() {
        var e = wizError(wizStep)
        if (e !== "") { wizMsg = e; return }
        wizMsg = ""
        if (wizStep < 5) wizStep += 1; else wizSave()
    }
    function wizSave() {
        if (hasPower(wiz.actions) && wiz.enable) {
            ask("Enable a consequential schedule?", powerText(wiz.actions).join("\n") + "\n\nSchedule: " + trigSummary(wiz) +
                "\nConfirmation: " + (wiz.grace) + " s cancel window.\n\nThis only stores the definition in the UI; a backend decides whether it ever runs.", "Save & enable", true, function () { commitWiz() })
        } else commitWiz()
    }
    function commitWiz() {
        var w = clone(wiz)
        if (w.id === "") w.id = uid()
        w.state = w.enable ? (unsupportedTrigger(w.ttype) ? "review" : "enabled") : "paused"
        if (hasPower(w.actions)) w.confirm = true
        w.sample = false
        automations = upserted(automations, w, true)
        automationSaved(w)
        autoDlg.open = false
        notify("Automation saved (UI only)", "“" + w.name + "” was stored in memory. No system schedule or timer was created.", "ok")
    }
    function toggleAuto(a) {
        var on = a.state === "paused"
        var apply = function () {
            var st = on ? (unsupportedTrigger(a.ttype) ? "review" : "enabled") : "paused"
            automations = patched(automations, a.id, { state: st })
            automationStateChangeRequested(a.id, on)
            notify(on ? "Marked enabled (UI only)" : "Paused", a.name + " — no real schedule was changed.", "info")
        }
        if (on && isPowerAuto(a)) ask("Enable a consequential schedule?", powerText(a.actions).join("\n") + "\n\nSchedule: " + trigSummary(a), "Enable", true, apply)
        else apply()
    }
    function dupAuto(a) { var c = clone(a); c.id = uid(); c.name = a.name + " (copy)"; c.state = "paused"; c.sample = false; c.nextRun = ""; c.lastResult = ""; automations = upserted(automations, c, true); notify("Automation duplicated", c.name, "ok") }
    function delAutoAsk(a) {
        ask("Delete “" + a.name + "”?", "The definition is removed from the UI. Any real schedule must be removed by the backend.", "Delete", true, function () {
            automations = removed(automations, a.id); automationDeleted(a.id); notify("Automation deleted", a.name, "info")
        })
    }
    function testAuto(a) {
        var pw = isPowerAuto(a), steps = []
        for (var i = 0; i < a.actions.length; i++) steps.push((i + 1) + ".  " + actionName(a.actions[i]))
        pvTitle = "Preview: " + a.name; pvSteps = steps; pvId = a.id
        pvNote = pw ? "Contains a power action. Power actions can’t be test-run from this UI." : "Nothing runs from this preview. “Request test run” only emits a request."
        pvAllow = !pw; pvDlg.open = true
    }
    function wizHasPower() { return hasPower(wiz.actions) }

    // ---- actions
    function filteredActions() {
        var q = actQuery.toLowerCase().trim(), o = []
        for (var i = 0; i < actionsData.length; i++) {
            var a = actionsData[i]
            if (actCat !== "All" && a.category !== actCat) continue
            if (q !== "" && (a.name + " " + a.purpose + " " + a.description + " " + a.category).toLowerCase().indexOf(q) < 0) continue
            o.push(a)
        }
        return o
    }
    function catCount(c) { var n = 0; for (var i = 0; i < actionsData.length; i++) if (c === "All" || actionsData[i].category === c) n++; return n }
    function runAction(a) {
        if (!a.enabled) { notify("Action disabled", a.name + " is disabled in the library.", "warn"); return }
        if (a.trust !== "reviewed") { notify("Review required", a.name + " is “" + trustLabel(a.trust) + "” and can’t be run until a review marks it Reviewed.", "warn"); return }
        var go2 = function () {
            var p = {}; for (var i = 0; i < a.params.length; i++) p[a.params[i].k] = a.params[i].v
            actionRunRequested(a.id, p); sysRequest("“" + a.name + "”")
        }
        if (a.confirm || settings.confirmRun) ask("Run “" + a.name + "”?", a.description + (a.confirm ? "\n\nThis action requires confirmation." : "") + "\n\nThe UI only sends a request; execution belongs to the backend.", "Request run", a.category === "Power", go2)
        else go2()
    }
    function openActionEditor(a) {
        actEditId = a ? a.id : ""
        aeCat = a ? a.category : "Custom Actions"; aeTrust = a && a.trust !== "reviewed" ? a.trust : "needs-review"
        aeConfirm = a ? a.confirm : true; aeMsg = ""
        aName.text = a ? a.name : ""; aDesc.text = a ? a.description : ""; aRef.text = a ? a.ref : ""
        aArgs.text = a ? a.args : ""; aCwd.text = a ? a.cwd : ""
        actDlg.open = true
    }
    function commitAction() {
        if (aName.text.trim() === "") { aeMsg = "Give the action a name."; return }
        if (!/^[A-Za-z0-9_.\-\/:]+$/.test(aRef.text.trim())) { aeMsg = "Reference must be a reviewed identifier or path with no spaces or shell characters."; return }
        if (/[;&|`$<>]/.test(aArgs.text) || /[;&|`$<>]/.test(aCwd.text)) { aeMsg = "Arguments and directory can’t contain shell operators (; & | ` $ < >)."; return }
        var base = actEditId !== "" ? actionObj(actEditId) : null
        var changed = base && (base.ref !== aRef.text.trim() || base.args !== aArgs.text.trim() || base.cwd !== aCwd.text.trim())
        var a = base ? clone(base) : { id: uid(), params: [], enabled: true, builtin: false, sample: false }
        a.name = aName.text.trim(); a.description = aDesc.text.trim(); a.purpose = a.description; a.category = aeCat
        a.ref = aRef.text.trim(); a.args = aArgs.text.trim(); a.cwd = aCwd.text.trim(); a.confirm = aeConfirm || aeCat === "Power"
        a.trust = base && base.trust === "reviewed" && !changed ? "reviewed" : aeTrust
        actionsData = upserted(actionsData, a, false)
        actDlg.open = false
        notify("Action saved", a.name + (changed && base.trust === "reviewed" ? " — changed after review, so it now needs review." : ""), "ok")
    }
    function dupAction(a) { var c = clone(a); c.id = uid(); c.name = a.name + " (copy)"; c.builtin = false; c.sample = false; c.trust = "needs-review"; actionsData = upserted(actionsData, c, false); notify("Action duplicated", c.name + " needs review before it can run.", "ok") }

    // ---- routines
    function editRoutine(rid, fn) {
        var out = []
        for (var i = 0; i < routines.length; i++) { var r = routines[i]; if (r.id === rid) { r = clone(r); fn(r) } out.push(r) }
        routines = out
    }
    function curRoutine() { return byId(routines, rtSelId) }
    function newRoutine() {
        var r = { id: uid(), name: "New workflow", description: "", trigger: "manual", schedule: "", onFail: "stop", enabled: false, sample: false, steps: [] }
        routines = upserted(routines, r, false); rtSelId = r.id; go(4)
    }
    function addStep(aid) { editRoutine(rtSelId, function (r) { r.steps.push({ id: uid(), actionId: aid, cond: "always", note: "" }) }) }
    function moveStep(i, d) { editRoutine(rtSelId, function (r) { var j = i + d; if (j < 0 || j >= r.steps.length) return; var t = r.steps[i]; r.steps[i] = r.steps[j]; r.steps[j] = t }) }
    function dupStep(i) { editRoutine(rtSelId, function (r) { var c = clone(r.steps[i]); c.id = uid(); r.steps.splice(i + 1, 0, c) }) }
    function delStep(i) { editRoutine(rtSelId, function (r) { r.steps.splice(i, 1) }) }
    function patchStep(i, patch) { editRoutine(rtSelId, function (r) { for (var k in patch) r.steps[i][k] = patch[k] }) }
    function previewRoutine(r) {
        var s = [], cl = { always: "", integration: "  (only if integration available)", prev_ok: "  (only if previous step succeeded)" }
        for (var i = 0; i < r.steps.length; i++) s.push((i + 1) + ".  " + actionName(r.steps[i].actionId) + cl[r.steps[i].cond])
        pvTitle = "Preview: " + r.name; pvSteps = s; pvId = r.id
        pvNote = "On failure: " + (r.onFail === "stop" ? "stop the workflow." : "continue with the next step.") + " Nothing runs from this preview."
        pvAllow = false; pvDlg.open = true
    }
    function routineHistory(r) { var n = 0, e = activityEvents; for (var i = 0; i < e.length; i++) if (e[i].automation === r.name || e[i].name === r.name) n++; return n }
    function delRoutineAsk(r) {
        ask("Delete “" + r.name + "”?", "The workflow definition is removed from the UI.", "Delete", true, function () {
            routines = removed(routines, r.id); var s = shown(routines); rtSelId = s.length ? s[0].id : ""; notify("Workflow deleted", r.name, "info")
        })
    }

    // ---- devices / links / presets / history
    function allLinks() {
        var l = sharedLinks.slice()
        if (previewDevices) {
            l.push({ id: "pl1", title: "Placeholder shared link", url: "https://example.com/placeholder", source: "Placeholder device", received: "", preview: true })
            l.push({ id: "pl2", title: "Another placeholder link", url: "https://example.org/sample", source: "Placeholder device", received: "", preview: true })
        }
        var o = []; for (var i = 0; i < l.length; i++) if (dismissedLinks.indexOf(l[i].id) < 0) o.push(l[i])
        return o
    }
    function devRequest(key, label) {
        var d = byId(allDevices(), devSel)
        if (!d || d.state !== "connected") { notify("No connected device", label + " needs a connected device. Select one that reports “Connected”.", "warn"); return }
        deviceActionRequested(d.id, key, {}); sysRequest(label + " on " + d.name)
    }
    function activatePreset(p) { presetSel = p.id; presetActivateRequested(p.id); sysRequest("Activating preset “" + p.name + "”") }
    function openPresetEditor(p) {
        presetEditId = p.id; peDnd = p.dnd; peTimer = p.timer
        pName.text = p.name; pDesc.text = p.description; pApps.text = p.apps.join(", ")
        presetDlg.open = true
    }
    function commitPreset() {
        if (pName.text.trim() === "") return
        var apps = []; var parts = pApps.text.split(","); for (var i = 0; i < parts.length; i++) if (parts[i].trim() !== "") apps.push(parts[i].trim())
        presets = patched(presets, presetEditId, { name: pName.text.trim(), description: pDesc.text.trim(), apps: apps, dnd: peDnd, timer: peTimer, sample: false })
        presetDlg.open = false; notify("Preset saved (UI only)", pName.text.trim(), "ok")
    }
    function dupPreset(p) { var c = clone(p); c.id = uid(); c.name = p.name + " (copy)"; c.sample = false; presets = upserted(presets, c, false); notify("Preset duplicated", c.name, "ok") }
    function sampleEvents() {
        var n = Date.now(), h = 3600000
        return [
            { id: "e1", ts: n - 1 * h, name: "Study Mode", trigger: "Schedule", result: "completed", duration: "1.2 s", category: "Automation", automation: "Study Mode", details: "Sample entry. Every action in the sequence reported success.", sample: true },
            { id: "e2", ts: n - 3 * h, name: "Lock Screen", trigger: "Manual", result: "completed", duration: "0.3 s", category: "Desktop", automation: "", details: "Sample entry.", sample: true },
            { id: "e3", ts: n - 7 * h, name: "Device Connected Notification", trigger: "Device", result: "failed", duration: "", category: "Automation", automation: "Device Connected Notification", details: "Sample entry. The trigger source was unavailable.", sample: true },
            { id: "e4", ts: n - 26 * h, name: "Scheduled Suspend", trigger: "Schedule", result: "cancelled", duration: "", category: "Power", automation: "Scheduled Suspend", details: "Sample entry. Cancelled during the confirmation window.", sample: true },
            { id: "e5", ts: n - 50 * h, name: "Development Workspace", trigger: "Schedule", result: "review", duration: "", category: "Automation", automation: "Development Workspace", details: "Sample entry. An action in this routine needs review.", sample: true }]
    }
    function allEvents() { var e = activityEvents.slice(); if (previewActivity) e = e.concat(sampleEvents()); return e }
    function fmtTs(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : Qt.formatDateTime(d, "MMM d · hh:mm") }
    function visibleEvents() {
        var e = allEvents(), o = [], now = Date.now()
        for (var i = 0; i < e.length; i++) {
            var x = e[i]
            if (histStatus !== "all" && x.result !== histStatus) continue
            if (histCat !== "All" && x.category !== histCat) continue
            if (histAuto !== "All" && x.automation !== histAuto) continue
            var t = new Date(x.ts).getTime()
            if (histRange === "24h" && !isNaN(t) && now - t > 86400000) continue
            if (histRange === "7d" && !isNaN(t) && now - t > 604800000) continue
            o.push(x)
        }
        return o
    }
    function distinct(key) { var e = allEvents(), o = ["All"]; for (var i = 0; i < e.length; i++) if (e[i][key] && o.indexOf(e[i][key]) < 0) o.push(e[i][key]); return o }

    // ---- global search
    function searchAll(q) {
        q = q.toLowerCase().trim()
        if (q === "") return []
        var out = []
        function add(kind, title, sub, page) { out.push({ kind: kind, title: title, sub: sub, page: page }) }
        var s = shown(savedItems), i
        for (i = 0; i < s.length; i++) if ((s[i].title + " " + s[i].tags.join(" ") + " " + s[i].description).toLowerCase().indexOf(q) >= 0) add("Saved", s[i].title, s[i].type, 1)
        var a = shown(automations)
        for (i = 0; i < a.length; i++) if (a[i].name.toLowerCase().indexOf(q) >= 0) add("Automation", a[i].name, trigSummary(a[i]), 2)
        for (i = 0; i < actionsData.length; i++) if ((actionsData[i].name + " " + actionsData[i].category).toLowerCase().indexOf(q) >= 0) add("Action", actionsData[i].name, actionsData[i].category, 3)
        var r = shown(routines)
        for (i = 0; i < r.length; i++) if (r[i].name.toLowerCase().indexOf(q) >= 0) add("Workflow", r[i].name, r[i].steps.length + " steps", 4)
        var d = allDevices()
        for (i = 0; i < d.length; i++) if (d[i].name.toLowerCase().indexOf(q) >= 0) add("Device", d[i].name, devLabel(d[i].state), 5)
        var p = shown(presets)
        for (i = 0; i < p.length; i++) if (p[i].name.toLowerCase().indexOf(q) >= 0) add("Preset", p[i].name, p[i].description, 6)
        return out.slice(0, 12)
    }
    function pickResult(r) {
        if (r.page === 1) savedQuery = r.title
        if (r.page === 3) actQuery = r.title
        go(r.page); globalSearch.text = ""
    }

    // ======================= SAMPLE DATA (clearly labelled SAMPLE in UI) =====
    function sampleSavedItems() {
        return [
            { id: "s1", type: "bookmark", title: "Hyprland Wiki", url: "https://wiki.hyprland.org", content: "", description: "Configuration reference and dispatcher documentation.", notes: "", collection: "Linux", tags: ["linux", "wayland"], pinned: true, favorite: true, trust: "", sample: true },
            { id: "s2", type: "bookmark", title: "Qt Quick documentation", url: "https://doc.qt.io/qt-6/qtquick-index.html", content: "", description: "Types, layouts and best practices for QML.", notes: "", collection: "Development", tags: ["qml", "ui"], pinned: false, favorite: false, trust: "", sample: true },
            { id: "s3", type: "bookmark", title: "Python tutorial", url: "https://docs.python.org/3/tutorial/", content: "", description: "Official tutorial.", notes: "", collection: "Python Learning", tags: ["python"], pinned: false, favorite: true, trust: "", sample: true },
            { id: "s4", type: "bookmark", title: "Hugging Face", url: "https://huggingface.co", content: "", description: "Models and datasets.", notes: "", collection: "AI Tools", tags: ["ai", "models"], pinned: false, favorite: false, trust: "", sample: true },
            { id: "s5", type: "note", title: "Layer-shell sizing reminder", url: "", content: "Give every layer-shell surface an explicit, non-zero size before showing it, and test with the panel hidden and shown.", description: "", notes: "", collection: "Development", tags: ["qml", "layer-shell"], pinned: true, favorite: false, trust: "", sample: true },
            { id: "s6", type: "note", title: "Study plan sketch", url: "", content: "Week 1: Python basics. Week 2: small automation scripts. Week 3: API calls and JSON.", description: "", notes: "", collection: "Python Learning", tags: ["plan"], pinned: false, favorite: false, trust: "", sample: true },
            { id: "s7", type: "snippet", title: "List audio sinks", url: "", content: "wpctl status", description: "Shows audio devices known to the sound server.", notes: "Read-only inspection.", collection: "Linux", tags: ["audio", "pipewire"], pinned: true, favorite: false, trust: "reviewed", sample: true },
            { id: "s8", type: "snippet", title: "Show layer surfaces", url: "", content: "hyprctl layers", description: "Dumps layer-shell surfaces for debugging.", notes: "", collection: "Linux", tags: ["hyprland", "debug"], pinned: false, favorite: false, trust: "reviewed", sample: true },
            { id: "s9", type: "snippet", title: "Trim package cache", url: "", content: "paccache -rk1", description: "Deletes old cached package versions (permanent).", notes: "Destructive — review before use.", collection: "Linux", tags: ["pacman", "cleanup"], pinned: false, favorite: false, trust: "needs-review", sample: true },
            { id: "s10", type: "snippet", title: "Remove orphaned packages", url: "", content: "pacman -Rns $(pacman -Qdtq)", description: "Removes packages nothing depends on.", notes: "Needs elevated rights.", collection: "Linux", tags: ["pacman"], pinned: false, favorite: false, trust: "restricted", sample: true }]
    }
    function sampleAutomations() {
        var b = blankAuto()
        function mk(o) { var x = clone(b); for (var k in o) x[k] = o[k]; x.sample = true; return x }
        return [
            mk({ id: "a1", name: "Study Mode", description: "Focus session with notifications muted.", ttype: "schedule", ttime: "16:00", actions: ["focus_start", "dnd_enable", "open_terminal"], state: "enabled" }),
            mk({ id: "a2", name: "Bedtime Reminder", description: "Gentle evening reminder.", ttype: "schedule", ttime: "22:45", actions: ["show_reminder"], state: "upcoming" }),
            mk({ id: "a3", name: "Scheduled Suspend", description: "Suspend late at night.", ttype: "schedule", ttime: "01:30", actions: ["suspend"], grace: 30, state: "paused" }),
            mk({ id: "a4", name: "Development Workspace", description: "Open the development layout on weekdays.", ttype: "schedule", ttime: "09:00", tdays: ["Mon", "Tue", "Wed", "Thu", "Fri"], actions: ["open_dev_ws"], state: "review" }),
            mk({ id: "a5", name: "Device Connected Notification", description: "Notify when a phone connects.", ttype: "device", tdevice: "my phone", actions: ["notify", "device_shortcuts"], state: "failed", lastResult: "Sample result: trigger source unavailable." })]
    }
    function automationTemplates() {
        var b = blankAuto()
        function mk(o) { var x = clone(b); for (var k in o) x[k] = o[k]; return x }
        return [
            mk({ name: "Study Mode", description: "Focus session with notifications muted.", ttype: "schedule", ttime: "16:00", actions: ["focus_start", "dnd_enable"] }),
            mk({ name: "Development Workspace", description: "Open the development layout.", ttype: "schedule", ttime: "09:00", tdays: ["Mon", "Tue", "Wed", "Thu", "Fri"], actions: ["open_dev_ws"] }),
            mk({ name: "Bedtime Reminder", description: "Evening wind-down reminder.", ttype: "schedule", ttime: "22:45", actions: ["show_reminder"] }),
            mk({ name: "Scheduled Suspend", description: "Suspend at a set time.", ttype: "schedule", ttime: "01:30", actions: ["suspend"], grace: 30 }),
            mk({ name: "Scheduled Shutdown", description: "Shut down at a set time.", ttype: "schedule", ttime: "23:30", actions: ["shutdown"], grace: 60 }),
            mk({ name: "Entertainment Mode", description: "Media hub and music.", ttype: "manual", actions: ["open_media_hub", "launch_music"] }),
            mk({ name: "Device Connected Notification", description: "Notify on phone connection.", ttype: "device", actions: ["notify", "device_shortcuts"] })]
    }
    function sampleActions() {
        function P(id, name, cat, desc, trust, confirm, params) {
            return { id: id, name: name, category: cat, purpose: desc, description: desc, params: params || [], trust: trust, confirm: confirm, enabled: true, builtin: true,
                     ref: cat.toLowerCase().split(" ")[0] + "." + id, args: "", cwd: "", sample: true }
        }
        return [
            P("lock_screen", "Lock Screen", "Desktop", "Locks the current session.", "reviewed", false),
            P("show_reminder", "Show Reminder", "Desktop", "Shows an on-screen reminder message.", "reviewed", false, [{ k: "message", v: "(set when used)" }]),
            P("notify", "Send Notification", "Desktop", "Posts a desktop notification.", "reviewed", false, [{ k: "title", v: "" }]),
            P("dnd_enable", "Enable Do Not Disturb", "Desktop", "Mutes notifications while active. Needs a working notification integration.", "needs-review", false),
            P("user_review_pause", "Pause for Review", "Desktop", "Waits until the user confirms their work is saved.", "reviewed", true),
            P("apply_preset", "Apply Workspace Preset", "Desktop", "Requests a workspace preset be applied.", "reviewed", false, [{ k: "preset", v: "" }]),
            P("focus_start", "Start Focus Session", "Desktop", "Starts a focus timer.", "reviewed", false, [{ k: "minutes", v: "25" }]),
            P("open_browser", "Open Browser", "Applications", "Opens the default browser.", "reviewed", false),
            P("open_terminal", "Open Terminal", "Applications", "Opens a terminal emulator.", "reviewed", false),
            P("launch_music", "Launch Music Application", "Applications", "Starts the chosen music player if installed.", "needs-review", false),
            P("open_saved_url", "Open Saved URL", "Applications", "Opens a bookmark from Saved Space.", "reviewed", false, [{ k: "url", v: "" }]),
            P("set_volume", "Set Volume", "Audio", "Sets the output volume to a level.", "reviewed", false, [{ k: "level", v: "40" }]),
            P("audio_controls", "Open Audio Controls", "Audio", "Opens the audio panel.", "reviewed", false),
            P("set_brightness", "Set Brightness", "Display", "Sets display brightness where supported.", "needs-review", false, [{ k: "percent", v: "60" }]),
            P("network_summary", "Show Network Summary", "Network", "Shows connection state.", "reviewed", false),
            P("open_dev_ws", "Open Development Workspace", "Development", "Opens the editor, terminal and browser layout.", "needs-review", false),
            P("dev_utility", "Run Reviewed Utility Task", "Development", "Runs a named utility task from a reviewed list.", "needs-review", true, [{ k: "task", v: "" }]),
            P("open_media_hub", "Open Media Hub", "Media", "Opens the media hub panel.", "reviewed", false),
            P("scrcpy_launch", "Launch scrcpy", "Phone & Devices", "Starts device mirroring with a profile.", "reviewed", false, [{ k: "profile", v: "default" }]),
            P("find_phone", "Find Phone", "Phone & Devices", "Asks the phone to ring.", "reviewed", false),
            P("send_file", "Send File to Phone", "Phone & Devices", "Sends a chosen file to the selected device.", "reviewed", true),
            P("detect_device_event", "Detect Device Event", "Phone & Devices", "Waits for a supported device event.", "needs-review", false),
            P("device_shortcuts", "Show Device Shortcuts", "Phone & Devices", "Shows quick actions for the device.", "reviewed", false),
            P("suspend", "Suspend", "Power", "Puts the machine to sleep.", "reviewed", true),
            P("shutdown", "Shut Down", "Power", "Powers the machine off.", "reviewed", true),
            P("reboot", "Reboot", "Power", "Restarts the machine.", "reviewed", true),
            P("schedule_power", "Schedule a Power Action", "Power", "Creates a scheduled power action.", "reviewed", true)]
    }
    function sampleRoutines() {
        var n = 0
        function S(a, c) { n += 1; return { id: "ss" + n, actionId: a, cond: c || "always", note: "" } }
        return [
            { id: "rt1", name: "Deep Work", description: "Template: dev workspace, focus timer, volume, DND.", trigger: "manual", schedule: "", onFail: "continue", enabled: false, sample: true,
              steps: [S("open_dev_ws"), S("focus_start"), S("set_volume"), S("dnd_enable", "integration")] },
            { id: "rt2", name: "Bedtime", description: "Template: reminder, review pause, confirmed suspend.", trigger: "scheduled", schedule: "Daily 22:45", onFail: "stop", enabled: false, sample: true,
              steps: [S("show_reminder"), S("user_review_pause"), S("suspend", "prev_ok")] },
            { id: "rt3", name: "Device Connected", description: "Template: detect event, notify, show shortcuts.", trigger: "scheduled", schedule: "On device event", onFail: "stop", enabled: false, sample: true,
              steps: [S("detect_device_event"), S("notify"), S("device_shortcuts")] },
            { id: "rt4", name: "Entertainment", description: "Template: media hub, music app, workspace preset.", trigger: "manual", schedule: "", onFail: "continue", enabled: false, sample: true,
              steps: [S("open_media_hub"), S("launch_music", "integration"), S("apply_preset")] }]
    }
    function samplePresets() {
        function B(x, y, w, h, l) { return { x: x, y: y, w: w, h: h, label: l } }
        return [
            { id: "p1", name: "Coding", description: "Editor, terminal and browser side by side.", apps: ["Editor", "Terminal", "Browser"], dnd: false, timer: "none", sample: true, layout: [B(0, 0, 0.55, 1, "EDITOR"), B(0.55, 0, 0.45, 0.5, "WEB"), B(0.55, 0.5, 0.45, 0.5, "TERM")] },
            { id: "p2", name: "Study", description: "Learning material beside a focus timer.", apps: ["Reader", "Notes", "Timer"], dnd: true, timer: "25", sample: true, layout: [B(0, 0, 0.6, 1, "READER"), B(0.6, 0, 0.4, 0.4, "TIMER"), B(0.6, 0.4, 0.4, 0.6, "NOTES")] },
            { id: "p3", name: "Entertainment", description: "Media in front, chat on the side.", apps: ["Media", "Chat"], dnd: false, timer: "none", sample: true, layout: [B(0, 0, 0.65, 1, "MEDIA"), B(0.65, 0, 0.35, 1, "CHAT")] },
            { id: "p4", name: "Presentation", description: "One fullscreen window, notifications muted.", apps: ["Slides"], dnd: true, timer: "none", sample: true, layout: [B(0, 0, 1, 1, "FULLSCREEN")] },
            { id: "p5", name: "Communication", description: "Chat, mail and calendar together.", apps: ["Chat", "Mail", "Calendar"], dnd: false, timer: "none", sample: true, layout: [B(0, 0, 0.5, 1, "CHAT"), B(0.5, 0, 0.5, 0.5, "MAIL"), B(0.5, 0.5, 0.5, 0.5, "CAL")] },
            { id: "p6", name: "Clean Desktop", description: "No windows, minimal distractions.", apps: [], dnd: true, timer: "none", sample: true, layout: [] }]
    }

    // ======================= SHORTCUTS ======================================
    Shortcut { sequence: "Ctrl+K"; onActivated: { globalSearch.input.forceActiveFocus(); root.searchOpen = true } }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (confirmDlg.open) confirmDlg.open = false
            else if (pvDlg.open) pvDlg.open = false
            else if (capDlg.open) capDlg.open = false
            else if (autoDlg.open) autoDlg.open = false
            else if (actDlg.open) actDlg.open = false
            else if (presetDlg.open) presetDlg.open = false
            else if (collDlg.open) collDlg.open = false
            else if (settingsDlg.open) settingsDlg.open = false
            else if (root.notifOpen || root.searchOpen) { root.notifOpen = false; root.searchOpen = false }
            else if (root.showCloseButton) { root.closeRequested() }
        }
    }

    // ======================= SHELL LAYOUT ===================================
    Rectangle { anchors.fill: parent; color: th.bg }
    RowLayout {
        anchors.fill: parent; spacing: 0

        // ---- sidebar
        Rectangle {
            Layout.preferredWidth: root.navW; Layout.fillHeight: true; color: th.panel
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: th.line }
            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 6; spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 8; color: th.a(th.violet, 0.18)
                        Mono { anchors.centerIn: parent; text: ">_"; color: th.lilac; font.bold: true }
                    }
                    ColumnLayout {
                        visible: !root.compactNav; spacing: 0
                        Lbl { text: "GPS TOOLBOX"; font.weight: Font.Bold; font.pixelSize: 13 }
                        Cap { text: "UI PROTOTYPE" }
                    }
                }
                Btn { Layout.fillWidth: true; kind: "primary"; icon: "+"; text: root.compactNav ? "" : "Quick Capture"; onClicked: root.openCapture("bookmark", null) }
                Item { implicitHeight: 6 }
                Repeater {
                    model: root.navItems
                    Rectangle {
                        id: nv
                        readonly property bool sel: root.pageIndex === index
                        Layout.fillWidth: true; implicitHeight: 38; radius: 9
                        color: sel ? th.a(th.violet, 0.14) : (nvMa.containsMouse ? th.panelHi : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Rectangle { visible: nv.sel; width: 3; height: 18; radius: 2; color: th.violet; anchors.verticalCenter: parent.verticalCenter }
                        RowLayout {
                            anchors { fill: parent; leftMargin: root.compactNav ? 0 : 12; rightMargin: 8 }
                            spacing: 10
                            Lbl { text: modelData.icon; color: nv.sel ? th.lilac : th.mute; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter
                                  Layout.preferredWidth: 22; Layout.fillWidth: root.compactNav }
                            Lbl { visible: !root.compactNav; text: modelData.label; Layout.fillWidth: true
                                  color: nv.sel ? th.text : th.dim; font.weight: nv.sel ? Font.DemiBold : Font.Normal }
                        }
                        MouseArea { id: nvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.go(index) }
                    }
                }
                Item { Layout.fillHeight: true }
                Rectangle {
                    visible: !root.compactNav
                    Layout.fillWidth: true; implicitHeight: sbc.implicitHeight + 16; radius: 8; color: th.well
                    ColumnLayout {
                        id: sbc; x: 8; y: 8; width: parent.width - 16; spacing: 2
                        Row { spacing: 6
                            Rectangle { width: 7; height: 7; radius: 4; color: root.compositorState === "connected" ? th.teal : th.mute; anchors.verticalCenter: parent.verticalCenter }
                            Cap { text: "COMPOSITOR" } }
                        Mono { text: root.compositorLabel(); color: th.dim; Layout.fillWidth: true }
                        Mono { text: (root.hostName !== "" ? root.hostName : "Host not connected") + (root.osName !== "" ? " · " + root.osName : ""); color: th.mute; Layout.fillWidth: true }
                    }
                }
                Btn { Layout.fillWidth: true; kind: "ghost"; icon: "⚙"; text: root.compactNav ? "" : "Settings"; onClicked: settingsDlg.open = true }
            }
        }

        // ---- main column
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // top bar
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 56; color: th.bg
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: th.line }
                RowLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 14 }
                    spacing: 8
                    Field {
                        id: globalSearch
                        Layout.maximumWidth: 440
                        icon: "⌕"; placeholder: "Search saved items, actions, automations…  (Ctrl+K)"
                        onTextChanged: root.searchOpen = text !== ""
                        onAccepted: if (root.searchResults.length) root.pickResult(root.searchResults[0])
                    }
                    Spacer {}
                    Chip { visible: !root.integrationAvailable; text: "INTEGRATION UNAVAILABLE"; tone: th.amber; dot: true }
                    Chip { visible: root.settings.showDeviceChip && root.firstConnected() !== null
                           text: root.firstConnected() ? ("PHONE · " + root.firstConnected().name + (root.firstConnected().battery >= 0 ? " " + root.firstConnected().battery + "%" : "")) : ""
                           tone: th.cyan; dot: true }
                    Chip { visible: root.nextRunSummary !== ""; text: "NEXT · " + root.nextRunSummary; tone: th.lilac }
                    Btn { icon: "+"; text: "Capture"; onClicked: root.openCapture("bookmark", null) }
                    Item {
                        implicitWidth: 34; implicitHeight: 32
                        Btn { anchors.fill: parent; kind: "ghost"; icon: "◉"; active: root.notifOpen; onClicked: { root.notifOpen = !root.notifOpen; root.unread = 0 } }
                        Rectangle { visible: root.unread > 0; width: 8; height: 8; radius: 4; color: th.cyan; anchors { top: parent.top; right: parent.right; topMargin: 5; rightMargin: 5 } }
                    }
                    Btn { kind: "ghost"; icon: "⚙"; onClicked: settingsDlg.open = true }
                    Btn { visible: root.showCloseButton; kind: "ghost"; icon: "✕"; onClicked: root.closeRequested() }
                }
            }

            // pages
            Item {
                id: stage
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                Repeater {
                    model: 8
                    Item {
                        id: holder
                        readonly property bool cur: index === root.pageIndex
                        property bool seen: false
                        width: stage.width; height: stage.height
                        y: cur ? 0 : 10
                        opacity: cur ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                        onCurChanged: if (cur) seen = true
                        Component.onCompleted: if (cur) seen = true
                        Loader { anchors.fill: parent; active: holder.seen; sourceComponent: root.pageComps[index] }
                    }
                }
            }
        }
    }

    // ======================= POPUPS =========================================
    MouseArea {
        z: 39; x: 0; y: 56; width: parent.width; height: parent.height - 56
        visible: root.notifOpen || (root.searchOpen && globalSearch.text !== "")
        onClicked: { root.notifOpen = false; root.searchOpen = false }
    }
    Rectangle {
        id: searchPop
        z: 40; x: root.navW + 18; y: 50
        width: Math.min(460, root.width - root.navW - 36)
        height: Math.min(380, spc.implicitHeight + 14)
        radius: 12; color: th.panelHi; border.width: 1; border.color: th.line
        visible: root.searchOpen && globalSearch.text !== ""
        ColumnLayout {
            id: spc; x: 7; y: 7; width: parent.width - 14; spacing: 2
            Empty { visible: root.searchResults.length === 0; icon: "⌕"; title: "No matches"; message: "Nothing found in saved items, actions, automations, workflows, devices or presets." }
            Repeater {
                model: root.searchResults
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 36; radius: 8; color: srMa.containsMouse ? th.raised : "transparent"
                    RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 10 } spacing: 8
                        Chip { text: modelData.kind.toUpperCase(); tone: th.cyan }
                        Lbl { text: modelData.title; Layout.fillWidth: true }
                        Mono { text: modelData.sub; color: th.mute; Layout.maximumWidth: 150 } }
                    MouseArea { id: srMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickResult(modelData) }
                }
            }
        }
    }
    Rectangle {
        z: 40; width: 340; x: root.width - width - 14; y: 50
        height: Math.min(root.height - 70, nc.implicitHeight + 24)
        radius: 12; color: th.panelHi; border.width: 1; border.color: th.line
        opacity: root.notifOpen ? 1 : 0; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.animMs } }
        ColumnLayout {
            id: nc; x: 12; y: 12; width: parent.width - 24; spacing: 8
            RowLayout { Layout.fillWidth: true
                Lbl { text: "Notifications"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Btn { compact: true; kind: "ghost"; text: "Clear all"; enabled: root.notifications.length > 0; onClicked: root.notifications = [] } }
            Empty { visible: root.notifications.length === 0; icon: "◉"; title: "All quiet"; message: "UI events and backend notices will appear here." }
            Repeater {
                model: root.notifications.slice(0, 7)
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: nr.implicitHeight + 16; radius: 8; color: th.well
                    readonly property color tone: modelData.kind === "ok" ? th.teal : modelData.kind === "warn" ? th.amber : modelData.kind === "err" ? th.red : th.cyan
                    Rectangle { width: 3; radius: 2; color: parent.tone; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 6 } }
                    ColumnLayout { id: nr; x: 16; y: 8; width: parent.width - 48; spacing: 1
                        RowLayout { Layout.fillWidth: true
                            Lbl { text: modelData.title; font.weight: Font.DemiBold; font.pixelSize: 12; Layout.fillWidth: true }
                            Mono { text: modelData.time; color: th.mute; font.pixelSize: 10 } }
                        Wrap { text: modelData.msg; font.pixelSize: 11 } }
                    Btn { compact: true; kind: "ghost"; icon: "✕"; anchors { right: parent.right; top: parent.top; margins: 4 }
                          onClicked: root.notifications = root.notifications.filter(function (n) { return n.id !== modelData.id }) }
                }
            }
        }
    }

    // toasts
    Column {
        z: 80; spacing: 8
        anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
        Repeater {
            model: toastModel
            Rectangle {
                id: tst
                readonly property color tone: kind === "ok" ? th.teal : kind === "warn" ? th.amber : kind === "err" ? th.red : th.cyan
                width: 340; height: tcol.implicitHeight + 22; radius: 12
                color: th.raised; border.width: 1; border.color: th.a(tone, 0.5)
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: root.animMs } }
                Component.onCompleted: opacity = 1
                Rectangle { width: 3; radius: 2; color: tst.tone; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 } }
                ColumnLayout { id: tcol; x: 18; y: 11; width: parent.width - 32; spacing: 2
                    Lbl { text: title; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Wrap { text: msg; font.pixelSize: 11 } }
                Timer { interval: kind === "warn" || kind === "err" ? 5600 : 3400; running: true; onTriggered: toastModel.remove(index) }
                MouseArea { anchors.fill: parent; onClicked: toastModel.remove(index) }
            }
        }
    }

    // ======================= PAGES ==========================================

    // ---------------------------------------------------------- HOME
    Component {
        id: homePage
        PageScroll {
            Card {
                Layout.fillWidth: true; pad: 18; gap: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Cap { text: "DESKTOP COMMAND CENTER"; color: th.lilac }
                        Lbl { text: "Your desktop, under your control."; font.pixelSize: 28; font.weight: Font.Bold; Layout.fillWidth: true }
                        Wrap { text: "Launch reviewed actions, capture links and notes, schedule routines and manage your phone bridge. Everything here is a request surface — nothing runs until a backend is connected." }
                    }
                    Rectangle {
                        visible: root.width > 900; Layout.alignment: Qt.AlignTop
                        implicitWidth: 180; implicitHeight: 54; radius: 10; color: th.well
                        Column { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 } spacing: 2
                            Cap { text: "COMPOSITOR" }
                            Mono { text: root.compositorLabel(); color: root.compositorState === "connected" ? th.teal : th.dim; font.pixelSize: 12 } }
                    }
                }
                Rule {}
                Flow {
                    Layout.fillWidth: true; spacing: 22
                    Repeater {
                        model: root.statusStrip()
                        Row { spacing: 6
                            Rectangle { width: 7; height: 7; radius: 4; color: modelData.tone; anchors.verticalCenter: parent.verticalCenter }
                            Cap { text: modelData.k }
                            Mono { text: modelData.v; color: th.text; font.pixelSize: 12 } }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                RowLayout { Layout.fillWidth: true
                    Cap { text: "QUICK ACTIONS"; Layout.fillWidth: true }
                    Mono { text: "requests only"; color: th.mute } }
                GridLayout {
                    id: qg
                    Layout.fillWidth: true
                    columns: width > 900 ? 4 : (width > 480 ? 2 : 1)
                    columnSpacing: 10; rowSpacing: 10
                    readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                    Repeater {
                        model: root.quickActions
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredWidth: qg.cw; implicitHeight: 64; radius: 12
                            color: qaMa.containsMouse ? th.panelHi : th.panel
                            border.width: 1; border.color: modelData.create ? th.a(th.violet, 0.55) : th.line
                            scale: qaMa.pressed ? 0.98 : 1
                            Behavior on scale { NumberAnimation { duration: 70 } }
                            Behavior on color { ColorAnimation { duration: 100 } }
                            RowLayout {
                                anchors { fill: parent; margins: 12 } spacing: 10
                                Rectangle { Layout.preferredWidth: 34; Layout.preferredHeight: 34; radius: 9; color: th.a(th.violet, 0.14)
                                    Lbl { anchors.centerIn: parent; text: modelData.icon; color: th.lilac; font.pixelSize: 14 } }
                                ColumnLayout { Layout.fillWidth: true; spacing: 1
                                    Lbl { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                    Mono { Layout.fillWidth: true; color: th.mute
                                        text: modelData.k === "nav" ? (modelData.create ? "Routine Builder" : root.countType("all") + " items") : (root.backendOk(modelData.id) ? "Backend available" : "Needs integration") } }
                            }
                            MouseArea { id: qaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.k === "nav") { if (modelData.create) root.newRoutine(); else root.go(modelData.target) }
                                    else root.runAction(root.actionObj(modelData.id))
                                } }
                        }
                    }
                }
            }

            GridLayout {
                id: hg
                Layout.fillWidth: true
                columns: width > 900 ? 2 : 1; columnSpacing: 14; rowSpacing: 14
                readonly property real lw: columns === 2 ? Math.round((width - 14) * 0.6) : width
                readonly property real rw: columns === 2 ? width - 14 - lw : width

                ColumnLayout {
                    Layout.preferredWidth: hg.lw; Layout.alignment: Qt.AlignTop; spacing: 14
                    Card {
                        Layout.fillWidth: true
                        SecTitle { text: "Scheduled Automations"; icon: "◔"; tone: th.lilac
                            Btn { compact: true; kind: "ghost"; text: "View all"; onClicked: root.go(2) } }
                        Mono { text: "Definitions below are SAMPLE UI entries — no system schedule exists."; color: th.mute; Layout.fillWidth: true; visible: root.showSampleData }
                        Repeater {
                            model: root.shown(root.automations).slice(0, 4)
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 58; radius: 10; color: th.panelHi
                                RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 8 } spacing: 8
                                    Rectangle { Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 8; color: th.a(root.isPowerAuto(modelData) ? th.red : th.cyan, 0.14)
                                        Lbl { anchors.centerIn: parent; text: root.isPowerAuto(modelData) ? "⏻" : root.trigIcon(modelData); color: root.isPowerAuto(modelData) ? th.red : th.cyan } }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 2
                                        RowLayout { spacing: 6
                                            Lbl { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                            Chip { text: root.stateLabel(modelData.state).toUpperCase(); tone: root.stateTone(modelData.state); dot: true } }
                                        Mono { text: root.trigSummary(modelData) + " · " + root.actionsSummary(modelData); color: th.mute; Layout.fillWidth: true } }
                                    Btn { compact: true; icon: "▶"; text: "Test"; onClicked: root.testAuto(modelData) }
                                    Btn { compact: true; kind: "ghost"; icon: modelData.state === "paused" ? "▶" : "❚❚"; onClicked: root.toggleAuto(modelData) }
                                    Btn { compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openWizard(modelData, false) }
                                }
                            }
                        }
                        Empty { visible: root.shown(root.automations).length === 0; icon: "◔"; title: "No automations"; message: "Create one from a template or start from scratch."
                            Btn { kind: "primary"; text: "Create automation"; onClicked: root.openWizard(null, false) } }
                    }
                    Card {
                        Layout.fillWidth: true
                        SecTitle { text: "Saved Space"; icon: "▤"; tone: th.cyan
                            Btn { compact: true; kind: "primary"; icon: "+"; text: "Quick Capture"; onClicked: root.openCapture("bookmark", null) }
                            Btn { compact: true; kind: "ghost"; text: "Open"; onClicked: root.go(1) } }
                        Flow { Layout.fillWidth: true; spacing: 6
                            Chip { text: root.countType("bookmark") + " BOOKMARKS"; tone: th.cyan }
                            Chip { text: root.countType("note") + " NOTES"; tone: th.lilac }
                            Chip { text: root.countType("snippet") + " SNIPPETS"; tone: th.teal }
                            Chip { text: root.collections.length + " COLLECTIONS"; tone: th.amber } }
                        GridLayout {
                            id: spg; Layout.fillWidth: true; columns: width > 520 ? 3 : 1; columnSpacing: 8; rowSpacing: 8
                            readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                            Repeater {
                                model: root.pinnedOrRecent()
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredWidth: spg.cw; Layout.alignment: Qt.AlignTop
                                    implicitHeight: pc.implicitHeight + 20; radius: 10; color: th.panelHi
                                    ColumnLayout { id: pc; x: 10; y: 10; width: parent.width - 20; spacing: 4
                                        RowLayout { spacing: 6
                                            Chip { text: modelData.type.toUpperCase(); tone: modelData.type === "bookmark" ? th.cyan : modelData.type === "note" ? th.lilac : th.teal }
                                            Spacer {}
                                            Lbl { visible: modelData.pinned; text: "⚑"; color: th.amber; font.pixelSize: 12 } }
                                        Lbl { text: modelData.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Mono { text: modelData.type === "bookmark" ? modelData.url : modelData.content; color: th.mute; Layout.fillWidth: true } }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: hg.rw; Layout.alignment: Qt.AlignTop; spacing: 14
                    Card {
                        Layout.fillWidth: true
                        SecTitle { text: "Device Bridge"; icon: "▯"; tone: th.cyan
                            Btn { compact: true; kind: "ghost"; text: "Open"; onClicked: root.go(5) } }
                        Repeater {
                            model: root.devices
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 48; radius: 10; color: th.panelHi
                                RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 10 } spacing: 8
                                    Lbl { text: "▯"; color: th.cyan; font.pixelSize: 18 }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                                        Lbl { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Mono { text: modelData.battery >= 0 ? "Battery " + modelData.battery + "%" : "Battery unknown"; color: th.mute } }
                                    Chip { text: root.devLabel(modelData.state).toUpperCase(); tone: root.devTone(modelData.state); dot: true } }
                            }
                        }
                        Rectangle {
                            visible: root.devices.length === 0
                            Layout.fillWidth: true; implicitHeight: 62; radius: 10; color: th.well
                            RowLayout { anchors { fill: parent; margins: 12 } spacing: 10
                                Lbl { text: "▯"; color: th.mute; font.pixelSize: 22 }
                                ColumnLayout { Layout.fillWidth: true; spacing: 1
                                    Lbl { text: "Not connected"; font.weight: Font.DemiBold }
                                    Wrap { text: "No device information has been supplied. Pairing and status come from the integration."; font.pixelSize: 11 } } }
                        }
                    }
                    Card {
                        Layout.fillWidth: true
                        SecTitle { text: "Workspace Presets"; icon: "▦"; tone: th.lilac
                            Btn { compact: true; kind: "ghost"; text: "Open"; onClicked: root.go(6) } }
                        GridLayout {
                            id: pg2; Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8
                            readonly property real cw: (width - columnSpacing) / 2
                            Repeater {
                                model: root.shown(root.presets).slice(0, 4)
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredWidth: pg2.cw; implicitHeight: ptc.implicitHeight + 20; radius: 10
                                    color: th.panelHi; border.width: 1; border.color: root.presetSel === modelData.id ? th.violet : "transparent"
                                    ColumnLayout { id: ptc; x: 10; y: 10; width: parent.width - 20; spacing: 6
                                        Lbl { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        LayoutPreview { Layout.fillWidth: true; implicitHeight: 40; blocks: modelData.layout }
                                        Btn { Layout.fillWidth: true; compact: true; text: root.presetSel === modelData.id ? "Selected" : "Activate"; onClicked: root.activatePreset(modelData) } }
                                }
                            }
                        }
                    }
                    Card {
                        Layout.fillWidth: true
                        SecTitle { text: "Recent Activity"; icon: "↺"; tone: th.teal
                            Btn { compact: true; kind: "ghost"; text: "Journal"; onClicked: root.go(7) } }
                        Repeater {
                            model: root.activityEvents.slice(0, 4)
                            RowLayout { Layout.fillWidth: true; spacing: 8
                                Rectangle { width: 8; height: 8; radius: 4; color: root.resTone(modelData.result) }
                                Lbl { text: modelData.name; Layout.fillWidth: true }
                                Mono { text: root.fmtTs(modelData.ts); color: th.mute } }
                        }
                        Empty { visible: root.activityEvents.length === 0; icon: "↺"; title: "No history yet"; message: "Runs reported by the backend will be listed here." }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- SAVED SPACE
    Component {
        id: savedPage
        PageScroll {
            id: sp
            Component.onCompleted: sq.text = root.savedQuery
            Connections { target: root; function onSavedQueryChanged() { if (sq.text !== root.savedQuery) sq.text = root.savedQuery } }

            PageHead {
                caps: "BOOKMARKS · NOTES · SNIPPETS"; title: "Saved Space"
                desc: "Instant retrieval for links, notes and command snippets. Saving a command never runs it."
                Chip { text: "IN-MEMORY ONLY"; tone: th.amber; Layout.alignment: Qt.AlignVCenter }
                Btn { kind: "primary"; icon: "+"; text: "Quick Capture"; onClicked: root.openCapture("bookmark", null) }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Field { id: sq; icon: "⌕"; placeholder: "Filter by title, URL, text, tag or collection…"; onTextChanged: root.savedQuery = text }
                Repeater {
                    model: [{ k: "recent", l: "Recent" }, { k: "az", l: "A–Z" }, { k: "pinned", l: "Pinned first" }]
                    Pill { text: modelData.l; active: root.savedSort === modelData.k; onClicked: root.savedSort = modelData.k }
                }
            }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [{ k: "all", l: "All" }, { k: "bookmark", l: "Bookmarks" }, { k: "note", l: "Notes" }, { k: "snippet", l: "Snippets" }, { k: "pinned", l: "Pinned" }, { k: "favorite", l: "Favorites" }]
                    Pill { text: modelData.l; count: root.countType(modelData.k); active: root.savedType === modelData.k; onClicked: root.savedType = modelData.k }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 14
                // collections
                Card {
                    visible: root.width > 900
                    Layout.preferredWidth: 220; Layout.alignment: Qt.AlignTop; gap: 4
                    SecTitle { text: "Collections"; icon: "▥"; tone: th.lilac
                        Btn { compact: true; kind: "ghost"; icon: "+"; onClicked: root.openCollDlg("new", "") } }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 32; radius: 8
                        color: root.savedColl === "" ? th.a(th.violet, 0.14) : "transparent"
                        RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            Lbl { text: "All items"; Layout.fillWidth: true }
                            Mono { text: root.countType("all"); color: th.mute } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.savedColl = "" }
                    }
                    Repeater {
                        model: root.collections
                        Rectangle {
                            id: crow
                            Layout.fillWidth: true; implicitHeight: 32; radius: 8
                            color: root.savedColl === modelData ? th.a(th.violet, 0.14) : (hv.hovered ? th.panelHi : "transparent")
                            HoverHandler { id: hv }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.savedColl = modelData }
                            RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 4 } spacing: 6
                                Rectangle { width: 8; height: 8; radius: 4; color: root.collTone(index) }
                                Lbl { text: modelData; Layout.fillWidth: true }
                                Btn { visible: hv.hovered; compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openCollDlg("rename", modelData) }
                                Btn { visible: hv.hovered; compact: true; kind: "ghost"; icon: "⌫"; onClicked: root.deleteCollAsk(modelData) }
                                Mono { visible: !hv.hovered; text: root.collCount(modelData); color: th.mute } }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 32; radius: 8
                        color: root.savedColl === "__none" ? th.a(th.violet, 0.14) : "transparent"
                        RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            Lbl { text: "Unsorted"; color: th.dim; Layout.fillWidth: true }
                            Mono { text: root.collCount("__none"); color: th.mute } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.savedColl = "__none" }
                    }
                }
                // items
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 10
                    Flow {
                        visible: root.width <= 900; Layout.fillWidth: true; spacing: 6
                        Pill { text: "All"; active: root.savedColl === ""; onClicked: root.savedColl = "" }
                        Repeater { model: root.collections; Pill { text: modelData; active: root.savedColl === modelData; onClicked: root.savedColl = modelData } }
                    }
                    GridLayout {
                        id: ig
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor(width / 300)); columnSpacing: 10; rowSpacing: 10
                        readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                        Repeater {
                            model: root.visibleItems()
                            Card {
                                id: ic
                                readonly property var it: modelData
                                readonly property color tone: it.type === "bookmark" ? th.cyan : it.type === "note" ? th.lilac : th.teal
                                Layout.fillWidth: true; Layout.preferredWidth: ig.cw; Layout.alignment: Qt.AlignTop; gap: 8
                                RowLayout { Layout.fillWidth: true; spacing: 6
                                    Chip { text: ic.it.type === "bookmark" ? "BOOKMARK" : ic.it.type === "note" ? "NOTE" : "SNIPPET"; tone: ic.tone }
                                    Chip { visible: ic.it.sample; text: "SAMPLE"; tone: th.mute }
                                    Chip { visible: ic.it.type === "snippet"; text: root.trustLabel(ic.it.trust).toUpperCase(); tone: root.trustTone(ic.it.trust); dot: true }
                                    Spacer {}
                                    Btn { compact: true; kind: "ghost"; icon: ic.it.favorite ? "★" : "☆"; tint: ic.it.favorite ? th.amber : "transparent"
                                          onClicked: root.savedItems = root.patched(root.savedItems, ic.it.id, { favorite: !ic.it.favorite }) }
                                    Btn { compact: true; kind: "ghost"; icon: "⚑"; tint: ic.it.pinned ? th.violet : "transparent"
                                          onClicked: root.savedItems = root.patched(root.savedItems, ic.it.id, { pinned: !ic.it.pinned }) } }
                                Lbl { text: ic.it.title; font.pixelSize: 14; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; maximumLineCount: 2; Layout.fillWidth: true }
                                Mono { visible: ic.it.type === "bookmark"; text: ic.it.url; color: th.cyan; Layout.fillWidth: true }
                                Wrap { visible: ic.it.type === "note"; text: ic.it.content; maximumLineCount: 4 }
                                Rectangle {
                                    visible: ic.it.type === "snippet"; Layout.fillWidth: true; implicitHeight: cmd.implicitHeight + 14; radius: 8; color: th.well
                                    Mono { id: cmd; x: 10; y: 7; width: parent.width - 20; text: "$ " + ic.it.content; color: ic.it.trust === "reviewed" ? th.teal : th.amber
                                           wrapMode: Text.WrapAnywhere; elide: Text.ElideNone; maximumLineCount: 3 }
                                }
                                Wrap { visible: ic.it.description !== ""; text: ic.it.description; color: th.mute; maximumLineCount: 2 }
                                Mono { visible: ic.it.type === "snippet" && ic.it.trust !== "reviewed"; Layout.fillWidth: true; color: th.amber; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                       text: "Stored only — not authorised to run. Execution needs a reviewed action." }
                                Flow { Layout.fillWidth: true; spacing: 4
                                    Chip { visible: ic.it.collection !== ""; text: ic.it.collection.toUpperCase(); tone: th.violet }
                                    Repeater { model: ic.it.tags; Mono { text: "#" + modelData; color: th.mute; font.pixelSize: 10 } } }
                                RowLayout { Layout.fillWidth: true; spacing: 4
                                    Btn { visible: ic.it.type === "bookmark"; compact: true; icon: "↗"; text: "Open"; onClicked: root.openUrl(ic.it.url) }
                                    Btn { compact: true; icon: "⧉"; text: ic.it.type === "bookmark" ? "Copy URL" : "Copy"
                                          onClicked: { root.copyText(ic.it.type === "bookmark" ? ic.it.url : ic.it.content); root.notify("Copied", ic.it.title, "ok") } }
                                    Spacer {}
                                    Btn { compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openCapture(ic.it.type, ic.it, null) }
                                    Btn { compact: true; kind: "ghost"; icon: "⌫"; onClicked: root.deleteItemAsk(ic.it) } }
                            }
                        }
                    }
                    Empty {
                        visible: root.visibleItems().length === 0
                        icon: "▤"; title: "Nothing matches"; message: "Adjust the filters, or capture something new."
                        Btn { kind: "primary"; icon: "+"; text: "Quick Capture"; onClicked: root.openCapture("bookmark", null) }
                    }
                    Card {
                        Layout.fillWidth: true; pad: 12
                        RowLayout { Layout.fillWidth: true; spacing: 10
                            Lbl { text: "◈"; color: th.teal; font.pixelSize: 18 }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                Lbl { text: "Zero-execution principle"; font.weight: Font.DemiBold }
                                Wrap { text: "Snippets are references. Saving, opening or copying never executes them; running anything is a separate, reviewed action in the Action Library." } } }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- AUTOMATIONS
    Component {
        id: autoPage
        PageScroll {
            PageHead {
                caps: "SCHEDULES & TRIGGERS"; title: "Automations"
                desc: "Define when reviewed actions should run. This prototype stores definitions only — no timers are created."
                Btn { text: "Templates"; icon: "⎘"; onClicked: tplCard.visible = !tplCard.visible }
                Btn { kind: "primary"; icon: "+"; text: "Create Automation"; onClicked: root.openWizard(null, false) }
            }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [{ k: "all", l: "All Automations" }, { k: "active", l: "Active" }, { k: "upcoming", l: "Upcoming" }, { k: "paused", l: "Paused" }, { k: "history", l: "Execution History" }]
                    Pill { text: modelData.l; count: modelData.k === "history" ? root.activityEvents.length : root.autoCount(modelData.k)
                           active: root.autoFilter === modelData.k; onClicked: root.autoFilter = modelData.k }
                }
            }
            Card {
                id: tplCard
                visible: false; Layout.fillWidth: true
                SecTitle { text: "Templates"; icon: "⎘"; tone: th.cyan }
                Wrap { text: "Templates open the editor with a draft. They are not active schedules." }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: root.automationTemplates()
                        Pill { text: modelData.name; icon: root.isPowerAuto(modelData) ? "⏻" : "◔"; tone: root.isPowerAuto(modelData) ? th.red : th.lilac
                               onClicked: { tplCard.visible = false; root.openWizard(modelData, true) } } } }
            }
            GridLayout {
                id: ag
                visible: root.autoFilter !== "history"
                Layout.fillWidth: true
                columns: width > 760 ? 2 : 1; columnSpacing: 12; rowSpacing: 12
                readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                Repeater {
                    model: root.visibleAutos()
                    Card {
                        id: ac
                        readonly property var a: modelData
                        readonly property bool power: root.isPowerAuto(a)
                        readonly property bool exp: !!root.expandedAuto[a.id]
                        Layout.fillWidth: true; Layout.preferredWidth: ag.cw; Layout.alignment: Qt.AlignTop
                        border.color: power ? th.a(th.red, 0.35) : "#252936"
                        RowLayout { Layout.fillWidth: true; spacing: 10
                            Rectangle { Layout.preferredWidth: 34; Layout.preferredHeight: 34; radius: 9; color: th.a(ac.power ? th.red : th.cyan, 0.14)
                                Lbl { anchors.centerIn: parent; text: ac.power ? "⏻" : root.trigIcon(ac.a); color: ac.power ? th.red : th.cyan; font.pixelSize: 15 } }
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                Lbl { text: ac.a.name; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                Mono { text: root.trigSummary(ac.a); color: th.mute; Layout.fillWidth: true } }
                            Toggle { checked: ac.a.state !== "paused"; onToggled: root.toggleAuto(ac.a) } }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Chip { text: root.stateLabel(ac.a.state).toUpperCase(); tone: root.stateTone(ac.a.state); dot: true }
                            Chip { visible: ac.a.sample; text: "SAMPLE"; tone: th.mute }
                            Chip { visible: root.unsupportedTrigger(ac.a.ttype); text: "TRIGGER NEEDS INTEGRATION"; tone: th.amber }
                            Spacer {} }
                        Rectangle {
                            visible: ac.power; Layout.fillWidth: true; implicitHeight: pw.implicitHeight + 16; radius: 8; color: th.a(th.redDeep, 0.35)
                            ColumnLayout { id: pw; x: 10; y: 8; width: parent.width - 20; spacing: 1
                                Cap { text: "⚠ CONSEQUENTIAL POWER ACTION"; color: th.red }
                                Wrap { text: ac.a.confirm || true ? "Needs confirmation with a " + ac.a.grace + " s cancel window." : ""; font.pixelSize: 11 } } }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 30; radius: 8; color: th.well
                            RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                Cap { text: "NEXT RUN" }
                                Spacer {}
                                Mono { text: ac.a.nextRun !== "" ? ac.a.nextRun : "Not scheduled — supplied by backend"; color: ac.a.nextRun !== "" ? th.teal : th.mute } } }
                        Flow { Layout.fillWidth: true; spacing: 4
                            Repeater { model: ac.a.actions
                                Rectangle { implicitHeight: 22; implicitWidth: al.implicitWidth + 16; radius: 6; color: th.raised
                                    Lbl { id: al; anchors.centerIn: parent; text: root.actionName(modelData); font.pixelSize: 11; color: th.dim } } } }
                        Mono { visible: ac.a.lastResult !== ""; text: "Last result: " + ac.a.lastResult; color: ac.a.state === "failed" ? th.red : th.mute; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                        Item {
                            Layout.fillWidth: true; clip: true
                            Layout.preferredHeight: ac.exp ? det.implicitHeight + 4 : 0
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                            ColumnLayout { id: det; width: parent.width; spacing: 4
                                Rule {}
                                Wrap { text: ac.a.description !== "" ? ac.a.description : "No description." }
                                Mono { text: "Confirm: " + (ac.a.confirm ? "yes" : "no") + " · Notify: " + (ac.a.notify ? "yes" : "no") + " · Stop on failure: " + (ac.a.stopOnFail ? "yes" : "no"); color: th.mute; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                                Mono { text: "Conditions: " + (ac.a.conds.length ? ac.a.conds.join(", ") : "none"); color: th.mute; Layout.fillWidth: true } } }
                        RowLayout { Layout.fillWidth: true; spacing: 4
                            Btn { visible: !ac.power; compact: true; icon: "▶"; text: "Run / Test"; onClicked: root.testAuto(ac.a) }
                            Btn { visible: ac.power; compact: true; kind: "danger"; icon: "✕"; text: "Cancel schedule"
                                  onClicked: { root.automations = root.patched(root.automations, ac.a.id, { state: "paused" }); root.scheduleCancelRequested(ac.a.id); root.notify("Schedule cancelled (UI only)", ac.a.name + " is paused. A backend must remove any real timer.", "warn") } }
                            Spacer {}
                            Btn { compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openWizard(ac.a, false) }
                            Btn { compact: true; kind: "ghost"; icon: "⧉"; onClicked: root.dupAuto(ac.a) }
                            Btn { compact: true; kind: "ghost"; icon: ac.exp ? "▴" : "ⓘ"; onClicked: root.expandedAuto = root.flip(root.expandedAuto, ac.a.id) }
                            Btn { compact: true; kind: "ghost"; icon: "⌫"; onClicked: root.delAutoAsk(ac.a) } }
                    }
                }
            }
            Empty { visible: root.autoFilter !== "history" && root.visibleAutos().length === 0; icon: "◔"; title: "No automations here"; message: "Create one, or start from a template."
                Btn { kind: "primary"; text: "Create Automation"; onClicked: root.openWizard(null, false) } }
            Card {
                visible: root.autoFilter === "history"; Layout.fillWidth: true
                SecTitle { text: "Execution History"; icon: "↺"; tone: th.teal }
                Repeater {
                    model: root.activityEvents
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Chip { text: root.resLabel(modelData.result).toUpperCase(); tone: root.resTone(modelData.result) }
                        Lbl { text: modelData.name; Layout.fillWidth: true }
                        Mono { text: root.fmtTs(modelData.ts); color: th.mute } }
                }
                Empty { visible: root.activityEvents.length === 0; icon: "↺"; title: "No execution history"; message: "Runs reported by a backend will appear here." }
            }
        }
    }

    // ---------------------------------------------------------- ACTION LIBRARY
    Component {
        id: actionPage
        PageScroll {
            PageHead {
                caps: "REVIEWED DESKTOP ACTIONS"; title: "Action Library"
                desc: "A catalogue of named actions. Availability is reported by the backend; arbitrary commands are not executable from here."
                Btn { kind: "primary"; icon: "+"; text: "Custom Action"; onClicked: root.openActionEditor(null) }
            }
            Field { icon: "⌕"; placeholder: "Search actions…"; Component.onCompleted: text = root.actQuery; onTextChanged: root.actQuery = text }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Pill { text: "All"; count: root.catCount("All"); active: root.actCat === "All"; onClicked: root.actCat = "All" }
                Repeater { model: root.actionCategories; Pill { text: modelData; count: root.catCount(modelData); active: root.actCat === modelData; onClicked: root.actCat = modelData } }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 10
                    GridLayout {
                        id: lg
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor(width / 320)); columnSpacing: 10; rowSpacing: 10
                        readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                        Repeater {
                            model: root.filteredActions()
                            Card {
                                id: lc2
                                readonly property var a: modelData
                                Layout.fillWidth: true; Layout.preferredWidth: lg.cw; Layout.alignment: Qt.AlignTop; gap: 8
                                border.color: root.inspId === a.id ? th.violet : "#252936"
                                opacity: a.enabled ? 1 : 0.6
                                RowLayout { Layout.fillWidth: true
                                    Lbl { text: a.name; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                    Chip { text: root.backendOk(a.id) ? "AVAILABLE" : "UNAVAILABLE"; tone: root.backendOk(a.id) ? th.teal : th.mute; dot: true } }
                                Wrap { text: a.purpose }
                                Flow { Layout.fillWidth: true; spacing: 4
                                    Chip { text: a.category.toUpperCase(); tone: th.violet }
                                    Chip { text: root.trustLabel(a.trust).toUpperCase(); tone: root.trustTone(a.trust); dot: true }
                                    Chip { visible: a.confirm; text: "CONFIRMS"; tone: th.amber }
                                    Chip { visible: !a.enabled; text: "DISABLED"; tone: th.mute }
                                    Chip { visible: a.sample; text: "SAMPLE"; tone: th.mute } }
                                RowLayout { Layout.fillWidth: true; spacing: 4
                                    Btn { compact: true; text: "Inspect"; onClicked: root.inspId = root.inspId === a.id ? "" : a.id }
                                    Btn { compact: true; kind: "primary"; icon: "▶"; text: "Run"; onClicked: root.runAction(a) }
                                    Spacer {}
                                    Btn { compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openActionEditor(a) }
                                    Btn { compact: true; kind: "ghost"; icon: "⧉"; onClicked: root.dupAction(a) }
                                    Btn { compact: true; kind: "ghost"; icon: a.enabled ? "⊘" : "✓"; onClicked: root.actionsData = root.patched(root.actionsData, a.id, { enabled: !a.enabled }) } }
                            }
                        }
                    }
                    Empty { visible: root.filteredActions().length === 0; icon: "⌘"; title: "No actions found"
                        message: root.actCat === "Custom Actions" ? "You haven’t defined any custom actions yet." : "Try another search or category."
                        Btn { kind: "primary"; text: "Create custom action"; onClicked: root.openActionEditor(null) } }
                }
                // inspector
                Item {
                    id: insp
                    readonly property var a: root.actionObj(root.inspId)
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: root.inspId !== "" ? 320 : 0
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                    implicitHeight: ic3.implicitHeight
                    clip: true; visible: root.inspId !== "" || width > 2
                    Card {
                        id: ic3
                        width: 320; gap: 8
                        SecTitle { text: insp.a ? insp.a.name : ""; icon: "ⓘ"; tone: th.cyan
                            Btn { compact: true; kind: "ghost"; icon: "✕"; onClicked: root.inspId = "" } }
                        Wrap { text: insp.a ? insp.a.description : "" }
                        Cap { text: "REFERENCE" }
                        Mono { text: insp.a ? insp.a.ref : ""; color: th.cyan; Layout.fillWidth: true }
                        Cap { text: "PARAMETERS" }
                        Repeater { model: insp.a ? insp.a.params : []
                            RowLayout { Layout.fillWidth: true
                                Mono { text: modelData.k; color: th.dim }
                                Spacer {}
                                Mono { text: modelData.v !== "" ? modelData.v : "—"; color: th.mute } } }
                        Mono { visible: insp.a && insp.a.params.length === 0; text: "None"; color: th.mute }
                        Cap { visible: insp.a && insp.a.args !== ""; text: "ARGUMENTS" }
                        Mono { visible: insp.a && insp.a.args !== ""; text: insp.a ? insp.a.args : ""; color: th.dim; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                        Cap { visible: insp.a && insp.a.cwd !== ""; text: "WORKING DIRECTORY" }
                        Mono { visible: insp.a && insp.a.cwd !== ""; text: insp.a ? insp.a.cwd : ""; color: th.dim; Layout.fillWidth: true }
                        Wrap { text: insp.a && insp.a.trust !== "reviewed" ? "This action is not Reviewed, so Run is blocked." : "Reviewed actions still only emit a run request."; color: th.mute; font.pixelSize: 11 }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- ROUTINE BUILDER
    Component {
        id: routinePage
        PageScroll {
            id: rp
            readonly property var r: root.curRoutine()
            function load() { var x = root.curRoutine(); rName.text = x ? x.name : ""; rDesc.text = x ? x.description : ""; rSched.text = x ? x.schedule : "" }
            Component.onCompleted: load()
            Connections { target: root; function onRtSelIdChanged() { rp.load() } }

            PageHead {
                caps: "MULTI-STEP WORKFLOWS"; title: "Routine Builder"
                desc: "Combine reviewed actions into an ordered workflow. Templates are editable examples — nothing runs automatically."
                Btn { kind: "primary"; icon: "+"; text: "New Workflow"; onClicked: root.newRoutine() }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                Card {
                    visible: root.width > 820
                    Layout.preferredWidth: 240; Layout.alignment: Qt.AlignTop; gap: 6
                    SecTitle { text: "Workflows"; icon: "⎇"; tone: th.lilac }
                    Repeater {
                        model: root.shown(root.routines)
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 52; radius: 9
                            color: root.rtSelId === modelData.id ? th.a(th.violet, 0.14) : (rma.containsMouse ? th.panelHi : "transparent")
                            ColumnLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 8 } spacing: 2
                                Item { Layout.fillHeight: true }
                                RowLayout { spacing: 6
                                    Lbl { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                    Chip { visible: modelData.sample; text: "SAMPLE"; tone: th.mute } }
                                Mono { text: modelData.steps.length + " steps · " + (modelData.enabled ? "enabled" : "disabled"); color: th.mute }
                                Item { Layout.fillHeight: true } }
                            MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rtSelId = modelData.id }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 12
                    Flow {
                        visible: root.width <= 820; Layout.fillWidth: true; spacing: 6
                        Repeater { model: root.shown(root.routines); Pill { text: modelData.name; active: root.rtSelId === modelData.id; onClicked: root.rtSelId = modelData.id } }
                    }
                    Empty { visible: !rp.r; icon: "⎇"; title: "No workflow selected"; message: "Create a workflow to start building steps."
                        Btn { kind: "primary"; text: "New Workflow"; onClicked: root.newRoutine() } }
                    Card {
                        visible: !!rp.r; Layout.fillWidth: true; gap: 8
                        RowLayout { Layout.fillWidth: true; spacing: 8
                            Field { id: rName; placeholder: "Workflow name"; onTextChanged: if (rp.r && text !== rp.r.name) root.editRoutine(root.rtSelId, function (x) { x.name = text }) }
                            Chip { visible: !!rp.r && rp.r.sample; text: "SAMPLE TEMPLATE"; tone: th.mute }
                            Lbl { text: "Enabled"; color: th.dim; font.pixelSize: 12 }
                            Toggle { checked: !!rp.r && rp.r.enabled; onToggled: root.editRoutine(root.rtSelId, function (x) { x.enabled = value }) } }
                        Field { id: rDesc; placeholder: "Description"; onTextChanged: if (rp.r && text !== rp.r.description) root.editRoutine(root.rtSelId, function (x) { x.description = text }) }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Cap { text: "TRIGGER" }
                            Pill { text: "Manual"; active: !!rp.r && rp.r.trigger === "manual"; onClicked: root.editRoutine(root.rtSelId, function (x) { x.trigger = "manual" }) }
                            Pill { text: "Scheduled"; active: !!rp.r && rp.r.trigger === "scheduled"; onClicked: root.editRoutine(root.rtSelId, function (x) { x.trigger = "scheduled" }) }
                            Field { id: rSched; visible: !!rp.r && rp.r.trigger === "scheduled"; placeholder: "e.g. Weekdays 09:00"
                                    onTextChanged: if (rp.r && text !== rp.r.schedule) root.editRoutine(root.rtSelId, function (x) { x.schedule = text }) }
                            Spacer { visible: !rp.r || rp.r.trigger !== "scheduled" } }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Cap { text: "ON FAILURE" }
                            Pill { text: "Stop workflow"; active: !!rp.r && rp.r.onFail === "stop"; tone: th.red; onClicked: root.editRoutine(root.rtSelId, function (x) { x.onFail = "stop" }) }
                            Pill { text: "Continue"; active: !!rp.r && rp.r.onFail === "continue"; tone: th.teal; onClicked: root.editRoutine(root.rtSelId, function (x) { x.onFail = "continue" }) }
                            Spacer {}
                            Mono { visible: !!rp.r; text: "History: " + (rp.r ? root.routineHistory(rp.r) : 0) + " runs"; color: th.mute } }
                    }
                    Card {
                        visible: !!rp.r; Layout.fillWidth: true; gap: 6
                        SecTitle { text: "Steps"; icon: "☰"; tone: th.cyan
                            Btn { compact: true; icon: "+"; text: "Add step"; onClicked: root.stepAddOpen = !root.stepAddOpen } }
                        Flow {
                            visible: root.stepAddOpen; Layout.fillWidth: true; spacing: 5
                            Repeater { model: root.actionsData
                                Pill { text: modelData.name; icon: modelData.category === "Power" ? "⏻" : ""; tone: modelData.category === "Power" ? th.red : th.cyan
                                       onClicked: { root.addStep(modelData.id); root.stepAddOpen = false } } } }
                        Repeater {
                            model: rp.r ? rp.r.steps : []
                            ColumnLayout {
                                id: sr
                                readonly property var st: modelData
                                readonly property bool open: !!root.stepOpen[st.id]
                                Layout.fillWidth: true; spacing: 0
                                Rectangle { visible: index > 0; Layout.preferredWidth: 2; Layout.preferredHeight: 10; Layout.leftMargin: 23; color: th.line }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: sc.implicitHeight + 20; radius: 10; color: th.panelHi
                                    border.width: 1; border.color: root.actionObj(sr.st.actionId) && root.actionObj(sr.st.actionId).category === "Power" ? th.a(th.red, 0.4) : "transparent"
                                    ColumnLayout { id: sc; x: 10; y: 10; width: parent.width - 20; spacing: 6
                                        RowLayout { Layout.fillWidth: true; spacing: 8
                                            Rectangle { Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13; color: th.a(th.violet, 0.2)
                                                Mono { anchors.centerIn: parent; text: index + 1; color: th.lilac; font.bold: true } }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                                Lbl { text: root.actionName(sr.st.actionId); font.weight: Font.DemiBold; Layout.fillWidth: true }
                                                Mono { color: th.mute; Layout.fillWidth: true
                                                    text: (sr.st.cond === "always" ? "Always runs" : sr.st.cond === "integration" ? "Only if integration available" : "Only if previous step succeeded") + (sr.st.note !== "" ? " · " + sr.st.note : "") } }
                                            Btn { compact: true; kind: "ghost"; icon: "▲"; enabled: index > 0; onClicked: root.moveStep(index, -1) }
                                            Btn { compact: true; kind: "ghost"; icon: "▼"; enabled: index < (rp.r ? rp.r.steps.length : 0) - 1; onClicked: root.moveStep(index, 1) }
                                            Btn { compact: true; kind: "ghost"; icon: "✎"; active: sr.open; onClicked: root.stepOpen = root.flip(root.stepOpen, sr.st.id) }
                                            Btn { compact: true; kind: "ghost"; icon: "⧉"; onClicked: root.dupStep(index) }
                                            Btn { compact: true; kind: "ghost"; icon: "✕"; onClicked: root.delStep(index) } }
                                        Item {
                                            Layout.fillWidth: true; clip: true
                                            Layout.preferredHeight: sr.open ? ed.implicitHeight + 2 : 0
                                            Behavior on Layout.preferredHeight { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                                            ColumnLayout { id: ed; width: parent.width; spacing: 6
                                                Field { placeholder: "Step note (optional)"; Component.onCompleted: text = sr.st.note
                                                        onTextChanged: if (text !== sr.st.note) root.patchStep(index, { note: text }) }
                                                Flow { Layout.fillWidth: true; spacing: 5
                                                    Pill { text: "Always"; active: sr.st.cond === "always"; onClicked: root.patchStep(index, { cond: "always" }) }
                                                    Pill { text: "If integration available"; active: sr.st.cond === "integration"; onClicked: root.patchStep(index, { cond: "integration" }) }
                                                    Pill { text: "If previous succeeded"; active: sr.st.cond === "prev_ok"; onClicked: root.patchStep(index, { cond: "prev_ok" }) } } } }
                                    }
                                }
                            }
                        }
                        Empty { visible: !rp.r || rp.r.steps.length === 0; icon: "☰"; title: "No steps yet"; message: "Add a reviewed action to begin." }
                    }
                    RowLayout {
                        visible: !!rp.r; Layout.fillWidth: true; spacing: 8
                        Btn { kind: "ghost"; icon: "⌫"; text: "Delete"; onClicked: root.delRoutineAsk(rp.r) }
                        Spacer {}
                        Btn { icon: "◎"; text: "Preview"; onClicked: root.previewRoutine(rp.r) }
                        Btn { kind: "primary"; icon: "✓"; text: "Save workflow"; onClicked: { root.workflowSaved(rp.r); root.notify("Workflow saved (UI only)", rp.r.name + " is stored in memory.", "ok") } }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- DEVICE BRIDGE
    Component {
        id: devicePage
        PageScroll {
            readonly property var devs: root.allDevices()
            PageHead {
                caps: "KDE CONNECT · SCRCPY"; title: "Device Bridge"
                desc: "Dynamic device cards and shortcuts. States come from a real integration — nothing is shown as connected until it reports so."
                Btn { icon: "◎"; text: root.previewDevices ? "Hide layout preview" : "Layout preview"; active: root.previewDevices; onClicked: root.previewDevices = !root.previewDevices }
            }
            Card {
                Layout.fillWidth: true
                SecTitle { text: "Devices"; icon: "▯"; tone: th.cyan }
                GridLayout {
                    id: dg; Layout.fillWidth: true; columns: width > 700 ? 2 : 1; columnSpacing: 10; rowSpacing: 10
                    readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                    Repeater {
                        model: devs
                        Rectangle {
                            id: dc
                            readonly property var d: modelData
                            Layout.fillWidth: true; Layout.preferredWidth: dg.cw; Layout.alignment: Qt.AlignTop
                            implicitHeight: dcol.implicitHeight + 24; radius: 10; color: th.panelHi
                            border.width: 1; border.color: root.devSel === d.id ? th.violet : "transparent"
                            ColumnLayout { id: dcol; x: 12; y: 12; width: parent.width - 24; spacing: 6
                                RowLayout { Layout.fillWidth: true; spacing: 10
                                    Lbl { text: "▯"; color: th.cyan; font.pixelSize: 24 }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                                        Lbl { text: dc.d.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                        Mono { color: th.mute; text: (dc.d.battery >= 0 ? "Battery " + dc.d.battery + "%" : "Battery unknown") + " · " + (dc.d.lastSeen !== "" ? "Last seen " + dc.d.lastSeen : "Last seen unknown") } }
                                    Chip { visible: !!dc.d.preview; text: "PREVIEW"; tone: th.mute }
                                    Chip { text: root.devLabel(dc.d.state).toUpperCase(); tone: root.devTone(dc.d.state); dot: true } }
                                Flow { Layout.fillWidth: true; spacing: 4
                                    Repeater { model: dc.d.capabilities || []; Mono { text: "· " + modelData; color: th.mute; font.pixelSize: 10 } } }
                                Btn { compact: true; text: root.devSel === dc.d.id ? "Selected" : "Select device"; onClicked: root.devSel = dc.d.id } }
                        }
                    }
                }
                Empty { visible: devs.length === 0; icon: "▯"; title: "No device supplied"; message: "When an integration reports devices they appear here with their real pairing state and battery." }
            }
            Card {
                Layout.fillWidth: true; gap: 8
                SecTitle { text: "Connection states"; icon: "◈"; tone: th.lilac }
                GridLayout {
                    Layout.fillWidth: true; columns: width > 700 ? 4 : 2; columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: [{ s: "disconnected", t: "A known device that isn’t reachable right now." }, { s: "pairing", t: "The device must be paired in the integration first." },
                                { s: "unavailable", t: "No integration or service is available." }, { s: "connected", t: "Shown only when an integration reports it." }]
                        Rectangle { Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: sl.implicitHeight + 20; radius: 8; color: th.well
                            ColumnLayout { id: sl; x: 10; y: 10; width: parent.width - 20; spacing: 4
                                Chip { text: root.devLabel(modelData.s).toUpperCase(); tone: root.devTone(modelData.s); dot: true }
                                Wrap { text: modelData.t; font.pixelSize: 11 } } }
                    }
                }
            }
            Card {
                Layout.fillWidth: true; gap: 8
                SecTitle { text: "Actions"; icon: "⌘"; tone: th.cyan }
                Wrap { text: "Actions need a selected, connected device. Without one they explain why instead of pretending to work." }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [{ k: "mirror", l: "Launch Device Mirror", i: "▭" }, { k: "profile", l: "Open scrcpy profile", i: "⚙" }, { k: "file", l: "Send file", i: "⇧" },
                                { k: "share", l: "Share URL / text", i: "↗" }, { k: "notifications", l: "Notification summary", i: "◉" }, { k: "find", l: "Find phone", i: "♪" }, { k: "command", l: "Predefined command", i: "⌘" }, { k: "settings", l: "Device settings", i: "⚙" }]
                        Btn { icon: modelData.i; text: modelData.l; onClicked: root.devRequest(modelData.k, modelData.l) }
                    }
                }
            }
            Card {
                Layout.fillWidth: true; gap: 6
                SecTitle { text: "Shared Link Inbox"; icon: "✉"; tone: th.lilac }
                Repeater {
                    model: root.allLinks()
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 52; radius: 10; color: th.panelHi
                        RowLayout { anchors { fill: parent; leftMargin: 10; rightMargin: 8 } spacing: 6
                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                RowLayout { spacing: 6
                                    Lbl { text: modelData.title !== "" ? modelData.title : modelData.url; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                    Chip { visible: !!modelData.preview; text: "PREVIEW"; tone: th.mute } }
                                Mono { color: th.mute; Layout.fillWidth: true
                                    text: modelData.url + (modelData.source ? " · " + modelData.source : "") + (modelData.received ? " · " + modelData.received : "") } }
                            Btn { compact: true; icon: "↗"; text: "Open"; onClicked: root.openUrl(modelData.url) }
                            Btn { compact: true; icon: "▤"; text: "Save"; onClicked: root.openCapture("bookmark", null, { title: modelData.title, url: modelData.url }) }
                            Btn { compact: true; kind: "ghost"; icon: "⧉"; onClicked: { root.copyText(modelData.url); root.notify("Copied", modelData.url, "ok") } }
                            Btn { compact: true; kind: "ghost"; icon: "✕"; onClicked: { root.dismissedLinks = root.dismissedLinks.concat([modelData.id]); root.sharedLinkDismissed(modelData.id) } } }
                    }
                }
                Empty { visible: root.allLinks().length === 0; icon: "✉"; title: "No shared links"; message: "Links sent from a phone will be listed with source and time when the integration provides them." }
            }
        }
    }

    // ---------------------------------------------------------- WORKSPACE PRESETS
    Component {
        id: presetPage
        PageScroll {
            PageHead {
                caps: "DESKTOP CONTEXT PROFILES"; title: "Workspace Presets"
                desc: "Layout and focus definitions for future integration. Activating only sends a request; no windows are moved or launched."
            }
            GridLayout {
                id: prg; Layout.fillWidth: true
                columns: Math.max(1, Math.floor(width / 320)); columnSpacing: 12; rowSpacing: 12
                readonly property real cw: (width - (columns - 1) * columnSpacing) / columns
                Repeater {
                    model: root.shown(root.presets)
                    Card {
                        id: pc2
                        readonly property var p: modelData
                        Layout.fillWidth: true; Layout.preferredWidth: prg.cw; Layout.alignment: Qt.AlignTop; gap: 8
                        border.color: root.presetSel === p.id ? th.violet : "#252936"
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Lbl { text: p.name; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            Chip { visible: p.sample; text: "SAMPLE"; tone: th.mute }
                            Chip { visible: root.presetSel === p.id; text: "SELECTED"; tone: th.violet; dot: true } }
                        Wrap { text: p.description }
                        LayoutPreview { Layout.fillWidth: true; implicitHeight: 92; blocks: p.layout }
                        Flow { Layout.fillWidth: true; spacing: 4
                            Repeater { model: p.apps; Chip { text: modelData.toUpperCase(); tone: th.cyan } }
                            Mono { visible: p.apps.length === 0; text: "No applications"; color: th.mute } }
                        Flow { Layout.fillWidth: true; spacing: 4
                            Chip { visible: p.dnd; text: "DO NOT DISTURB"; tone: th.amber }
                            Chip { visible: p.timer !== "none"; text: "FOCUS TIMER " + p.timer + " MIN"; tone: th.teal } }
                        RowLayout { Layout.fillWidth: true; spacing: 4
                            Btn { kind: "primary"; compact: true; icon: "▶"; text: "Activate"; onClicked: root.activatePreset(p) }
                            Spacer {}
                            Btn { compact: true; kind: "ghost"; icon: "✎"; onClicked: root.openPresetEditor(p) }
                            Btn { compact: true; kind: "ghost"; icon: "⧉"; onClicked: root.dupPreset(p) } }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- ACTIVITY & HISTORY
    Component {
        id: historyPage
        PageScroll {
            readonly property var evs: root.visibleEvents()
            PageHead {
                caps: "EXECUTION VISIBILITY"; title: "Activity & History"
                desc: "A journal of action and automation runs reported by a backend. Passwords and tokens are never displayed."
                Btn { icon: "◎"; text: root.previewActivity ? "Hide sample entries" : "Show sample entries"; active: root.previewActivity; onClicked: root.previewActivity = !root.previewActivity }
            }
            Card {
                Layout.fillWidth: true; gap: 8
                Flow { Layout.fillWidth: true; spacing: 6
                    Cap { text: "STATUS"; height: 28; verticalAlignment: Text.AlignVCenter }
                    Repeater { model: [{ k: "all", l: "All" }, { k: "completed", l: "Completed" }, { k: "failed", l: "Failed" }, { k: "cancelled", l: "Cancelled" }, { k: "review", l: "Needs Review" }]
                        Pill { text: modelData.l; active: root.histStatus === modelData.k; onClicked: root.histStatus = modelData.k } } }
                Flow { Layout.fillWidth: true; spacing: 6
                    Cap { text: "DATE"; height: 28; verticalAlignment: Text.AlignVCenter }
                    Repeater { model: [{ k: "any", l: "Any time" }, { k: "24h", l: "Last 24 h" }, { k: "7d", l: "Last 7 days" }]
                        Pill { text: modelData.l; active: root.histRange === modelData.k; onClicked: root.histRange = modelData.k } } }
                Flow { Layout.fillWidth: true; spacing: 6
                    Cap { text: "CATEGORY"; height: 28; verticalAlignment: Text.AlignVCenter }
                    Repeater { model: root.distinct("category"); Pill { text: modelData; active: root.histCat === modelData; onClicked: root.histCat = modelData } } }
                Flow { Layout.fillWidth: true; spacing: 6
                    Cap { text: "AUTOMATION"; height: 28; verticalAlignment: Text.AlignVCenter }
                    Repeater { model: root.distinct("automation"); Pill { text: modelData; active: root.histAuto === modelData; onClicked: root.histAuto = modelData } } }
            }
            Card {
                Layout.fillWidth: true; gap: 4
                SecTitle { text: evs.length + " entries"; icon: "↺"; tone: th.teal }
                Repeater {
                    model: evs
                    ColumnLayout {
                        id: er
                        readonly property var e: modelData
                        readonly property bool open: !!root.expandedEvt[e.id]
                        Layout.fillWidth: true; spacing: 0
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 42; radius: 8; color: ema.containsMouse ? th.panelHi : "transparent"
                            RowLayout { anchors { fill: parent; leftMargin: 8; rightMargin: 8 } spacing: 10
                                Rectangle { width: 8; height: 8; radius: 4; color: root.resTone(er.e.result) }
                                Lbl { text: er.e.name; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                Chip { visible: !!er.e.sample; text: "SAMPLE"; tone: th.mute }
                                Mono { visible: root.width > 760; text: er.e.trigger; color: th.mute }
                                Chip { text: root.resLabel(er.e.result).toUpperCase(); tone: root.resTone(er.e.result) }
                                Mono { visible: root.width > 760 && er.e.duration !== ""; text: er.e.duration; color: th.mute }
                                Mono { text: root.fmtTs(er.e.ts); color: th.mute }
                                Lbl { text: er.open ? "▴" : "▾"; color: th.mute } }
                            MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.expandedEvt = root.flip(root.expandedEvt, er.e.id) }
                        }
                        Item {
                            Layout.fillWidth: true; clip: true
                            Layout.preferredHeight: er.open ? ed2.implicitHeight + 8 : 0
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
                            ColumnLayout { id: ed2; x: 26; width: parent.width - 34; spacing: 2
                                Wrap { text: er.e.details !== "" ? er.e.details : "No further details were supplied." }
                                Mono { color: th.mute; Layout.fillWidth: true
                                    text: "Category: " + er.e.category + (er.e.automation ? " · Automation: " + er.e.automation : "") } }
                        }
                    }
                }
                Empty { visible: evs.length === 0; icon: "↺"; title: root.allEvents().length === 0 ? "No history yet" : "No entries match"
                    message: root.allEvents().length === 0 ? "When actions or automations run, the backend reports them here. Nothing is fabricated." : "Change the filters to see more." }
            }
            Mono { text: "Retention preference: " + (root.settings.retention > 0 ? root.settings.retention + " days" : "keep forever") + " (enforced by the backend)."; color: th.mute; Layout.fillWidth: true }
        }
    }

    // ======================= DIALOGS ========================================
    function pinnedOrRecent() {
        var s = shown(savedItems), p = [], r = []
        for (var i = 0; i < s.length; i++) { if (s[i].pinned) p.push(s[i]); else r.push(s[i]) }
        return p.concat(r).slice(0, 3)
    }

    // ---- confirm
    Modal {
        id: confirmDlg
        animMs: root.animMs; dlgWidth: 440; title: root.cfTitle
        onDismissed: open = false
        Wrap { text: root.cfMsg; color: th.dim; font.pixelSize: 13 }
        footer: [ Spacer {}, Btn { text: "Cancel"; onClicked: confirmDlg.open = false },
                  Btn { kind: root.cfDanger ? "danger" : "primary"; text: root.cfLabel; onClicked: { confirmDlg.open = false; if (root.cfFn) root.cfFn() } } ]
    }

    // ---- preview
    Modal {
        id: pvDlg
        animMs: root.animMs; dlgWidth: 480; title: root.pvTitle; subtitle: "Preview only"
        onDismissed: open = false
        Repeater { model: root.pvSteps; Lbl { text: modelData; Layout.fillWidth: true; color: th.text; font.family: "JetBrains Mono"; font.pixelSize: 12 } }
        Mono { visible: root.pvSteps.length === 0; text: "No steps."; color: th.mute }
        Wrap { text: root.pvNote; color: th.amber }
        footer: [ Spacer {}, Btn { text: "Close"; onClicked: pvDlg.open = false },
                  Btn { visible: root.pvAllow; kind: "primary"; icon: "▶"; text: "Request test run"
                        onClicked: { pvDlg.open = false; root.automationTestRequested(root.pvId); root.sysRequest("Test run") } } ]
    }

    // ---- quick capture
    Modal {
        id: capDlg
        animMs: root.animMs; dlgWidth: 600
        title: root.capEditId !== "" ? "Edit item" : "Quick Capture"
        subtitle: "Catalogue links, notes and command snippets. Held in memory only until a storage backend handles savedItemSaved."
        onDismissed: open = false
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: [{ k: "bookmark", l: "Bookmark" }, { k: "note", l: "Note" }, { k: "snippet", l: "Command Snippet" }]
                Pill { Layout.fillWidth: true; text: modelData.l; active: root.capType === modelData.k; enabled: root.capEditId === ""; onClicked: root.capType = modelData.k }
            }
        }
        Cap { text: "TITLE" }
        Field { id: capTitle; placeholder: "Short, searchable title"; invalid: root.capBadTitle; onTextChanged: root.capBadTitle = false }
        Mono { visible: root.capBadTitle; text: "Title is required."; color: th.red }
        Cap { text: root.capType === "bookmark" ? "URL" : root.capType === "note" ? "NOTE TEXT" : "COMMAND (STORED, NEVER EXECUTED)" }
        Field { id: capUrl; visible: root.capType === "bookmark"; mono: true; placeholder: "https://example.com"; invalid: root.capBadContent; onTextChanged: root.capBadContent = false }
        Area { id: capBody; visible: root.capType !== "bookmark"; mono: root.capType === "snippet"; invalid: root.capBadContent
               placeholder: root.capType === "note" ? "Write your note…" : "command --with arguments"; onTextChanged: root.capBadContent = false }
        Mono { visible: root.capBadContent; text: root.capContentMsg; color: th.red; Layout.fillWidth: true }
        Cap { text: "DESCRIPTION (OPTIONAL)" }
        Field { id: capDesc; placeholder: "What is this for?" }
        Cap { visible: root.capType === "snippet"; text: "NOTES (OPTIONAL)" }
        Area { id: capNotes; visible: root.capType === "snippet"; implicitHeight: 56; placeholder: "Cautions, prerequisites…" }
        ColumnLayout {
            visible: root.capType === "snippet"; Layout.fillWidth: true; spacing: 6
            Cap { text: "TRUST STATUS (A LABEL — NOT AN EXECUTION PERMISSION)" }
            Flow { Layout.fillWidth: true; spacing: 6
                Repeater { model: ["reviewed", "needs-review", "restricted"]
                    Pill { text: root.trustLabel(modelData); tone: root.trustTone(modelData); active: root.capTrust === modelData; onClicked: root.capTrust = modelData } } }
        }
        Cap { text: "COLLECTION" }
        Flow { Layout.fillWidth: true; spacing: 5
            Pill { text: "None"; active: root.capColl === ""; onClicked: root.capColl = "" }
            Repeater { model: root.collections; Pill { text: modelData; active: root.capColl === modelData; onClicked: root.capColl = modelData } } }
        Cap { text: "TAGS (COMMA SEPARATED)" }
        Field { id: capTags; mono: true; placeholder: "linux, wayland, notes" }
        footer: [ Mono { text: "◈ Saving never executes anything"; color: th.mute }, Spacer {},
                  Btn { text: "Cancel"; onClicked: capDlg.open = false },
                  Btn { kind: "primary"; icon: "✓"; text: root.capEditId !== "" ? "Save changes" : "Save to Space"; onClicked: root.commitCapture() } ]
    }

    // ---- collection dialog
    Modal {
        id: collDlg
        animMs: root.animMs; dlgWidth: 400; title: root.collMode === "new" ? "New collection" : "Rename collection"
        onDismissed: open = false
        Field { id: collName; placeholder: "Collection name"; invalid: root.collErr !== ""; onAccepted: root.commitColl(); onTextChanged: root.collErr = "" }
        Mono { visible: root.collErr !== ""; text: root.collErr; color: th.red }
        footer: [ Spacer {}, Btn { text: "Cancel"; onClicked: collDlg.open = false }, Btn { kind: "primary"; text: "Save"; onClicked: root.commitColl() } ]
    }

    // ---- automation wizard
    Modal {
        id: autoDlg
        animMs: root.animMs; dlgWidth: 680
        title: root.wiz.id !== "" ? "Edit automation" : "Create automation"
        subtitle: "Definitions are stored in the UI only. No system schedule or timer is created."
        onDismissed: open = false
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            Repeater {
                model: ["Identity", "Trigger", "Actions", "Conditions", "Safety", "Review"]
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 30; radius: 8
                    color: index === root.wizStep ? th.a(th.violet, 0.2) : th.well
                    border.width: 1; border.color: index === root.wizStep ? th.violet : th.line
                    Row { anchors.centerIn: parent; spacing: 5
                        Mono { text: index < root.wizStep ? "✓" : index + 1; color: index <= root.wizStep ? th.lilac : th.mute; font.bold: true }
                        Lbl { visible: root.width > 760; text: modelData; font.pixelSize: 11; color: index === root.wizStep ? th.text : th.mute } }
                    MouseArea { anchors.fill: parent; enabled: index < root.wizStep; cursorShape: Qt.PointingHandCursor; onClicked: { root.wizStep = index; root.wizMsg = "" } }
                }
            }
        }
        // 0 identity
        ColumnLayout { visible: root.wizStep === 0; Layout.fillWidth: true; spacing: 8
            Cap { text: "NAME" }
            Field { id: wName; placeholder: "e.g. Focus sprint"; onTextChanged: root.setWiz("name", text) }
            Cap { text: "DESCRIPTION" }
            Field { id: wDesc; placeholder: "What should this automation do?"; onTextChanged: root.setWiz("description", text) } }
        // 1 trigger
        ColumnLayout { visible: root.wizStep === 1; Layout.fillWidth: true; spacing: 8
            Cap { text: "TRIGGER TYPE" }
            Flow { Layout.fillWidth: true; spacing: 6
                Repeater { model: root.triggerTypes
                    Pill { text: modelData.l; active: root.wiz.ttype === modelData.k; onClicked: root.setWiz("ttype", modelData.k) } } }
            Rectangle { visible: root.unsupportedTrigger(root.wiz.ttype); Layout.fillWidth: true; implicitHeight: tw.implicitHeight + 16; radius: 8; color: th.a(th.amber, 0.12)
                Wrap { id: tw; x: 10; y: 8; width: parent.width - 20; text: "This trigger needs an integration that isn’t reported as supported. It can be defined, but will be saved as “Requires Review”."; color: th.amber } }
            RowLayout { visible: root.wiz.ttype === "once"; Layout.fillWidth: true; spacing: 8
                ColumnLayout { Layout.fillWidth: true; spacing: 4; Cap { text: "DATE (YYYY-MM-DD)" } Field { id: wDate; mono: true; placeholder: "2026-12-31"; onTextChanged: root.setWiz("tdate", text) } } }
            ColumnLayout { visible: root.wiz.ttype === "once" || root.wiz.ttype === "schedule"; Layout.fillWidth: true; spacing: 4
                Cap { text: "TIME (24 H, HH:MM)" }
                Field { id: wTime; mono: true; placeholder: "09:00"; onTextChanged: root.setWiz("ttime", text) } }
            ColumnLayout { visible: root.wiz.ttype === "schedule"; Layout.fillWidth: true; spacing: 4
                Cap { text: "DAYS (NONE SELECTED = EVERY DAY)" }
                Flow { Layout.fillWidth: true; spacing: 5
                    Repeater { model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        Pill { text: modelData; active: root.hasIn(root.wiz.tdays, modelData); onClicked: root.setWiz("tdays", root.toggled(root.wiz.tdays, modelData)) } } } }
            ColumnLayout { visible: root.wiz.ttype === "delay"; Layout.fillWidth: true; spacing: 4
                Cap { text: "DELAY (MINUTES)" }
                Field { id: wMin; mono: true; placeholder: "30"; onTextChanged: root.setWiz("tminutes", text) } }
            ColumnLayout { visible: root.wiz.ttype === "battery"; Layout.fillWidth: true; spacing: 4
                Cap { text: "BATTERY THRESHOLD (%)" }
                Field { id: wThr; mono: true; placeholder: "20"; onTextChanged: root.setWiz("tthreshold", text) }
                Flow { spacing: 5
                    Pill { text: "Falls below"; active: root.wiz.tdir === "below"; onClicked: root.setWiz("tdir", "below") }
                    Pill { text: "Rises above"; active: root.wiz.tdir === "above"; onClicked: root.setWiz("tdir", "above") } } }
            ColumnLayout { visible: root.wiz.ttype === "device"; Layout.fillWidth: true; spacing: 4
                Cap { text: "DEVICE NAME (FREE TEXT)" }
                Field { id: wDev; placeholder: "Device to watch for"; onTextChanged: root.setWiz("tdevice", text) } }
            ColumnLayout { visible: root.wiz.ttype === "event"; Layout.fillWidth: true; spacing: 4
                Cap { text: "SYSTEM EVENT" }
                Field { id: wEvt; placeholder: "Describe the event"; onTextChanged: root.setWiz("tevent", text) } }
            Wrap { visible: root.wiz.ttype === "manual"; text: "Manual automations only run when you request them." } }
        // 2 actions
        ColumnLayout { visible: root.wizStep === 2; Layout.fillWidth: true; spacing: 8
            Cap { text: "PICK ACTIONS FROM THE LIBRARY" }
            Flow { Layout.fillWidth: true; spacing: 5
                Repeater { model: root.actionsData
                    Pill { visible: modelData.enabled; text: modelData.name; icon: modelData.category === "Power" ? "⏻" : ""; tone: modelData.category === "Power" ? th.red : th.cyan
                           active: root.hasIn(root.wiz.actions, modelData.id); onClicked: root.setWiz("actions", root.toggled(root.wiz.actions, modelData.id)) } } }
            Cap { text: "ORDER OF EXECUTION" }
            Repeater {
                model: root.wiz.actions
                RowLayout { Layout.fillWidth: true; spacing: 4
                    Mono { text: index + 1; color: th.lilac }
                    Lbl { text: root.actionName(modelData); Layout.fillWidth: true }
                    Chip { visible: root.actionObj(modelData) && root.actionObj(modelData).trust !== "reviewed"; text: "NEEDS REVIEW"; tone: th.amber }
                    Btn { compact: true; kind: "ghost"; icon: "▲"; enabled: index > 0
                          onClicked: { var a = root.wiz.actions.slice(); var t = a[index]; a[index] = a[index - 1]; a[index - 1] = t; root.setWiz("actions", a) } }
                    Btn { compact: true; kind: "ghost"; icon: "▼"; enabled: index < root.wiz.actions.length - 1
                          onClicked: { var a = root.wiz.actions.slice(); var t = a[index]; a[index] = a[index + 1]; a[index + 1] = t; root.setWiz("actions", a) } }
                    Btn { compact: true; kind: "ghost"; icon: "✕"; onClicked: root.setWiz("actions", root.toggled(root.wiz.actions, modelData)) } }
            }
            Mono { visible: root.wiz.actions.length === 0; text: "No actions selected yet."; color: th.mute } }
        // 3 conditions
        ColumnLayout { visible: root.wizStep === 3; Layout.fillWidth: true; spacing: 8
            Wrap { text: "Optional conditions. They are stored with the definition and evaluated by the backend." }
            Repeater {
                model: [{ k: "weekdays", t: "Only on weekdays" }, { k: "ac_power", t: "Only while on AC power (if supported)" },
                        { k: "no_fullscreen", t: "Skip if a fullscreen window is active (if supported)" }, { k: "no_focus", t: "Skip if a focus session is running" }]
                Check { text: modelData.t; checked: root.hasIn(root.wiz.conds, modelData.k); onToggled: root.setWiz("conds", root.toggled(root.wiz.conds, modelData.k)) }
            } }
        // 4 safety
        ColumnLayout { visible: root.wizStep === 4; Layout.fillWidth: true; spacing: 8
            Check { text: "Ask for confirmation before running"; sub: root.wizHasPower() ? "Always required for power actions." : ""
                    checked: root.wiz.confirm || root.wizHasPower(); enabled: !root.wizHasPower(); onToggled: root.setWiz("confirm", value) }
            Cap { text: "CANCEL WINDOW" }
            Flow { spacing: 5
                Repeater { model: [10, 15, 30, 60]; Pill { text: modelData + " s"; active: root.wiz.grace === modelData; onClicked: root.setWiz("grace", modelData) } } }
            Check { text: "Notify when it runs"; checked: root.wiz.notify; onToggled: root.setWiz("notify", value) }
            Check { text: "Stop if an action fails"; checked: root.wiz.stopOnFail; onToggled: root.setWiz("stopOnFail", value) }
            Rectangle {
                visible: root.wizHasPower(); Layout.fillWidth: true; implicitHeight: pc3.implicitHeight + 20; radius: 10; color: th.a(th.redDeep, 0.35)
                ColumnLayout { id: pc3; x: 12; y: 10; width: parent.width - 24; spacing: 6
                    Cap { text: "⚠ CONSEQUENTIAL POWER ACTION"; color: th.red }
                    Repeater { model: root.powerText(root.wiz.actions); Wrap { text: "• " + modelData; color: th.text } }
                    Mono { text: "Schedule: " + root.trigSummary(root.wiz); color: th.dim; Layout.fillWidth: true }
                    Check { text: "I understand this can end my session and lose unsaved work."; checked: root.wiz.ack; onToggled: root.setWiz("ack", value) } }
            } }
        // 5 review
        ColumnLayout { visible: root.wizStep === 5; Layout.fillWidth: true; spacing: 8
            Rectangle { Layout.fillWidth: true; implicitHeight: rv.implicitHeight + 20; radius: 10; color: th.well
                ColumnLayout { id: rv; x: 12; y: 10; width: parent.width - 24; spacing: 4
                    Lbl { text: root.wiz.name; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Wrap { text: root.wiz.description !== "" ? root.wiz.description : "No description." }
                    Rule {}
                    Mono { text: "Trigger: " + root.trigSummary(root.wiz); color: th.dim; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                    Mono { text: "Actions: " + root.actionsSummary(root.wiz); color: th.dim; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                    Mono { text: "Conditions: " + (root.wiz.conds.length ? root.wiz.conds.join(", ") : "none"); color: th.dim; Layout.fillWidth: true }
                    Mono { text: "Safety: confirm " + (root.wiz.confirm || root.wizHasPower() ? "on" : "off") + " · cancel window " + root.wiz.grace + " s · stop on failure " + (root.wiz.stopOnFail ? "yes" : "no"); color: th.dim; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone } } }
            Rectangle { visible: root.unsupportedTrigger(root.wiz.ttype); Layout.fillWidth: true; implicitHeight: w1.implicitHeight + 16; radius: 8; color: th.a(th.amber, 0.12)
                Wrap { id: w1; x: 10; y: 8; width: parent.width - 20; text: "The chosen trigger isn’t supported by the current integration — this will be saved as Requires Review."; color: th.amber } }
            Rectangle { visible: root.wizHasPower(); Layout.fillWidth: true; implicitHeight: w2.implicitHeight + 16; radius: 8; color: th.a(th.redDeep, 0.35)
                Wrap { id: w2; x: 10; y: 8; width: parent.width - 20; text: "Contains a power action. Enabling it asks for a final confirmation."; color: th.red } }
            Check { text: "Enable after saving"; sub: "Marks the definition enabled in the UI only."; checked: root.wiz.enable; onToggled: root.setWiz("enable", value) } }
        footer: [ Lbl { text: root.wizMsg; color: th.red; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone },
                  Btn { text: "Cancel"; onClicked: autoDlg.open = false },
                  Btn { text: "Back"; visible: root.wizStep > 0; onClicked: { root.wizStep -= 1; root.wizMsg = "" } },
                  Btn { kind: "primary"; text: root.wizStep === 5 ? "Save automation" : "Next"; onClicked: root.wizNext() } ]
    }

    // ---- custom action editor
    Modal {
        id: actDlg
        animMs: root.animMs; dlgWidth: 600
        title: root.actEditId !== "" ? "Edit action" : "Custom action"
        subtitle: "Arbitrary command execution is restricted. Definitions here are validated and reviewed by the backend before they can run."
        onDismissed: open = false
        Cap { text: "NAME" }
        Field { id: aName; placeholder: "Action name" }
        Cap { text: "DESCRIPTION" }
        Field { id: aDesc; placeholder: "What will this do?" }
        Cap { text: "CATEGORY" }
        Flow { Layout.fillWidth: true; spacing: 5
            Repeater { model: root.actionCategories; Pill { text: modelData; active: root.aeCat === modelData; onClicked: root.aeCat = modelData } } }
        Cap { text: "REVIEWED ACTION IDENTIFIER OR EXECUTABLE REFERENCE" }
        Field { id: aRef; mono: true; placeholder: "namespace.action_id" }
        Cap { text: "STRUCTURED ARGUMENTS (ONE PER LINE — NO SHELL PARSING)" }
        Area { id: aArgs; mono: true; implicitHeight: 64; placeholder: "--flag\nvalue" }
        Cap { text: "WORKING DIRECTORY (OPTIONAL)" }
        Field { id: aCwd; mono: true; placeholder: "Leave empty unless required" }
        Check { text: "Require confirmation before running"; checked: root.aeConfirm || root.aeCat === "Power"; enabled: root.aeCat !== "Power"; onToggled: root.aeConfirm = value }
        Cap { text: "TRUST STATUS" }
        Flow { spacing: 5
            Pill { text: "Needs Review"; tone: th.amber; active: root.aeTrust === "needs-review"; onClicked: root.aeTrust = "needs-review" }
            Pill { text: "Restricted"; tone: th.red; active: root.aeTrust === "restricted"; onClicked: root.aeTrust = "restricted" } }
        Wrap { text: "“Reviewed” is granted only by the backend’s review process, never by this form."; color: th.mute; font.pixelSize: 11 }
        Mono { visible: root.aeMsg !== ""; text: root.aeMsg; color: th.red; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
        footer: [ Spacer {}, Btn { text: "Cancel"; onClicked: actDlg.open = false }, Btn { kind: "primary"; text: "Save action"; onClicked: root.commitAction() } ]
    }

    // ---- preset editor
    Modal {
        id: presetDlg
        animMs: root.animMs; dlgWidth: 500; title: "Edit preset"
        onDismissed: open = false
        Cap { text: "NAME" }
        Field { id: pName; placeholder: "Preset name" }
        Cap { text: "DESCRIPTION" }
        Field { id: pDesc; placeholder: "What is this context for?" }
        Cap { text: "INTENDED APPLICATIONS (COMMA SEPARATED)" }
        Field { id: pApps; placeholder: "Editor, Terminal, Browser" }
        Check { text: "Do Not Disturb while active (if supported)"; checked: root.peDnd; onToggled: root.peDnd = value }
        Cap { text: "FOCUS TIMER" }
        Flow { spacing: 5
            Repeater { model: ["none", "25", "50"]; Pill { text: modelData === "none" ? "None" : modelData + " min"; active: root.peTimer === modelData; onClicked: root.peTimer = modelData } } }
        footer: [ Spacer {}, Btn { text: "Cancel"; onClicked: presetDlg.open = false }, Btn { kind: "primary"; text: "Save preset"; onClicked: root.commitPreset() } ]
    }

    // ---- settings
    Modal {
        id: settingsDlg
        animMs: root.animMs; dlgWidth: 560; title: "Settings"
        subtitle: "No passwords, root access or hidden command execution are configurable here."
        onDismissed: open = false
        Cap { text: "DEFAULT COLLECTION" }
        Flow { Layout.fillWidth: true; spacing: 5
            Pill { text: "None"; active: root.settings.defaultCollection === ""; onClicked: root.setSetting("defaultCollection", "") }
            Repeater { model: root.collections; Pill { text: modelData; active: root.settings.defaultCollection === modelData; onClicked: root.setSetting("defaultCollection", modelData) } } }
        Cap { text: "DEFAULT DIRECTORIES (OPTIONAL, NOT VALIDATED HERE)" }
        Field { mono: true; placeholder: "Default save directory"; Component.onCompleted: text = root.settings.defaultDir; onTextChanged: if (text !== root.settings.defaultDir) root.setSetting("defaultDir", text) }
        Field { mono: true; placeholder: "Reviewed scripts directory"; Component.onCompleted: text = root.settings.scriptsDir; onTextChanged: if (text !== root.settings.scriptsDir) root.setSetting("scriptsDir", text) }
        Cap { text: "NOTIFICATIONS & CONFIRMATIONS" }
        Check { text: "Show toast notifications for UI operations"; checked: root.settings.toasts; onToggled: root.setSetting("toasts", value) }
        Check { text: "Confirm before deleting items"; checked: root.settings.confirmDelete; onToggled: root.setSetting("confirmDelete", value) }
        Check { text: "Confirm before requesting any action run"; sub: "Power and confirm-flagged actions always ask."; checked: root.settings.confirmRun; onToggled: root.setSetting("confirmRun", value) }
        Cap { text: "DEVICE VISIBILITY" }
        Check { text: "Show phone status in the top bar when available"; checked: root.settings.showDeviceChip; onToggled: root.setSetting("showDeviceChip", value) }
        Cap { text: "HISTORY RETENTION" }
        Flow { spacing: 5
            Repeater { model: [7, 30, 90, 0]; Pill { text: modelData === 0 ? "Forever" : modelData + " days"; active: root.settings.retention === modelData; onClicked: root.setSetting("retention", modelData) } } }
        Cap { text: "ANIMATION" }
        Check { text: "Reduce animations"; sub: "Disables page, dialog and panel transitions."; checked: root.settings.reduceMotion; onToggled: root.setSetting("reduceMotion", value) }
        Cap { text: "ALLOWED / REVIEWED ACTIONS" }
        Repeater {
            model: root.actionsData
            RowLayout { Layout.fillWidth: true; spacing: 8
                Lbl { text: modelData.name; Layout.fillWidth: true; color: modelData.enabled ? th.text : th.mute }
                Chip { text: root.trustLabel(modelData.trust).toUpperCase(); tone: root.trustTone(modelData.trust) }
                Toggle { checked: modelData.enabled; onToggled: root.actionsData = root.patched(root.actionsData, modelData.id, { enabled: value }) } }
        }
        footer: [ Spacer {}, Btn { kind: "primary"; text: "Done"; onClicked: settingsDlg.open = false } ]
    }
}
