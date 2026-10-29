import QtQuick
import QtQuick.Controls
import "../Theme.js" as Theme

Row {
    id: root
    spacing: 12

    property var sddmObj: (typeof sddm !== "undefined" && sddm) ? sddm : null
    property bool canPower: sddmObj ? (typeof sddmObj.canPowerOff === "boolean" ? sddmObj.canPowerOff : true) : true
    property bool canReboot: sddmObj ? (typeof sddmObj.canReboot === "boolean" ? sddmObj.canReboot : true) : true
    property bool canSuspend: sddmObj ? (typeof sddmObj.canSuspend === "boolean" ? sddmObj.canSuspend : true) : true

    // Suspend button
    Rectangle {
        id: suspendBtn
        visible: root.canSuspend
        width: 36
        height: 36
        radius: 18
        color: suspendMouse.containsMouse ? Theme.palette.surfaceHigh : Theme.palette.surface
        border.color: suspendMouse.containsMouse ? Theme.palette.accentSecondary : Theme.palette.outlineSoft
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Image {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/suspend.svg")
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: suspendMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sddmObj && typeof root.sddmObj.suspend === "function") {
                    root.sddmObj.suspend()
                } else {
                    console.log("SDDM suspend requested (preview mode)")
                }
            }
        }
    }

    // Reboot button
    Rectangle {
        id: rebootBtn
        visible: root.canReboot
        width: 36
        height: 36
        radius: 18
        color: rebootMouse.containsMouse ? Theme.palette.surfaceHigh : Theme.palette.surface
        border.color: rebootMouse.containsMouse ? Theme.palette.brandAccent : Theme.palette.outlineSoft
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Image {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/reboot.svg")
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: rebootMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sddmObj && typeof root.sddmObj.reboot === "function") {
                    root.sddmObj.reboot()
                } else {
                    console.log("SDDM reboot requested (preview mode)")
                }
            }
        }
    }

    // Power off button
    Rectangle {
        id: powerBtn
        visible: root.canPower
        width: 36
        height: 36
        radius: 18
        color: powerMouse.containsMouse ? Theme.palette.surfaceHigh : Theme.palette.surface
        border.color: powerMouse.containsMouse ? Theme.palette.statusDanger : Theme.palette.outlineSoft
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Image {
            anchors.centerIn: parent
            source: Qt.resolvedUrl("../assets/power.svg")
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: powerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.sddmObj && typeof root.sddmObj.powerOff === "function") {
                    root.sddmObj.powerOff()
                } else {
                    console.log("SDDM powerOff requested (preview mode)")
                }
            }
        }
    }
}
