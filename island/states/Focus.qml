// Island state: focus — compact work/break pill and expanded work session.
// Island.qml owns the session engine; this file only renders its live data.
import QtQuick
import QtQuick.Layouts

Item {
    id: st

    required property var core

    readonly property string key: "focus"
    readonly property real w: core.focusBreak ? 220 : core.hovered ? 380 : 220
    readonly property real h: core.focusBreak ? 40 : core.hovered ? 130 : 40
    readonly property color accent: core.focusBreak ? core.lav : core.teal
    readonly property bool hasTime: core.focusOn && core.focusRemaining >= 0
    readonly property bool hasProgress: hasTime && core.focusPhaseSeconds > 0
    readonly property real progress: hasProgress
        ? Math.max(0, Math.min(1, 1 - core.focusRemaining / core.focusPhaseSeconds))
        : 0
    readonly property bool hasSessionIndex: core.focusOn
        && core.focusSessionIndex > 0 && core.focusSessionCount > 0

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 12
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 10
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component Ring: Canvas {
        property real progress: 0
        property color tone: st.accent

        onProgressChanged: requestPaint()
        onToneChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const lineWidth = width < 30 ? 2.2 : 3
            const radius = Math.min(width, height) / 2 - lineWidth / 2
            const cx = width / 2
            const cy = height / 2
            ctx.lineWidth = lineWidth
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
            ctx.beginPath()
            ctx.arc(cx, cy, radius, 0, Math.PI * 2, false)
            ctx.stroke()

            if (progress <= 0) return
            ctx.strokeStyle = tone
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(cx, cy, radius, -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * progress, false)
            ctx.stroke()
        }
    }

    // Work compact view also becomes the expanded view on hover. A debug preview
    // deliberately shows only the fixed interface label and PREVIEW status.
    Item {
        anchors.fill: parent
        visible: !core.focusBreak && !core.hovered

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 7

            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                visible: st.hasProgress

                Ring { anchors.fill: parent; progress: st.progress; tone: st.accent }
                Rectangle {
                    anchors.centerIn: parent
                    width: 4; height: 4; radius: 2
                    color: st.accent
                }
            }

            Txt {
                Layout.fillWidth: true
                text: st.hasTime ? st.core.fmt(st.core.focusRemaining) : "FOCUS"
                font.family: st.core.monoFont
                font.pixelSize: 13
                font.bold: true
            }

            Rectangle {
                Layout.preferredWidth: compactLabel.implicitWidth + 16
                Layout.preferredHeight: 22
                radius: 11
                color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.25)

                Text {
                    id: compactLabel
                    anchors.centerIn: parent
                    text: core.focusPaused ? "PAUSED" : core.focusOn ? "ACTIVE" : "PREVIEW"
                    color: st.accent
                    font.family: st.core.monoFont
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }
    }

    // Expanded work session: all values are omitted when the debug preview has
    // no real session behind it.
    Item {
        anchors.fill: parent
        visible: !core.focusBreak && core.hovered

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 10

                Item {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    visible: st.hasProgress
                    Ring { anchors.fill: parent; progress: st.progress; tone: st.accent }
                    Text {
                        anchors.centerIn: parent
                        visible: st.hasProgress
                        text: st.core.fmt(st.core.focusRemaining)
                        color: st.core.text
                        font.family: st.core.monoFont
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Txt {
                        Layout.fillWidth: true
                        text: core.focusTitle !== "" ? core.focusTitle : "FOCUS SESSION"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Mono {
                        Layout.fillWidth: true
                        visible: st.hasSessionIndex
                        text: "SESSION " + core.focusSessionIndex + " / " + core.focusSessionCount
                    }

                    Mono {
                        Layout.fillWidth: true
                        visible: st.hasProgress
                        text: Math.round(st.progress * 100) + "% COMPLETE"
                        color: st.accent
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                visible: st.hasProgress
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    width: parent.width * st.progress
                    height: parent.height
                    radius: parent.radius
                    color: st.accent
                }
            }

            Mono {
                Layout.fillWidth: true
                visible: core.focusPaused || core.focusOn
                text: core.focusPaused ? "PAUSED" : "WORK"
                color: core.focusPaused ? core.dim : st.accent
            }
        }
    }

    // Breaks stay compact and always use the real remaining duration.
    Item {
        anchors.fill: parent
        visible: core.focusBreak

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 7

            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                visible: st.hasProgress
                Ring { anchors.fill: parent; progress: st.progress; tone: st.core.lav }
                Rectangle {
                    anchors.centerIn: parent
                    width: 4; height: 4; radius: 2
                    color: st.core.lav
                }
            }

            Txt {
                Layout.fillWidth: true
                text: st.hasTime ? st.core.fmt(st.core.focusRemaining) : "REST"
                font.family: st.core.monoFont
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                text: "REST"
                color: st.core.lav
                font.family: st.core.monoFont
                font.pixelSize: 9
                font.bold: true
            }
        }
    }
}
