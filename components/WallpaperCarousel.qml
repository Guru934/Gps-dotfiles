import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import qs.config

PanelWindow {
    id: root

    property var hub: null
    property bool isOpen: false
    property int currentIndex: 0
    readonly property int visibleRadius: 3
    readonly property string repoRoot: (root.hub && root.hub.repoRoot)
        ? root.hub.repoRoot
        : (Quickshell.env("GPS_ROOT") || "")
    readonly property string wallpaperDirectory: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"

    readonly property var targetScreen: (root.hub && root.hub.popupScreen)
        ? root.hub.popupScreen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    function toggle() { root.isOpen = !root.isOpen }
    function close() { root.isOpen = false }
    function step(delta) {
        if (!carouselLoader.item) return
        carouselLoader.item.step(delta)
    }
    function applyWallpaper() {
        if (!carouselLoader.item) return
        carouselLoader.item.applyWallpaper()
    }

    // Centered finite surface: empty layer-shell edge anchors.
    // Adapts to 82% of screen width and 68% of screen height.
    screen: root.targetScreen
    anchors {}
    implicitWidth: root.targetScreen
        ? Math.min(1600, Math.max(960, Math.round(root.targetScreen.width * 0.82)))
        : 1574
    implicitHeight: root.targetScreen
        ? Math.min(880, Math.max(540, Math.round(root.targetScreen.height * 0.68)))
        : 816

    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "gps-wallpaper-carousel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Shortcut { sequence: "Super+W"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }

    // Lazy instantiation: whole carousel is only created when opened and freed on close
    Loader {
        id: carouselLoader
        anchors.fill: parent
        active: root.isOpen
        focus: true
        sourceComponent: carouselContent
        onLoaded: {
            if (carouselLoader.item) {
                carouselLoader.item.forceActiveFocus()
            }
        }
    }

    Component {
        id: carouselContent

        FocusScope {
            id: contentRoot
            anchors.fill: parent
            focus: true

            Component.onCompleted: contentRoot.forceActiveFocus()

            function step(delta) {
                if (wallpapers.count === 0) return
                root.currentIndex = (root.currentIndex + delta + wallpapers.count) % wallpapers.count
            }

            function applyWallpaper() {
                if (wallpapers.count === 0) return
                const path = wallpapers.get(root.currentIndex, "filePath")
                if (!path) return
                Quickshell.execDetached([root.repoRoot + "/scripts/set-wallpaper", path])
                root.close()
            }

            FolderListModel {
                id: wallpapers
                folder: root.wallpaperDirectory
                nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp"]
                showDirs: false
                sortField: FolderListModel.Name
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left) {
                    contentRoot.step(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    contentRoot.step(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.isAutoRepeat) {
                        event.accepted = true
                        return
                    }
                    contentRoot.applyWallpaper()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    if (event.isAutoRepeat) {
                        event.accepted = true
                        return
                    }
                    root.close()
                    event.accepted = true
                }
            }

            // Main Coverflow Stage: fills the centered window
            Item {
                id: stage
                anchors.fill: parent

                Repeater {
                    model: wallpapers
                    delegate: Item {
                        id: cardDelegate
                        required property int index
                        required property url fileUrl
                        required property string fileName

                        readonly property int delta: index - root.currentIndex
                        readonly property bool inRange: Math.abs(delta) <= root.visibleRadius
                        readonly property bool isSelected: delta === 0

                        // 16:10 aspect thumbnail card
                        width: Math.min(580, Math.round(stage.width * 0.38))
                        height: Math.round(width * 0.625)
                        x: stage.width / 2 - width / 2 + delta * (width * 0.45)
                        y: stage.height / 2 - height / 2 - 24
                        z: 20 - Math.abs(delta)

                        // Selected item is largest; neighbors scale down progressively
                        scale: isSelected ? 1.0 : (Math.abs(delta) === 1 ? 0.78 : (Math.abs(delta) === 2 ? 0.62 : 0.48))
                        opacity: inRange ? (isSelected ? 1.0 : (Math.abs(delta) === 1 ? 0.70 : (Math.abs(delta) === 2 ? 0.40 : 0.15))) : 0
                        visible: opacity > 0.01

                        transform: Rotation {
                            origin.x: cardDelegate.width / 2
                            origin.y: cardDelegate.height / 2
                            axis { x: 0; y: 1; z: 0 }
                            angle: delta < 0 ? 32 : (delta > 0 ? -32 : 0)
                            Behavior on angle { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        }

                        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        // Card Surface
                        Item {
                            id: cardVisual
                            anchors.fill: parent

                            // Soft shadow for selected card
                            layer.enabled: cardDelegate.isSelected
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Theme.shadowColor
                                shadowBlur: 0.85
                                shadowVerticalOffset: 10
                                shadowHorizontalOffset: 0
                            }

                            Rectangle {
                                id: cardRect
                                anchors.fill: parent
                                radius: Theme.radiusXl
                                color: Theme.surfaceDeep
                                border.width: cardDelegate.isSelected ? 2 : 0
                                border.color: cardDelegate.isSelected ? Theme.brandAccent : "transparent"
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: cardDelegate.isSelected ? 2 : 0
                                    source: fileUrl
                                    sourceSize.width: 720
                                    sourceSize.height: 450
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                // Neighbor darkening overlay
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusXl
                                    color: "#000000"
                                    opacity: cardDelegate.isSelected ? 0.0 : (Math.abs(cardDelegate.delta) === 1 ? 0.28 : 0.55)
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }
                            }
                        }

                        // Small floating filename label under the selected wallpaper only
                        Text {
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                top: parent.bottom
                                topMargin: 20
                            }
                            visible: cardDelegate.isSelected
                            opacity: cardDelegate.isSelected ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            text: cardDelegate.fileName
                            color: Theme.textMain
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.fontSizeHeading
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onWheel: wheel => {
                                contentRoot.step(wheel.angleDelta.y > 0 ? -1 : 1)
                                wheel.accepted = true
                            }
                            onClicked: {
                                if (cardDelegate.delta === 0) contentRoot.applyWallpaper()
                                else root.currentIndex = cardDelegate.index
                            }
                        }
                    }
                }

                // Empty state fallback
                Text {
                    anchors.centerIn: parent
                    visible: wallpapers.count === 0
                    text: "No wallpapers found in ~/Pictures/Wallpapers"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSizeSubheading
                }
            }
        }
    }
}
