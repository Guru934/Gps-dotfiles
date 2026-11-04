// Island state: facelock — Live Howdy biometric status and diagnostic interface for GPS dynamic island.
// Displays honest system state (Howdy presence, PAM wiring, model enrollment, camera device).
// Provides user-triggered safe test verification and lock trigger.
// PAM remains authoritative for real authentication; this component does not grant authentication.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: st
    required property var core
    readonly property string key: "facelock"

    // System probe values (populated safely via non-root inspection)
    property bool howdyInstalled: false
    property bool pamWired: false
    property bool sddmWired: false
    property bool modelEnrolled: false
    property int modelCount: 0
    property string configuredDevice: "/dev/video0"
    property bool cameraAvailable: false
    property bool probeDone: false

    // Diagnostic test state: "idle" | "scanning" | "ok" | "reject"
    property string testState: "idle"
    property string testOutcome: ""

    readonly property bool active: core.mode === key
    readonly property bool testing: testState === "scanning"
    readonly property bool testOk: testState === "ok"
    readonly property bool testReject: testState === "reject"
    readonly property bool inspectView: testState === "idle" && (Boolean(core.hovered) || forceInspect)
    readonly property bool armedView: testState === "idle" && !inspectView
    property bool forceInspect: false

    readonly property string overallStatus: !howdyInstalled ? "unavailable"
        : !cameraAvailable ? "no_camera"
        : !modelEnrolled ? "not_enrolled"
        : !pamWired ? "unwired"
        : "ready"

    readonly property string statusLabel: overallStatus === "ready" ? "READY"
        : overallStatus === "unwired" ? "PAM SETUP NEEDED"
        : overallStatus === "not_enrolled" ? "NOT ENROLLED"
        : overallStatus === "no_camera" ? "CAMERA MISSING"
        : "UNAVAILABLE"

    readonly property color statusColor: overallStatus === "ready" ? core.teal
        : overallStatus === "unwired" ? core.amber
        : overallStatus === "not_enrolled" ? core.amber
        : core.coral

    readonly property real w: inspectView ? 380 : testReject ? 300 : (testing || testOk) ? 260 : 150
    readonly property real h: inspectView ? 142 : testReject ? 70 : (testing || testOk) ? 60 : 34
    readonly property color accent: testReject ? core.coral : statusColor

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: {
        core.register(key, st)
        refreshStatus()
    }

    onActiveChanged: {
        if (active) {
            refreshStatus()
        } else {
            forceInspect = false
            cancelTest()
        }
    }

    function tint(base, alpha) {
        return Qt.rgba(base.r, base.g, base.b, alpha)
    }

    function refreshStatus() {
        if (!probeProc.running) {
            probeProc.running = true
        }
    }

    function startTest() {
        if (testing) return
        testOutcome = ""
        testState = "scanning"
        testTimer.stop()
        testProc.running = true
    }

    function cancelTest() {
        if (testProc.running) {
            testProc.running = false
        }
        testState = "idle"
        testOutcome = ""
        testTimer.stop()
    }

    function lockSession() {
        Quickshell.execDetached(["gps-lock"])
    }

    // ── Non-root telemetry probe (reads standard files and configuration) ──
    Process {
        id: probeProc
        command: ["sh", "-c", '
            user="${USER:-$(whoami)}"
            howdy_bin=""
            command -v howdy >/dev/null 2>&1 && howdy_bin="1"
            pam_mod="0"
            { [ -f /usr/lib/security/pam_howdy.so ] || [ -f /lib/security/pam_howdy.so ]; } && pam_mod="1"

            pam_wired="0"
            grep -q pam_howdy /etc/pam.d/hyprlock 2>/dev/null && pam_wired="1"

            sddm_wired="0"
            grep -q pam_howdy /etc/pam.d/sddm 2>/dev/null && sddm_wired="1"

            model_file="/etc/howdy/models/${user}.dat"
            model_count="0"
            if [ -f "$model_file" ]; then
                model_count=$(grep -c \'"id":\' "$model_file" 2>/dev/null || echo "1")
            fi

            cam_dev=$(sed -n "s/^[[:space:]]*device_path[[:space:]]*=[[:space:]]*//p" /etc/howdy/config.ini 2>/dev/null | head -1 | tr -d " \r\n")
            [ -n "$cam_dev" ] || cam_dev="/dev/video0"

            cam_ok="0"
            [ -e "$cam_dev" ] && cam_ok="1"

            printf "HOWDY_OK=%s\nPAM_MOD=%s\nPAM_WIRED=%s\nSDDM_WIRED=%s\nMODELS=%s\nCAM_DEV=%s\nCAM_OK=%s\n" \
                "$howdy_bin" "$pam_mod" "$pam_wired" "$sddm_wired" "$model_count" "$cam_dev" "$cam_ok"
        ']
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (line.indexOf("HOWDY_OK=") === 0) {
                        st.howdyInstalled = line.substring(9) === "1"
                    } else if (line.indexOf("PAM_WIRED=") === 0) {
                        st.pamWired = line.substring(10) === "1"
                    } else if (line.indexOf("SDDM_WIRED=") === 0) {
                        st.sddmWired = line.substring(11) === "1"
                    } else if (line.indexOf("MODELS=") === 0) {
                        var cnt = parseInt(line.substring(7), 10) || 0
                        st.modelCount = cnt
                        st.modelEnrolled = cnt > 0
                    } else if (line.indexOf("CAM_DEV=") === 0) {
                        st.configuredDevice = line.substring(8)
                    } else if (line.indexOf("CAM_OK=") === 0) {
                        st.cameraAvailable = line.substring(7) === "1"
                    }
                }
                st.probeDone = true
            }
        }
    }

    // ── Safe user-level recognition test runner ──
    Process {
        id: testProc
        command: ["python3", "/usr/lib/howdy/compare.py", ("" + (Quickshell.env("USER") || "guru"))]
        onExited: (code, status) => {
            if (st.testState !== "scanning") return
            if (code === 0) {
                st.testState = "ok"
                st.testOutcome = "Face verified (diagnostic test)"
            } else if (code === 13) {
                st.testState = "reject"
                st.testOutcome = "Lighting too dark"
            } else {
                st.testState = "reject"
                st.testOutcome = "Not recognized / timed out"
            }
            testTimer.restart()
        }
    }

    Timer {
        id: testTimer
        interval: 3500
        repeat: false
        onTriggered: {
            st.testState = "idle"
            st.testOutcome = ""
        }
    }

    // ── Small local primitives ──
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 9
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component Ico: Text {
        property string name: ""
        property string alt: ""
        text: st.core.iconOk ? name : alt
        font.family: st.core.iconOk ? st.core.iconFont : st.core.uiFont
        font.pixelSize: 14
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Wireframe face tile with the laser sweep
    component ScanGlyph: Item {
        id: sg
        implicitWidth: 32
        implicitHeight: 32
        clip: true

        readonly property color bracketColor: st.tint(st.core.teal, 0.55)

        Rectangle {
            anchors.fill: parent
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }

        Ico {
            anchors.centerIn: parent
            name: "face"
            alt: "◉"
            font.pixelSize: 16
            color: st.tint(st.core.teal, 0.70)
        }

        Rectangle { x: 5; y: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; y: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; y: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; y: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { x: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 6; height: 1.5; radius: 0.75; color: sg.bracketColor }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5; width: 1.5; height: 6; radius: 0.75; color: sg.bracketColor }

        Item {
            id: scanLaser
            x: 4
            y: 5
            width: sg.width - 8
            height: 4
            visible: st.testing

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 1
                radius: 0.5
                color: st.core.teal
                opacity: 0.35
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 2
                radius: 1
                color: st.core.teal
                opacity: 0.9
            }

            SequentialAnimation on y {
                loops: Animation.Infinite
                running: st.testing
                NumberAnimation { from: 5; to: 23; duration: 750; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 23; to: 5; duration: 750; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ═══════════ A · IDLE ARMED PILL (150×34) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.armedView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                st.forceInspect = !st.forceInspect
                st.refreshStatus()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 4

            Ico {
                Layout.alignment: Qt.AlignVCenter
                name: "face"
                alt: "◉"
                font.pixelSize: 15
                color: st.statusColor
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 5
                Layout.preferredHeight: 5
                radius: 2.5
                color: st.statusColor
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "FACE"
                color: st.core.text
                font.family: st.core.monoFont
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 0.4
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: armedBadgeText.implicitWidth + 8
                Layout.preferredHeight: 14
                radius: 7
                color: st.tint(st.statusColor, 0.12)
                border.width: 1
                border.color: st.tint(st.statusColor, 0.35)

                Text {
                    id: armedBadgeText
                    anchors.centerIn: parent
                    text: st.overallStatus === "ready" ? "ARMED" : (st.overallStatus === "unwired" ? "PAM" : "INFO")
                    color: st.statusColor
                    font.family: st.core.monoFont
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 0.4
                }
            }
        }
    }

    // ═══════════ B · INSPECTION & CONTROL CARD (380×142) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.inspectView ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 5

            // Top row: Identity and honest live status badge
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    Ico {
                        anchors.centerIn: parent
                        name: "face"
                        alt: "◉"
                        font.pixelSize: 13
                        color: st.statusColor
                    }
                }

                Txt {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "Howdy Face Authentication"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: inspectBadgeText.implicitWidth + 10
                    Layout.preferredHeight: 18
                    radius: 9
                    color: st.tint(st.statusColor, 0.12)
                    border.width: 1
                    border.color: st.tint(st.statusColor, 0.35)

                    Text {
                        id: inspectBadgeText
                        anchors.centerIn: parent
                        text: st.statusLabel
                        color: st.statusColor
                        font.family: st.core.monoFont
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 0.4
                    }
                }
            }

            // Telemetry line 1: Camera & Hardware
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                spacing: 6

                Ico {
                    Layout.alignment: Qt.AlignVCenter
                    name: "videocam"
                    alt: "C"
                    font.pixelSize: 11
                    color: st.cameraAvailable ? st.core.teal : st.core.coral
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Camera: " + (st.configuredDevice ? st.configuredDevice.split("/").pop() : "None")
                          + (st.cameraAvailable ? " (online)" : " (offline)")
                          + " · RGB webcam (no hardware IR)"
                    font.pixelSize: 9
                    color: st.cameraAvailable ? st.core.text : st.core.coral
                }
            }

            // Telemetry line 2: Models & PAM integration status
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                spacing: 6

                Ico {
                    Layout.alignment: Qt.AlignVCenter
                    name: "verified_user"
                    alt: "V"
                    font.pixelSize: 11
                    color: st.pamWired ? st.core.teal : st.core.amber
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Models: " + st.modelCount + " enrolled · Lockscreen PAM: "
                          + (st.pamWired ? "wired" : "not wired")
                          + " · Login: " + (st.sddmWired ? "SDDM wired" : "unwired")
                    font.pixelSize: 9
                }
            }

            // Real Action Row: Safe test action & Lock screen trigger
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 8

                // Button 1: Safe Diagnostic Scan
                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    radius: 12
                    color: testBtnMouse.containsMouse ? st.tint(st.core.teal, 0.22) : st.tint(st.core.teal, 0.12)
                    border.width: 1
                    border.color: st.tint(st.core.teal, 0.40)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Ico {
                            name: "center_focus_weak"
                            alt: "◎"
                            font.pixelSize: 12
                            color: st.core.teal
                        }

                        Text {
                            text: "TEST SCAN"
                            color: st.core.text
                            font.family: st.core.monoFont
                            font.pixelSize: 8
                            font.bold: true
                            font.letterSpacing: 0.4
                        }
                    }

                    MouseArea {
                        id: testBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.startTest()
                    }
                }

                // Button 2: Real Lock Screen trigger
                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    radius: 12
                    color: lockBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Ico {
                            name: "lock"
                            alt: "L"
                            font.pixelSize: 12
                            color: st.core.text
                        }

                        Text {
                            text: "LOCK NOW"
                            color: st.core.text
                            font.family: st.core.monoFont
                            font.pixelSize: 8
                            font.bold: true
                            font.letterSpacing: 0.4
                        }
                    }

                    MouseArea {
                        id: lockBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.lockSession()
                    }
                }

                Mono {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "PAM authoritative"
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 8
                    color: st.core.dim
                }
            }

            // Security note footer
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
                spacing: 4

                Ico {
                    Layout.alignment: Qt.AlignVCenter
                    name: "info"
                    alt: "i"
                    font.pixelSize: 9
                    color: st.core.dim
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Password authentication is always preserved as primary fallback"
                    font.pixelSize: 8
                    color: st.core.dim
                }
            }
        }
    }

    // ═══════════ C · LIVE TEST SCANNING VIEW (260×60) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.testing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            ScanGlyph {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Txt {
                        text: "SCANNING FACE"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: st.core.teal
                    }
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Look at camera · Test only"
                    font.pixelSize: 8
                    color: st.core.dim
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, 0.10)

                Ico {
                    anchors.centerIn: parent
                    name: "close"
                    alt: "×"
                    font.pixelSize: 12
                    color: st.core.text
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.cancelTest()
                }
            }
        }
    }

    // ═══════════ D · TEST SUCCESS VIEW (260×60) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.testOk ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 9
                color: st.core.teal

                Ico {
                    anchors.centerIn: parent
                    name: "check"
                    alt: "✓"
                    font.pixelSize: 18
                    color: st.core.pillColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Txt {
                    Layout.fillWidth: true
                    text: "FACE RECOGNIZED"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: st.core.teal
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Diagnostic match · Ready"
                    font.pixelSize: 8
                    color: st.core.dim
                }
            }
        }
    }

    // ═══════════ E · TEST REJECT VIEW (300×70) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.testReject ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 9
                color: st.tint(st.core.coral, 0.16)
                border.width: 1
                border.color: st.tint(st.core.coral, 0.35)

                Ico {
                    anchors.centerIn: parent
                    name: "close"
                    alt: "×"
                    font.pixelSize: 18
                    color: st.core.coral
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Txt {
                    Layout.fillWidth: true
                    text: "RECOGNITION FAILED"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: st.core.coral
                }

                Mono {
                    Layout.fillWidth: true
                    text: st.testOutcome || "Face not matched or timed out"
                    font.pixelSize: 8
                    color: st.core.text
                }

                Mono {
                    Layout.fillWidth: true
                    text: "Password fallback remains available"
                    font.pixelSize: 8
                    color: st.core.dim
                }
            }
        }
    }
}
