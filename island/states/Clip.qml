// Island state: clip — toast-only copy confirmation (360×56 text / 360×80 image)
// Shows a short copied preview with sensitive data redacted.
// Interactive history selection is owned by the dedicated ClipboardPicker surface.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: st
    required property var core
    readonly property string key: "clip"

    readonly property bool active: core.mode === key

    // Image detection
    readonly property string effectiveKind: (core.clipKind && core.clipKind !== "") ? core.clipKind : ""
    readonly property string effectiveMime: (core.clipMime && core.clipMime !== "") ? core.clipMime : ""
    readonly property int effectiveBytes: (core.clipBytes && core.clipBytes > 0) ? core.clipBytes : 0
    readonly property string effectiveImgPath: (core.clipImgPath && core.clipImgPath !== "") ? core.clipImgPath : ""
    readonly property real effectiveTs: (core.clipTs && core.clipTs > 0) ? core.clipTs : core.now

    readonly property bool isImage: effectiveKind === "image" || effectiveImgPath !== ""
    readonly property bool showImageFlash: isImage
    readonly property bool showTextFlash: !isImage

    readonly property real w: 360
    readonly property real h: isImage ? 80 : 56
    readonly property color accent: core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function fmtBytes(b) {
        if (b <= 0) return ""
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return Math.max(1, Math.round(b / 1024)) + " KB"
        return b + " B"
    }

    function redactPreview(text) {
        if (!st.core.clipPreview) return "••••••••"
        if (!text) return ""
        const trimmed = text.trim()
        // Redact tokens, keys, passwords, hashes
        if (/^(gh[pousr]_[A-Za-z0-9_]{20,}|sk_[a-zA-Z0-9_]{20,}|ey[A-Za-z0-9_-]{20,}\.ey[A-Za-z0-9_-]{20,}|\$2[aby]\$[0-9]{2}\$|-----BEGIN [A-Z ]+ PRIVATE KEY-----)/.test(trimmed)) {
            return "•••••••• [sensitive key hidden]"
        }
        return text
    }

    // Shared small text components
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 10
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    component Ico: Text {
        property string alt: ""
        property string name: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 15
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // ═══════════ STATE 01: COPY FLASH (TEXT) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showTextFlash ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.10)

                Ico {
                    anchors.centerIn: parent
                    name: "content_copy"
                    alt: "⎘"
                    font.pixelSize: 15
                    color: st.core.teal
                }
            }

            Mono {
                Layout.fillWidth: true
                visible: st.core.clipText !== ""
                text: st.redactPreview(st.core.clipText)
                font.pixelSize: 12
                font.weight: Font.Medium
                color: st.core.text
            }

            RowLayout {
                spacing: 8

                Mono {
                    visible: st.core.clipChars > 0
                    text: st.core.clipChars + " chars"
                    font.pixelSize: 9
                    color: st.core.dim
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: copiedRow.implicitWidth + 16
                    radius: 10
                    color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.15)

                    RowLayout {
                        id: copiedRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: st.core.teal
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: st.visible && st.showTextFlash
                                NumberAnimation { to: 0.2; duration: 550 }
                                NumberAnimation { to: 1.0; duration: 550 }
                            }
                        }

                        Mono {
                            text: "COPIED"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            color: st.core.teal
                        }
                    }
                }
            }
        }
    }

    // ═══════════ STATE 02: IMAGE BUFFER FLASH ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showImageFlash ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            Rectangle {
                implicitWidth: 56
                implicitHeight: 56
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
                clip: true

                Image {
                    id: thumbImg
                    anchors.fill: parent
                    source: st.effectiveImgPath ? "file://" + st.effectiveImgPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                Ico {
                    anchors.centerIn: parent
                    visible: thumbImg.status !== Image.Ready
                    name: "image"
                    alt: "IMG"
                    font.pixelSize: 22
                    color: st.core.teal
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Txt {
                    text: "Image copied to clipboard"
                    font.weight: Font.DemiBold
                    font.pixelSize: 12
                }

                Mono {
                    text: st.effectiveBytes > 0 ? st.fmtBytes(st.effectiveBytes) : "PNG Image"
                    color: st.core.dim
                }
            }

            Rectangle {
                implicitHeight: 20
                implicitWidth: imgCopiedRow.implicitWidth + 16
                radius: 10
                color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.15)

                RowLayout {
                    id: imgCopiedRow
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        width: 4
                        height: 4
                        radius: 2
                        color: st.core.teal
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: st.visible && st.showImageFlash
                            NumberAnimation { to: 0.2; duration: 550 }
                            NumberAnimation { to: 1.0; duration: 550 }
                        }
                    }

                    Mono {
                        text: "COPIED"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                        color: st.core.teal
                    }
                }
            }
        }
    }
}
