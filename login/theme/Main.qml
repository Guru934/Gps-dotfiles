import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme
import "components"

Rectangle {
    id: root

    width: 1280
    height: 800
    color: Theme.palette.surfaceDeep

    property bool isPreview: (typeof sddm === "undefined" || !sddm || (typeof sddm.canPowerOff === "boolean" && !sddm.canPowerOff))
    property string activeLayout: (typeof keyboard !== "undefined" && keyboard && keyboard.layouts && keyboard.layouts.length > 0 && typeof keyboard.currentLayout === "number") ? keyboard.layouts[keyboard.currentLayout].shortName : "US"

    // Background Wallpaper
    Image {
        id: bgImage
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/background.jpg")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true

        // Dark cinema scrim for guaranteed text contrast
        Rectangle {
            anchors.fill: parent
            color: Theme.palette.surfaceDeep
            opacity: 0.55
        }

        // Subtle gradient vignette
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.07, 0.11, 0.4) }
                GradientStop { position: 0.5; color: Qt.rgba(0.06, 0.07, 0.11, 0.2) }
                GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.07, 0.11, 0.6) }
            }
        }
    }

    // Top Header Bar
    Item {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60
        anchors.margins: 20

        // GPS Desktop Branding Pill
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: Theme.palette.brandAccent
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "GPS Desktop"
                font.pixelSize: 13
                font.family: Theme.palette.fontUi
                font.weight: Font.Medium
                color: Theme.palette.textMuted
                renderType: Text.NativeRendering
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Keyboard Layout Indicator (if available)
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 24
            radius: 6
            color: Theme.palette.surfaceBase
            border.color: Theme.palette.outlineSoft
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: root.activeLayout
                font.pixelSize: 11
                font.family: Theme.palette.fontMono
                font.weight: Font.DemiBold
                color: Theme.palette.textMain
                renderType: Text.NativeRendering
            }
        }
    }

    // Center Stage: Clock & Login Card
    Column {
        id: centerStage
        anchors.centerIn: parent
        spacing: 20

        Clock {
            id: clockWidget
            anchors.horizontalCenter: parent.horizontalCenter
        }

        LoginCard {
            id: loginCard
            anchors.horizontalCenter: parent.horizontalCenter
            onLoginRequested: function(username, password, sessionIdx) {
                if (typeof sddm !== "undefined" && sddm && typeof sddm.login === "function") {
                    sddm.login(username, password, sessionIdx)
                } else {
                    console.log("SDDM login requested:", username, "(session", sessionIdx, ")")
                    // Standalone test fallback
                    fakeAuthTimer.restart()
                }
            }
        }
    }

    // Standalone test auth simulator (only fires if sddm is undefined)
    Timer {
        id: fakeAuthTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (typeof sddm === "undefined" || !sddm) {
                loginCard.handleLoginFailed("SDDM greeter not connected (Standalone Preview Mode)")
            }
        }
    }

    // Bottom Footer Bar
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 50
        anchors.margins: 20

        // Status or Session Info
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "CachyOS • Hyprland Desktop"
            font.pixelSize: 12
            font.family: Theme.palette.fontUi
            color: Theme.palette.textDim
            renderType: Text.NativeRendering
        }

        // Power Actions
        PowerBar {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // SDDM Greeter Event Listeners
    Connections {
        target: (typeof sddm !== "undefined" && sddm) ? sddm : null
        ignoreUnknownSignals: true

        function onLoginFailed() {
            loginCard.handleLoginFailed("")
        }

        function onLoginSucceeded() {
            loginCard.handleLoginSucceeded()
        }

        function onInformationMessage(message) {
            console.log("SDDM info:", message)
        }
    }
}
