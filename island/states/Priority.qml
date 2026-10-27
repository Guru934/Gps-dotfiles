// Island state: priority — visual-only "Priority and Dual Mode" design preview for the GPS dynamic island.
// Compact (190×34) · expanded explainer (540×~395, on hover): dual-capsule illustration, priority order, interruption timeline.
// This file draws the intended design only. It has no Process, Timer, Connections, window or command path,
// it does not touch autoMode or state priority, and it never generates, resolves or restores anything.
// The only live data is the real music title / artist / art / playing flag from `core` (guarded; hidden when absent).
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: st
    required property var core
    readonly property string key: "priority"

    readonly property bool expanded: Boolean(core.hovered)

    // Island.qml's window is 560×420 and its input mask follows the pill, so the expanded size
    // stays inside that window: 540 wide, height derived from the content and capped at 412.
    readonly property real w: expanded ? 540 : 190
    readonly property real h: expanded ? Math.min(412, Math.ceil(col.implicitHeight) + 24) : 34
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    // ───────────── fixed design information (not a dump of the real autoMode) ─────────────
    readonly property var priorityRows: [
        { rank: "P0", category: "Critical",  label: "Agent Alert",       tone: "coral", note: "Highest priority; needs attention first" },
        { rank: "P1", category: "Biometric", label: "Face Lock",         tone: "teal",  note: "Biometric unlock prompt" },
        { rank: "P2", category: "Toast",     label: "Notification",      tone: "amber", note: "Incoming notification toast" },
        { rank: "P3", category: "Transient", label: "OSD Overlay",       tone: "lav",   note: "Brief volume and brightness feedback" },
        { rank: "P4", category: "Hardware",  label: "Charging Power",    tone: "amber", note: "Plug, unplug and low battery events" },
        { rank: "P5", category: "Feedback",  label: "Clipboard History", tone: "lav",   note: "Copy feedback and recent items" },
        { rank: "P6", category: "Sensor",    label: "Privacy Guards",    tone: "teal",  note: "Microphone, camera and screen indicators" },
        { rank: "P7", category: "Media",     label: "Music MPRIS",       tone: "lav",   note: "Media playback" },
        { rank: "P8", category: "Baseline",  label: "Idle",              tone: "dim",   note: "Shown when nothing else is active" }
    ]
    readonly property var timelineSteps: [
        { n: "01", label: "MUSIC ACTIVE",   tone: "teal" },
        { n: "02", label: "INTERRUPT",      tone: "amber" },
        { n: "03", label: "ALERT ACTIVE",   tone: "coral" },
        { n: "04", label: "ALERT RESOLVES", tone: "teal" },
        { n: "05", label: "MUSIC RESTORED", tone: "teal" }
    ]

    function toneColor(k) {
        return k === "coral" ? core.coral
             : k === "teal"  ? core.teal
             : k === "amber" ? core.amber
             : k === "lav"   ? core.lav
             : core.dim
    }
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ───────────── small local widgets ─────────────
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 9
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    component Ico: Text {
        property string alt: ""
        property string name: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 14
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    // section heading: small coloured dot + spaced mono caption
    component SecHead: RowLayout {
        id: sh
        property string label: ""
        property color tone: st.core.teal
        spacing: 6
        Rectangle { Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 2.5; color: sh.tone }
        Mono { Layout.fillWidth: true; text: sh.label; font.letterSpacing: 1.2; font.weight: Font.DemiBold }
    }
    // black capsule with a hairline edge, used by the illustration and the timeline thumbnails
    component Capsule: Rectangle {
        property color edge: st.core.teal
        property real edgeAlpha: 0.35
        radius: height / 2
        color: "#000000"
        border.width: 1
        border.color: Qt.rgba(edge.r, edge.g, edge.b, edgeAlpha)
    }
    // real cover art when MPRIS provides it, otherwise a plain disc
    component Art: Item {
        id: art
        property int size: 28
        implicitWidth: size
        implicitHeight: size
        Rectangle { id: artMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        Rectangle {
            anchors.fill: parent; radius: width / 2; color: "#14171f"; visible: img.status !== Image.Ready
            Rectangle {
                anchors.centerIn: parent; width: art.size * 0.38; height: width; radius: width / 2
                color: "#000000"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle { anchors.centerIn: parent; width: parent.width * 0.35; height: width; radius: width / 2; color: st.core.teal }
            }
        }
        Image {
            id: img
            anchors.fill: parent
            visible: status === Image.Ready
            source: st.core.hasMedia && st.core.artUrl ? st.core.artUrl : ""
            cache: false
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: art.size * 2
            sourceSize.height: art.size * 2
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true; maskSource: artMask
                maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
                saturation: st.core.playing ? 0.0 : -1.0
            }
        }
    }

    // ═══════════════ 1 · compact (190×34) ═══════════════
    Item {
        anchors.fill: parent
        opacity: !st.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Row {
            anchors.centerIn: parent
            spacing: 10
            // tiny two-capsule glyph: wide primary + round satellite
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Rectangle {
                    width: 20; height: 9; radius: 4.5
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1; border.color: st.tint(st.core.teal, 0.6)
                }
                Rectangle {
                    width: 9; height: 9; radius: 4.5
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1; border.color: st.tint(st.core.lav, 0.6)
                }
            }
            Mono {
                anchors.verticalCenter: parent.verticalCenter
                text: "PRIORITY · DUAL"
                color: st.core.text
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }
        }
    }

    // ═══════════════ 2 · expanded explainer ═══════════════
    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8
        opacity: st.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // ───────── Section A · dual capsule illustration ─────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            SecHead { Layout.fillWidth: true; label: "DUAL CAPSULE ILLUSTRATION · DESIGN PREVIEW"; tone: st.core.teal }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 66
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.06)

                // illustration is 300 + 12 + 40 = 352 wide, centred in the card
                Item {
                    id: illus
                    width: 352
                    height: parent.height
                    anchors.horizontalCenter: parent.horizontalCenter

                    // primary music capsule — 300×40
                    Capsule {
                        id: primary
                        x: 0; y: 7
                        width: 300; height: 40
                        edge: st.core.teal
                        edgeAlpha: 0.3

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 14
                            spacing: 8

                            Art {
                                size: 28
                                visible: st.core.hasMedia
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Rectangle {
                                visible: !st.core.hasMedia
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter
                                radius: 14; color: Qt.rgba(1, 1, 1, 0.08)
                                Ico {
                                    anchors.centerIn: parent
                                    name: "music_note"; alt: "♪"
                                    font.pixelSize: 15
                                    color: st.core.dim
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0
                                Txt {
                                    Layout.fillWidth: true
                                    text: st.core.hasMedia ? st.core.title : "MUSIC PREVIEW"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: st.core.hasMedia ? st.core.text : st.core.dim
                                }
                                Mono {
                                    Layout.fillWidth: true
                                    visible: st.core.hasMedia && st.core.artist !== ""
                                    text: st.core.artist
                                }
                            }
                            Mono {
                                visible: st.core.hasMedia
                                text: st.core.playing ? "PLAYING" : "PAUSED"
                                color: st.core.playing ? st.core.teal : st.core.dim
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    // satellite call capsule — 40×40, 12 px gap
                    Capsule {
                        id: satellite
                        x: primary.width + 12; y: 7
                        width: 40; height: 40
                        edge: st.core.lav
                        edgeAlpha: 0.4
                        Ico {
                            anchors.centerIn: parent
                            name: "headset_mic"; alt: "☎"
                            font.pixelSize: 18
                            color: st.core.lav
                        }
                    }

                    // captions
                    Mono {
                        x: 4; y: 51; width: 200
                        text: "PRIMARY · MUSIC · 300×40"
                    }
                    Mono {
                        x: 152; y: 51; width: 200
                        horizontalAlignment: Text.AlignRight
                        text: "Discord call · PREVIEW"
                        color: st.core.lav
                    }
                }
            }
        }

        // ───────── Section B · priority order ─────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            SecHead { Layout.fillWidth: true; label: "PRIORITY ORDER · DESIGN PREVIEW"; tone: st.core.lav }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: st.priorityRows
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property color tone: st.toneColor(modelData.tone)
                        Layout.fillWidth: true
                        Layout.preferredHeight: 19
                        radius: 7
                        color: Qt.rgba(1, 1, 1, 0.05)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 8
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 13
                                Layout.alignment: Qt.AlignVCenter
                                radius: 6.5
                                color: st.tint(row.tone, 0.2)
                                Mono {
                                    anchors.centerIn: parent
                                    text: row.modelData.rank
                                    color: row.tone
                                    font.weight: Font.Bold
                                    elide: Text.ElideNone
                                }
                            }
                            Mono {
                                Layout.preferredWidth: 60
                                Layout.alignment: Qt.AlignVCenter
                                text: row.modelData.category.toUpperCase()
                                font.letterSpacing: 0.6
                            }
                            Txt {
                                Layout.preferredWidth: 116
                                Layout.alignment: Qt.AlignVCenter
                                text: row.modelData.label
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Txt {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                text: row.modelData.note
                                font.pixelSize: 10
                                color: st.core.dim
                            }
                        }
                    }
                }
            }
        }

        // ───────── Section C · interruption and restoration ─────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            SecHead { Layout.fillWidth: true; label: "INTERRUPTION AND RESTORATION · DESIGN PREVIEW"; tone: st.core.amber }

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: st.timelineSteps
                    delegate: RowLayout {
                        id: step
                        required property int index
                        required property var modelData
                        readonly property color tone: st.toneColor(modelData.tone)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 100
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.06)

                            Column {
                                x: 5; y: 5
                                width: parent.width - 10
                                spacing: 2

                                Mono {
                                    width: parent.width
                                    text: step.modelData.n
                                    color: step.tone
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                }
                                Mono {
                                    width: parent.width
                                    text: step.modelData.label
                                    color: st.core.text
                                    font.weight: Font.DemiBold
                                }
                                // static thumbnail of the intended look at this step
                                Item {
                                    width: parent.width
                                    height: 14

                                    // 01 and 05: music capsule
                                    Capsule {
                                        visible: step.index === 0 || step.index === 4
                                        anchors.fill: parent
                                        edge: st.core.teal
                                        Rectangle {
                                            x: 4; anchors.verticalCenter: parent.verticalCenter
                                            width: 8; height: 8; radius: 4
                                            color: st.tint(st.core.teal, 0.5)
                                        }
                                        Rectangle {
                                            x: 18; anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 34; height: 2; radius: 1
                                            color: Qt.rgba(1, 1, 1, 0.25)
                                        }
                                    }

                                    // 02: music capsule makes room for a small interrupting capsule
                                    Capsule {
                                        visible: step.index === 1
                                        x: 0
                                        width: parent.width - 18; height: 14
                                        edge: st.core.teal
                                        Rectangle {
                                            x: 4; anchors.verticalCenter: parent.verticalCenter
                                            width: 8; height: 8; radius: 4
                                            color: st.tint(st.core.teal, 0.5)
                                        }
                                    }
                                    Capsule {
                                        visible: step.index === 1
                                        x: parent.width - 14
                                        width: 14; height: 14
                                        edge: st.core.coral
                                        edgeAlpha: 0.7
                                    }

                                    // 03: alert capsule
                                    Capsule {
                                        visible: step.index === 2
                                        anchors.fill: parent
                                        edge: st.core.coral
                                        edgeAlpha: 0.7
                                        Rectangle {
                                            x: 4; anchors.verticalCenter: parent.verticalCenter
                                            width: 8; height: 8; radius: 4
                                            color: st.core.coral
                                        }
                                        Rectangle {
                                            x: 18; anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 34; height: 2; radius: 1
                                            color: st.tint(st.core.coral, 0.5)
                                        }
                                    }

                                    // 04: resolved marker
                                    Capsule {
                                        visible: step.index === 3
                                        anchors.fill: parent
                                        edge: st.core.teal
                                        edgeAlpha: 0.6
                                        Ico {
                                            anchors.centerIn: parent
                                            name: "check"; alt: "✓"
                                            font.pixelSize: 11
                                            color: st.core.teal
                                        }
                                    }
                                }
                            }
                        }

                        // connector arrow (kept transparent after the last step so the cards stay equal width)
                        Item {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 52
                            Ico {
                                anchors.centerIn: parent
                                name: "chevron_right"; alt: "›"
                                font.pixelSize: 13
                                color: st.core.dim
                                opacity: step.index < 4 ? 1 : 0
                            }
                        }
                    }
                }
            }
        }
    }
}
