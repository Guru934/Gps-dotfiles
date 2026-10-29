import QtQuick
import QtQuick.Controls
import "../Theme.js" as Theme

Rectangle {
    id: root

    property alias text: innerInput.text
    property bool isError: false
    property bool showPassword: false
    property bool isLoading: false
    property bool capsLock: (typeof keyboard !== "undefined" && keyboard && typeof keyboard.capsLock === "boolean") ? keyboard.capsLock : false

    signal submitted(string password)

    width: 320
    height: 46
    radius: 12
    color: Theme.palette.track
    border.color: isError ? Theme.palette.statusDanger : (innerInput.activeFocus ? Theme.palette.brandAccent : Theme.palette.outlineSoft)
    border.width: innerInput.activeFocus || isError ? 1.5 : 1

    Behavior on border.color { ColorAnimation { duration: 150 } }

    function forceInputFocus() {
        innerInput.forceActiveFocus()
    }

    function clear() {
        innerInput.text = ""
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 8

        // Lock Icon
        Image {
            id: lockIcon
            source: Qt.resolvedUrl("../assets/lock.svg")
            width: 18
            height: 18
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            opacity: 0.7
        }

        // Text input field
        TextInput {
            id: innerInput
            width: parent.width - lockIcon.width - (revealBtn.visible ? revealBtn.width : 0) - submitBtn.width - 32
            anchors.verticalCenter: parent.verticalCenter
            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
            font.pixelSize: 14
            font.family: Theme.palette.fontMono
            color: Theme.palette.textMain
            clip: true
            selectByMouse: true
            renderType: Text.NativeRendering
            enabled: !root.isLoading

            Text {
                anchors.fill: parent
                text: "Password"
                font: innerInput.font
                color: Theme.palette.textDim
                visible: innerInput.text.length === 0 && !innerInput.activeFocus
                renderType: Text.NativeRendering
            }

            Keys.onReturnPressed: {
                if (innerInput.text.length > 0 && !root.isLoading) {
                    root.submitted(innerInput.text)
                }
            }

            Keys.onEnterPressed: {
                if (innerInput.text.length > 0 && !root.isLoading) {
                    root.submitted(innerInput.text)
                }
            }
        }

        // Password reveal toggle
        Rectangle {
            id: revealBtn
            width: 26
            height: 26
            radius: 13
            anchors.verticalCenter: parent.verticalCenter
            color: revealMouse.containsMouse ? Theme.palette.surfaceHigh : "transparent"
            visible: innerInput.text.length > 0

            Image {
                anchors.centerIn: parent
                source: root.showPassword ? Qt.resolvedUrl("../assets/eye-closed.svg") : Qt.resolvedUrl("../assets/eye-open.svg")
                width: 16
                height: 16
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: revealMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showPassword = !root.showPassword
            }
        }

        // Submit Button
        Rectangle {
            id: submitBtn
            width: 30
            height: 30
            radius: 15
            anchors.verticalCenter: parent.verticalCenter
            color: innerInput.text.length > 0 ? (submitMouse.containsMouse ? Theme.palette.accentPrimary : Theme.palette.brandAccent) : Theme.palette.surfaceBase
            opacity: innerInput.text.length > 0 ? 1 : 0.4

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: root.isLoading ? "…" : "→"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: innerInput.text.length > 0 ? Theme.palette.brandAccentFg : Theme.palette.textMuted
            }

            MouseArea {
                id: submitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: innerInput.text.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: innerInput.text.length > 0 && !root.isLoading
                onClicked: root.submitted(innerInput.text)
            }
        }
    }
}
