import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel
import qs.config

PanelWindow {
    id: root

    property var hub: null
    property bool isOpen: false
    property int currentIndex: 0
    readonly property int visibleRadius: 2
    readonly property string wallpaperDirectory: "file:///home/rice/Pictures/Wallpapers"

    function toggle() { root.isOpen = !root.isOpen }
    function close() { root.isOpen = false }
    function step(delta) {
        if (wallpapers.count === 0) return
        root.currentIndex = (root.currentIndex + delta + wallpapers.count) % wallpapers.count
    }
    function applyWallpaper() {
        if (wallpapers.count === 0) return
        const path = wallpapers.get(root.currentIndex, "filePath")
        if (!path) return
        Quickshell.execDetached(["awww", "img", path, "--transition-type", "outer", "--transition-pos", "0.92,0.06", "--transition-fps", "165", "--transition-duration", "1.1"])
        Quickshell.execDetached(["/home/rice/Projects/my-rice/scripts/extract-theme.py"])
        root.close()
    }

    FolderListModel {
        id: wallpapers
        folder: root.wallpaperDirectory
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    anchors { horizontalCenter: true; verticalCenter: true }
    implicitWidth: 840
    implicitHeight: 520
    color: "transparent"
    visible: root.isOpen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Shortcut { sequence: "Super+W"; context: Qt.ApplicationShortcut; onActivated: root.toggle() }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: "#F20F131C"
        border.width: 1
        border.color: Theme.brandAccent

        FocusScope {
            id: keyboardTrap
            anchors.fill: parent
            focus: root.isOpen
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left) { root.step(-1); event.accepted = true }
                else if (event.key === Qt.Key_Right) { root.step(1); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applyWallpaper(); event.accepted = true }
                else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                Row {
                    width: parent.width
                    Text { text: "WALLPAPER CAROUSEL"; color: Theme.textMain; font.family: Theme.fontUi; font.pixelSize: 15; font.bold: true }
                    Item { width: parent.width - 250; height: 1 }
                    Text { text: "← →  SELECT    ENTER  APPLY    ESC  CLOSE"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 8 }
                }

                Item {
                    id: stage
                    width: parent.width
                    height: parent.height - 84

                    Repeater {
                        model: wallpapers
                        delegate: Item {
                            required property int index
                            required property url fileUrl
                            readonly property int delta: index - root.currentIndex
                            readonly property bool inRange: Math.abs(delta) <= root.visibleRadius
                            width: 300
                            height: 300
                            x: stage.width / 2 - width / 2 + delta * 190
                            y: stage.height / 2 - height / 2
                            z: 10 - Math.abs(delta)
                            scale: delta === 0 ? 1.0 : 0.82
                            opacity: inRange ? (delta === 0 ? 1 : 0.72) : 0
                            visible: inRange
                            transform: Rotation {
                                origin.x: 150
                                origin.y: 150
                                axis { x: 0; y: 1; z: 0 }
                                angle: delta < 0 ? 36 : delta > 0 ? -36 : 0
                            }
                            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: Theme.card
                                border.width: delta === 0 ? 2 : 1
                                border.color: delta === 0 ? Theme.brandAccent : Theme.border
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    source: fileUrl
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }
                                Rectangle { anchors.fill: parent; color: delta === 0 ? "#22000000" : "#66000000" }
                                Text { anchors { left: parent.left; bottom: parent.bottom; leftMargin: 14; bottomMargin: 12 } text: fileUrl.toString().split("/").pop(); color: "#F4FFFFFF"; font.family: Theme.fontUi; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width - 28 }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onWheel: wheel => { root.step(wheel.angleDelta.y > 0 ? -1 : 1); wheel.accepted = true }
                                    onClicked: { if (delta === 0) root.applyWallpaper(); else root.currentIndex = index }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: wallpapers.count === 0
                        text: "No wallpapers found in ~/Pictures/Wallpapers"
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }
                }

                Row {
                    width: parent.width
                    Text { text: (root.currentIndex + 1) + " / " + wallpapers.count; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
                    Item { width: parent.width - 150; height: 1 }
                    Text { text: "AETHERIC DARK THEME  ·  165Hz TRANSITION"; color: Theme.brandAccent; font.family: Theme.fontMono; font.pixelSize: 8 }
                }
            }
        }
    }
}
