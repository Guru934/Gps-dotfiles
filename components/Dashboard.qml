import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.dashboard

// Dashboard frame: header, tab strip, per-tab content well and a footer hint
// bar. Each tab owns a Loader that only instantiates its pane while the tab
// is active and the drawer is covering, so per-pane timers and processes die
// with the pane. `hub` is the shell root (settings + shared actions).
Item {
    id: root
    property var hub: null
    property bool isOpen: false
    property bool covering: false
    property string activeTab: "home"

    signal closeRequested()
    signal tabRequested(string tabName)

    readonly property var tabs: [
        { key: "home", label: "HOME", icon: "space_dashboard" },
        { key: "media", label: "MEDIA", icon: "graphic_eq" },
        { key: "system", label: "SYSTEM", icon: "monitor_heart" },
        { key: "tools", label: "TOOLS", icon: "construction" }
    ]

    readonly property int currentIndex: {
        for (let i = 0; i < root.tabs.length; i++) {
            if (root.tabs[i].key === root.activeTab) return i
        }
        return 0
    }
    readonly property var currentTab: root.tabs[root.currentIndex]

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: Theme.radiusDrawer
        // Opaque per the design refs (bg-surface #0f131c): unlike the small
        // popups, the full-height drawer reads as a solid console surface.
        color: Theme.surfaceDeep
        border.width: 1
        border.color: Theme.outlineSoft

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 9
                    color: Theme.surfaceHigh
                    border.width: 1
                    border.color: Theme.outlineSoft

                    DashIcon {
                        anchors.centerIn: parent
                        name: "hub"
                        color: Theme.accentPrimary
                        font.pixelSize: 17
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: "SYSTEM CONSOLE"
                        color: Theme.textMain
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "DASHBOARD // " + (root.currentTab ? root.currentTab.label : "")
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                }

                Item {
                    id: closeButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 30
                    implicitHeight: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: closeHover.hovered ? Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    DashIcon {
                        anchors.centerIn: parent
                        name: "close"
                        color: closeHover.hovered ? Theme.textMain : Theme.textMuted
                        font.pixelSize: 16
                    }

                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.closeRequested() }
                }
            }

            DashTabBar {
                id: tabBar
                Layout.fillWidth: true
                tabs: root.tabs
                currentIndex: root.currentIndex
                onTabSelected: (key, index) => root.tabRequested(key)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Home pane: created when the drawer starts covering the
                // screen, destroyed once it has fully closed, so all probe
                // timers and service bindings below it die with it.
                Loader {
                    id: homeLoader
                    anchors.fill: parent
                    active: root.currentTab !== null && root.currentTab.key === "home" && root.covering
                    sourceComponent: homePane
                }

                Component {
                    id: homePane
                    HomeTab {
                        isOpen: root.isOpen
                        hub: root.hub
                    }
                }

                // Media pane: same lifecycle rules as the home pane, so its
                // MPRIS bindings, device polling and lyric process all stop
                // when the tab is left or the drawer closes.
                Loader {
                    id: mediaLoader
                    anchors.fill: parent
                    active: root.currentTab !== null && root.currentTab.key === "media" && root.covering
                    sourceComponent: mediaPane
                }

                Component {
                    id: mediaPane
                    MediaTab {
                        isOpen: root.isOpen
                        hub: root.hub
                    }
                }

                // System pane: same lifecycle rules; its probe and one-shot
                // process readers all stop when the tab is left or the drawer
                // closes.
                Loader {
                    id: systemLoader
                    anchors.fill: parent
                    active: root.currentTab !== null && root.currentTab.key === "system" && root.covering
                    sourceComponent: systemPane
                }

                Component {
                    id: systemPane
                    SystemTab {
                        isOpen: root.isOpen
                        hub: root.hub
                    }
                }

                // Tools pane: same lifecycle rules; capture launchers run
                // detached so they survive the drawer closing, and all live
                // reads stop when the tab is left or the drawer closes.
                Loader {
                    id: toolsLoader
                    anchors.fill: parent
                    active: root.currentTab !== null && root.currentTab.key === "tools" && root.covering
                    sourceComponent: toolsPane
                }

                Component {
                    id: toolsPane
                    ToolsTab {
                        isOpen: root.isOpen
                        hub: root.hub
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Theme.radiusControl
                color: Theme.surfaceBase
                border.width: 1
                border.color: Theme.outlineSoft

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: "ESC"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Text {
                        text: "close"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "SUPER+D"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Text {
                        text: "toggle"
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
