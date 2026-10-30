import QtQuick
import QtQuick.Layouts
import qs.config

// FontTestView: Visual verification harness for the GPS unified font system.
// Covers English, Hindi Devanagari conjuncts, Japanese CJK, Korean CJK,
// Emoji, Material Symbols, and Nerd Font icons.
Rectangle {
    id: root
    width: 620
    implicitHeight: layout.implicitHeight + 32
    color: Theme.surfaceBase
    radius: Theme.radiusCard
    border.width: Theme.borderWidth
    border.color: Theme.outlineSoft

    ColumnLayout {
        id: layout
        anchors { fill: parent; margins: 16 }
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "GPS Unified Font System Test"
                color: Theme.textMain
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 72; height: 22; radius: Theme.radiusPill
                color: Theme.accentPrimaryDim
                border.width: 1; border.color: Theme.accentPrimary
                Text {
                    anchors.centerIn: parent
                    text: "1.5x Scale"
                    color: Theme.accentPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }
        }

        // Active Font Token Summary
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: tokenGrid.implicitHeight + 16
            color: Theme.card
            radius: Theme.radiusMd
            border.width: 1; border.color: Theme.border

            GridLayout {
                id: tokenGrid
                anchors { fill: parent; margins: 8 }
                columns: 2
                columnSpacing: 16
                rowSpacing: 4

                Text { text: "fontSans:"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                Text { text: Theme.fontSans + (Theme.fontSans !== Theme.fontSansPreferred ? " (fallback from " + Theme.fontSansPreferred + ")" : " (preferred)"); color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 10; font.bold: true }

                Text { text: "fontMono:"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                Text { text: Theme.fontMono + (Theme.fontMono !== Theme.fontMonoPreferred ? " (bridge/fallback)" : " (preferred)"); color: Theme.accentSecondary; font.family: Theme.fontMono; font.pixelSize: 10; font.bold: true }

                Text { text: "fontIcon:"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10 }
                Text { text: Theme.fontIcon + " (installed)"; color: Theme.statusGood; font.family: Theme.fontMono; font.pixelSize: 10; font.bold: true }
            }
        }

        // Test Section 1: English & UI Sans
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { text: "English (UI Sans / fontSans)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            Text {
                text: "GPS Desktop — Unified typography across shell, hub & terminal."
                color: Theme.textMain
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeBody
            }
        }

        // Test Section 2: Hindi & Devanagari Conjuncts
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { text: "Hindi / Devanagari Conjuncts (संयुक्ताक्षर)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            Text {
                text: "नमस्ते दुनिया, क्षत्रिय, प्रौद्योगिकी (राष्ट्र, धर्म, कृष्ण)"
                color: Theme.textMain
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeHeading
            }
        }

        // Test Section 3: Japanese (CJK JP)
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { text: "Japanese / CJK JP (日本語・アニメタイトル)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            Text {
                text: "こんにちは、アニメーション (進撃の巨人 / 新世紀エヴァンゲリオン)"
                color: Theme.textMain
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeHeading
            }
        }

        // Test Section 4: Korean (CJK KR)
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { text: "Korean / CJK KR (한국어・웹툰)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            Text {
                text: "안녕하세요, 애니메이션 (나 혼자만 레벨업)"
                color: Theme.textMain
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeHeading
            }
        }

        // Test Section 5: Emoji
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { text: "Emoji (Noto Color Emoji)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            Text {
                text: "🚀 🎨 🎧 🔒 ⚡ ☕ 🌐 💡"
                color: Theme.textMain
                font.pixelSize: 18
            }
        }

        // Test Section 6: Material Symbols Rounded
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4
            Text { text: "Material Symbols Rounded (Ligature icons)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            RowLayout {
                spacing: 16
                Repeater {
                    model: ["search", "settings", "close", "check", "play_arrow", "volume_up", "download", "favorite"]
                    RowLayout {
                        spacing: 4
                        Text {
                            text: modelData
                            color: Theme.brandAccent
                            font.family: Theme.fontIcon
                            font.pixelSize: 20
                        }
                        Text {
                            text: modelData
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        // Test Section 7: Nerd Font Icons
        ColumnLayout {
            Layout.fillWidth: true; spacing: 4
            Text { text: "Nerd Font Glyphs (JetBrainsMono Nerd Font)"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: 9 }
            RowLayout {
                spacing: 16
                Repeater {
                    model: [
                        { glyph: "󰕾", label: "volume" },
                        { glyph: "󰂚", label: "bell" },
                        { glyph: "󰁹", label: "battery" },
                        { glyph: "󰖨", label: "brightness" },
                        { glyph: "󰆴", label: "trash" },
                        { glyph: "󰥔", label: "time" },
                        { glyph: "󰐥", label: "power" }
                    ]
                    RowLayout {
                        spacing: 4
                        Text {
                            text: modelData.glyph
                            color: Theme.accentSecondary
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                        }
                        Text {
                            text: modelData.label
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }
}
