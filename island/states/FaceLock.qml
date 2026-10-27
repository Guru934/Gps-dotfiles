// Island state: facelock — visual-only Face Lock preview for the GPS dynamic island.
// Five local subviews: armed (150×34) · inspect (380×122) · scanning (260×60) · ok (260×60) · reject (300×70).
// This file has no camera, PAM, Howdy, hyprlock, Process, Timer or command path. The stage
// switcher is a local design preview and must never be read as authentication state.
import QtQuick
import QtQuick.Layouts

Item {
    id: st
    required property var core
    readonly property string key: "facelock"

    // Local, non-persistent preview selection. Never written to core or disk.
    property string previewStage: "armed"
    property string previewNote: "Visual prototype · authentication backend not connected"

    readonly property bool active: core.mode === key
    readonly property bool inspectView: previewStage === "inspect"
        || (previewStage === "armed" && Boolean(core.hovered))
    readonly property bool scanningView: previewStage === "scanning"
    readonly property bool okView: previewStage === "ok"
    readonly property bool rejectView: previewStage === "reject"
    readonly property bool armedView: previewStage === "armed" && !inspectView

    readonly property real w: inspectView ? 380 : rejectView ? 300 : (scanningView || okView) ? 260 : 150
    readonly property real h: inspectView ? 122 : rejectView ? 70 : (scanningView || okView) ? 60 : 34
    readonly property color accent: rejectView ? core.coral : core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    onActiveChanged: if (!active) previewStage = "armed"

    function tint(base, alpha) {
        return Qt.rgba(base.r, base.g, base.b, alpha)
    }

    function selectStage(value) {
        if (["armed", "inspect", "scanning", "ok", "reject"].indexOf(value) < 0) return
        previewStage = value
    }

    // ── small local widgets; each island state stays self-contained ──
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
        property string name: ""
        property string alt: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 14
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Amber, clickable preview indicator. Opens the inspector where all stages live.
    component PreviewTag: Rectangle {
        id: pt
        implicitWidth: ptRow.implicitWidth + 14
        implicitHeight: 18
        radius: 9
        color: ptMouse.containsMouse ? st.tint(st.core.amber, 0.20)
                                     : st.tint(st.core.amber, 0.08)
        border.width: 1
        border.color: st.tint(st.core.amber, 0.32)
        signal picked()

        RowLayout {
            id: ptRow
            anchors.centerIn: parent
            spacing: 2

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "PREVIEW"
                color: st.core.amber
                font.family: st.core.monoFont
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 0.4
            }

            Ico {
                Layout.alignment: Qt.AlignVCenter
                name: "keyboard_arrow_up"
                alt: "^"
                font.pixelSize: 11
                color: st.core.amber
            }
        }

        MouseArea {
            id: ptMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pt.picked()
        }
    }

    // Explicit stage button used only by the development preview selector.
    component StageChip: Rectangle {
        id: sc
        property string label: ""
        property bool selected: false
        property color tone: st.core.teal
        implicitWidth: scText.implicitWidth + 14
        implicitHeight: 18
        radius: 9
        color: selected ? st.tint(tone, 0.18)
                        : scMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
                                                : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: selected ? st.tint(tone, 0.45) : Qt.rgba(1, 1, 1, 0.10)
        signal picked()

        Text {
            id: scText
            anchors.centerIn: parent
            text: sc.label
            color: sc.selected ? sc.tone : st.core.dim
            font.family: st.core.monoFont
            font.pixelSize: 8
            font.bold: sc.selected
            font.letterSpacing: 0.4
        }

        MouseArea {
            id: scMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sc.picked()
        }
    }

    // The only looping animation in this file. Both entries stop with the stage
    // or the state, so nothing keeps ticking behind another island mode.
    component PulseDot: Item {
        id: pd
        property bool run: false
        property color tone: st.core.teal
        implicitWidth: 10
        implicitHeight: 10

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: pd.tone
            opacity: 0.22
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: pd.run && st.active && st.visible
                NumberAnimation { from: 0.7; to: 1.6; duration: 800; easing.type: Easing.OutCubic }
                NumberAnimation { from: 1.6; to: 0.7; duration: 0 }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            radius: 2.5
            color: pd.tone
        }
    }

    // Wireframe face tile with the Stitch-style laser sweep.
    component ScanGlyph: Item {
        id: sg
        implicitWidth: 32
        implicitHeight: 32
        clip: true

        readonly property color bracketColor: st.tint(st.core.teal, 0.55)

        Rectangle {
            anchors.fill: parent
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }

        Ico {
            anchors.centerIn: parent
            name: "face"
            alt: "◉"
            font.pixelSize: 16
            color: st.tint(st.core.teal, 0.70)
        }

        Rectangle { x: 5; y: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; y: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; y: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; y: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }

        Item {
            id: scanLaser
            x: 4
            y: 5
            width: sg.width - 8
            height: 4
            visible: st.active && st.visible && st.scanningView

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 1
                radius: 0.5
                color: st.core.teal
                opacity: 0.35
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 2
                radius: 1
                color: st.core.teal
                opacity: 0.9
            }

            SequentialAnimation on y {
                loops: Animation.Infinite
                running: st.active && st.visible && st.scanningView
                NumberAnimation { from: 5; to: 23; duration: 750; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 23; to: 5; duration: 750; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ═══════════ A · IDLE ARMED PREVIEW (150×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.armedView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: st.selectStage("inspect")
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 4

            Ico {
                Layout.alignment: Qt.AlignVCenter
                name: "face"
                alt: "◉"
                font.pixelSize: 15
                color: st.core.teal
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 5
                Layout.preferredHeight: 5
                radius: 2.5
                color: st.core.teal
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "FACE LOCK"
                color: st.core.text
                font.family: st.core.monoFont
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 0.4
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: armedBadgeText.implicitWidth + 8
                Layout.preferredHeight: 14
                radius: 7
                color: st.tint(st.core.amber, 0.08)
                border.width: 1
                border.color: st.tint(st.core.amber, 0.28)

                Text {
                    id: armedBadgeText
                    anchors.centerIn: parent
                    text: "PREVIEW"
                    color: st.core.amber
                    font.family: st.core.monoFont
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 0.4
                }
            }
        }
    }

    // ═══════════ B · INSPECT PANEL PREVIEW (380×122) ═══════════
    // Opens on hover from the compact view, or stays open via the INSPECT chip.
    Item {
        anchors.fill: parent
        opacity: st.inspectView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 11
            anchors.bottomMargin: 11
            spacing: 6

            // Top row: identity, honest preview badge.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    Ico {
                        anchors.centerIn: parent
                        name: "face"
                        alt: "◉"
                        font.pixelSize: 14
                        color: st.core.teal
                    }
                }

                Txt {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "Face lock"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: inspectBadgeText.implicitWidth + 12
                    Layout.preferredHeight: 18
                    radius: 9
                    color: st.tint(st.core.amber, 0.10)
                    border.width: 1
                    border.color: st.tint(st.core.amber, 0.32)

                    Text {
                        id: inspectBadgeText
                        anchors.centerIn: parent
                        text: "PREVIEW"
                        color: st.core.amber
                        font.family: st.core.monoFont
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 0.4
                    }
                }
            }

            // Middle row: the only status statement available in this milestone.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                spacing: 6

                Ico {
                    Layout.alignment: Qt.AlignVCenter
                    name: "info"
                    alt: "i"
                    font.pixelSize: 11
                    color: st.core.dim
                }

                Mono {
                    Layout.fillWidth: true
                    text: st.previewNote
                    font.pixelSize: 9
                }
            }

            // Bottom row: visual-only primary action; no MouseArea is attached.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 146
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    radius: 13
                    color: Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 4

                        Ico {
                            Layout.alignment: Qt.AlignVCenter
                            name: "lock"
                            alt: "L"
                            font.pixelSize: 13
                            color: st.core.teal
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: "LOCK NOW"
                            color: st.core.text
                            font.family: st.core.monoFont
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.5
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "UI ONLY"
                            color: st.core.amber
                            font.family: st.core.monoFont
                            font.pixelSize: 7
                            font.bold: true
                        }
                    }
                }

                Mono {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "NO SYSTEM ACTION"
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 8
                }
            }

            // Development-only stage selector. Local state only.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "DEV PREVIEW"
                    color: st.core.amber
                    font.family: st.core.monoFont
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 0.4
                }

                StageChip {
                    Layout.alignment: Qt.AlignVCenter
                    label: "ARMED"
                    selected: st.previewStage === "armed" && !st.inspectView
                    onPicked: st.selectStage("armed")
                }

                StageChip {
                    Layout.alignment: Qt.AlignVCenter
                    label: "INSPECT"
                    selected: st.inspectView
                    tone: st.core.lav
                    onPicked: st.selectStage("inspect")
                }

                StageChip {
                    Layout.alignment: Qt.AlignVCenter
                    label: "SCANNING"
                    selected: st.previewStage === "scanning"
                    onPicked: st.selectStage("scanning")
                }

                StageChip {
                    Layout.alignment: Qt.AlignVCenter
                    label: "SUCCESS"
                    selected: st.previewStage === "ok"
                    onPicked: st.selectStage("ok")
                }

                StageChip {
                    Layout.alignment: Qt.AlignVCenter
                    label: "REJECT"
                    selected: st.previewStage === "reject"
                    tone: st.core.coral
                    onPicked: st.selectStage("reject")
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ═══════════ C · SCANNING PREVIEW (260×60) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.scanningView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            ScanGlyph {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Txt {
                        text: "SCANNING"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    PulseDot {
                        Layout.alignment: Qt.AlignVCenter
                        run: st.scanningView
                    }

                    Item { Layout.fillWidth: true }
                }

                Mono {
                    Layout.fillWidth: true
                    text: "PREVIEW · DESIGN ONLY"
                    font.pixelSize: 8
                    color: st.core.amber
                }
            }

            PreviewTag {
                Layout.alignment: Qt.AlignVCenter
                onPicked: st.selectStage("inspect")
            }
        }
    }

    // ═══════════ D · SUCCESS PREVIEW (260×60) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.okView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 9
                color: st.core.teal

                Ico {
                    anchors.centerIn: parent
                    name: "check"
                    alt: "✓"
                    font.pixelSize: 18
                    color: st.core.pillColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Txt {
                    Layout.fillWidth: true
                    text: "SUCCESS"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Mono {
                    Layout.fillWidth: true
                    text: "PREVIEW · NO UNLOCK"
                    font.pixelSize: 8
                    color: st.core.amber
                }
            }

            PreviewTag {
                Layout.alignment: Qt.AlignVCenter
                onPicked: st.selectStage("inspect")
            }
        }
    }

    // ═══════════ E · REJECT PREVIEW (300×70) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.rejectView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 9
                color: st.tint(st.core.coral, 0.14)
                border.width: 1
                border.color: st.tint(st.core.coral, 0.30)

                Ico {
                    anchors.centerIn: parent
                    name: "close"
                    alt: "×"
                    font.pixelSize: 18
                    color: st.core.coral
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Txt {
                    Layout.fillWidth: true
                    text: "REJECTED"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Mono {
                    Layout.fillWidth: true
                    text: "PREVIEW · MOCK STATE"
                    font.pixelSize: 8
                    color: st.core.coral
                }
            }

            PreviewTag {
                Layout.alignment: Qt.AlignVCenter
                onPicked: st.selectStage("inspect")
            }
        }
    }
}
