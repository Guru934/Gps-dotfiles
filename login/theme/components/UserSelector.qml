import QtQuick
import QtQuick.Controls
import "../Theme.js" as Theme

Item {
    id: root

    property var model: (typeof userModel !== "undefined" && userModel) ? userModel : null
    property int currentIndex: (model && typeof model.lastIndex === "number") ? Math.max(0, model.lastIndex) : 0
    property int userCount: model ? (typeof model.count === "number" ? model.count : 0) : 1

    property string currentUsername: ""
    property string currentRealName: ""
    property string currentAvatar: ""

    width: 320
    height: 110

    function updateUser() {
        if (root.model && root.userCount > 0) {
            var idx = Math.max(0, Math.min(root.currentIndex, root.userCount - 1))
            var name = root.model.data(root.model.index(idx, 0), Qt.UserRole + 1) // Qt.UserRole + 1 is name in SDDM
            var realName = root.model.data(root.model.index(idx, 0), Qt.UserRole + 2) // realName
            var icon = root.model.data(root.model.index(idx, 0), Qt.UserRole + 4) // icon

            root.currentUsername = name ? String(name) : (idx === 0 ? "rice" : "user")
            root.currentRealName = realName ? String(realName) : root.currentUsername
            root.currentAvatar = icon ? String(icon) : ""
        } else {
            root.currentUsername = "rice"
            root.currentRealName = "GPS User"
            root.currentAvatar = ""
        }
    }

    onCurrentIndexChanged: updateUser()
    Component.onCompleted: updateUser()

    function nextUser() {
        if (root.userCount > 1) {
            root.currentIndex = (root.currentIndex + 1) % root.userCount
        }
    }

    function prevUser() {
        if (root.userCount > 1) {
            root.currentIndex = (root.currentIndex - 1 + root.userCount) % root.userCount
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        // Left switcher arrow (if multi-user)
        Rectangle {
            id: prevBtn
            visible: root.userCount > 1
            width: 28
            height: 28
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            color: prevMouse.containsMouse ? Theme.palette.surfaceHigh : "transparent"
            border.color: prevMouse.containsMouse ? Theme.palette.outlineSoft : "transparent"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "‹"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: prevMouse.containsMouse ? Theme.palette.brandAccent : Theme.palette.textMuted
            }

            MouseArea {
                id: prevMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.prevUser()
            }
        }

        // Avatar container
        Rectangle {
            id: avatarContainer
            width: 64
            height: 64
            radius: 32
            color: Theme.palette.surfaceBase
            border.color: Theme.palette.brandAccent
            border.width: 1.5

            Image {
                id: avatarImage
                anchors.fill: parent
                anchors.margins: 2
                source: root.currentAvatar !== "" ? root.currentAvatar : Qt.resolvedUrl("../assets/user-avatar.svg")
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Error && source !== Qt.resolvedUrl("../assets/user-avatar.svg")) {
                        source = Qt.resolvedUrl("../assets/user-avatar.svg")
                    }
                }
            }

            // Fallback initials if image not ready
            Text {
                anchors.centerIn: parent
                visible: avatarImage.status !== Image.Ready
                text: root.currentUsername.length > 0 ? root.currentUsername.charAt(0).toUpperCase() : "U"
                font.pixelSize: 26
                font.weight: Font.DemiBold
                font.family: Theme.palette.fontUi
                color: Theme.palette.accentPrimary
            }
        }

        // Name and username column
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: 150

            Text {
                text: root.currentRealName !== "" ? root.currentRealName : root.currentUsername
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.family: Theme.palette.fontUi
                color: Theme.palette.textMain
                elide: Text.ElideRight
                width: parent.width
                renderType: Text.NativeRendering
            }

            Text {
                text: "@" + root.currentUsername
                font.pixelSize: 12
                font.family: Theme.palette.fontMono
                color: Theme.palette.textMuted
                elide: Text.ElideRight
                width: parent.width
                renderType: Text.NativeRendering
            }
        }

        // Right switcher arrow (if multi-user)
        Rectangle {
            id: nextBtn
            visible: root.userCount > 1
            width: 28
            height: 28
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            color: nextMouse.containsMouse ? Theme.palette.surfaceHigh : "transparent"
            border.color: nextMouse.containsMouse ? Theme.palette.outlineSoft : "transparent"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "›"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: nextMouse.containsMouse ? Theme.palette.brandAccent : Theme.palette.textMuted
            }

            MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.nextUser()
            }
        }
    }
}
