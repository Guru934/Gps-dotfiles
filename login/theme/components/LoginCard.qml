import QtQuick
import QtQuick.Controls
import "../Theme.js" as Theme

GlassCard {
    id: root

    property alias currentUsername: userSelector.currentUsername
    property alias sessionIndex: sessionSelector.currentIndex
    property alias isError: passwordInput.isError
    property alias isLoading: passwordInput.isLoading
    property string errorMessage: ""
    property string statusMessage: ""

    signal loginRequested(string username, string password, int sessionIndex)

    width: 380
    height: 380
    cornerRadius: 20
    baseColor: Theme.palette.surface
    borderColor: Theme.palette.outlineSoft

    function triggerShake() {
        shakeAnim.restart()
    }

    function handleLoginFailed(msg) {
        root.isLoading = false
        root.isError = true
        root.errorMessage = msg && msg !== "" ? msg : "Authentication failed. Please check password."
        root.statusMessage = ""
        passwordInput.clear()
        passwordInput.forceInputFocus()
        root.triggerShake()
    }

    function handleLoginSucceeded() {
        root.isLoading = false
        root.isError = false
        root.errorMessage = ""
        root.statusMessage = "Authenticated. Starting session…"
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: -12; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 12; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: -8; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 8; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: -4; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 4; duration: 40; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40; easing.type: Easing.OutQuad }
    }

    Column {
        anchors.centerIn: parent
        spacing: 16
        width: 330

        // User profile and switcher
        UserSelector {
            id: userSelector
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Session selection pill
        SessionSelector {
            id: sessionSelector
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Password input field
        PasswordInput {
            id: passwordInput
            anchors.horizontalCenter: parent.horizontalCenter
            onSubmitted: function(pass) {
                root.isError = false
                root.errorMessage = ""
                root.isLoading = true
                root.statusMessage = "Authenticating…"
                root.loginRequested(userSelector.currentUsername, pass, sessionSelector.currentIndex)
            }
        }

        // Caps Lock Warning
        Rectangle {
            id: capsWarning
            visible: passwordInput.capsLock
            width: parent.width
            height: 24
            radius: 6
            color: Qt.rgba(1, 0.83, 0.48, 0.12)
            border.color: Theme.palette.statusWarn
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "⇪"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: Theme.palette.statusWarn
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Caps Lock is ON"
                    font.pixelSize: 11
                    font.family: Theme.palette.fontUi
                    font.weight: Font.Medium
                    color: Theme.palette.statusWarn
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Error Feedback Message
        Text {
            id: errorText
            visible: root.isError && root.errorMessage !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.errorMessage
            font.pixelSize: 12
            font.family: Theme.palette.fontUi
            color: Theme.palette.statusDanger
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: parent.width
            renderType: Text.NativeRendering
        }

        // Status Message (e.g. Authenticating...)
        Text {
            id: statusText
            visible: !root.isError && root.statusMessage !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.statusMessage
            font.pixelSize: 12
            font.family: Theme.palette.fontUi
            color: Theme.palette.accentPrimary
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
        }
    }

    Component.onCompleted: {
        passwordInput.forceInputFocus()
    }
}
