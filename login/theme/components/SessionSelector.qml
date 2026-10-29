import QtQuick
import QtQuick.Controls
import "../Theme.js" as Theme

Item {
    id: root

    property var model: (typeof sessionModel !== "undefined" && sessionModel) ? sessionModel : null
    property int currentIndex: (model && typeof model.lastIndex === "number") ? Math.max(0, model.lastIndex) : 0
    property int sessionCount: model ? (typeof model.count === "number" ? model.count : 0) : 1
    property string currentSessionName: "Hyprland"
    property bool expanded: false

    width: 260
    height: 36

    function updateSessionName() {
        if (root.model && root.sessionCount > 0) {
            var idx = Math.max(0, Math.min(root.currentIndex, root.sessionCount - 1))
            var name = root.model.data(root.model.index(idx, 0), Qt.UserRole + 1)
            root.currentSessionName = name ? String(name) : "Desktop Session"
        } else {
            root.currentSessionName = "Hyprland"
        }
    }

    onCurrentIndexChanged: updateSessionName()
    Component.onCompleted: updateSessionName()

    function selectIndex(idx) {
        root.currentIndex = idx
        root.expanded = false
        updateSessionName()
    }

    Rectangle {
        id: sessionButton
        anchors.fill: parent
        radius: 18
        color: sessionMouse.containsMouse ? Theme.palette.surfaceHigh : Theme.palette.surfaceBase
        border.color: sessionMouse.containsMouse ? Theme.palette.brandAccent : Theme.palette.outlineSoft
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Row {
            anchors.centerIn: parent
            spacing: 8

            Image {
                source: Qt.resolvedUrl("../assets/session-hyprland.svg")
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
            }

            Text {
                text: root.currentSessionName
                font.pixelSize: 13
                font.family: Theme.palette.fontUi
                font.weight: Font.Medium
                color: Theme.palette.textMain
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.sessionCount > 1
                text: root.expanded ? "▲" : "▼"
                font.pixelSize: 9
                color: Theme.palette.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: sessionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sessionCount > 1) {
                    root.expanded = !root.expanded
                }
            }
        }
    }

    // Dropdown list when expanded
    Rectangle {
        id: dropdownMenu
        visible: root.expanded
        z: 99
        anchors.top: sessionButton.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: Math.min(180, root.sessionCount * 34 + 8)
        radius: 12
        color: Theme.palette.surfaceDeep
        border.color: Theme.palette.outlineSoft
        border.width: 1
        clip: true

        ListView {
            id: sessionList
            anchors.fill: parent
            anchors.margins: 4
            model: root.sessionCount
            clip: true
            boundsBehavior: ListView.StopAtBounds

            delegate: Rectangle {
                id: delegateItem
                required property int index

                width: parent ? parent.width : 252
                height: 32
                radius: 8
                color: itemMouse.containsMouse ? Theme.palette.surfaceHigh : (delegateItem.index === root.currentIndex ? Theme.palette.surfaceBase : "transparent")
                border.color: delegateItem.index === root.currentIndex ? Theme.palette.brandAccent : "transparent"
                border.width: 1

                function getSessionName(i) {
                    if (root.model) {
                        var name = root.model.data(root.model.index(i, 0), Qt.UserRole + 1)
                        if (name) return String(name)
                    }
                    return "Session " + (i + 1)
                }

                Text {
                    anchors.centerIn: parent
                    text: delegateItem.getSessionName(delegateItem.index)
                    font.pixelSize: 12
                    font.family: Theme.palette.fontUi
                    color: delegateItem.index === root.currentIndex ? Theme.palette.brandAccent : Theme.palette.textMain
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectIndex(delegateItem.index)
                }
            }
        }
    }
}
