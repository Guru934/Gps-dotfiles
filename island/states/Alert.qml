// Island state: alert — persistent alert pill (270×40) · expanded permission dialog (490×150) · multi-agent stack (490×190) · resolved flash (200×40)
// Live coding-agent permission telemetry from $XDG_RUNTIME_DIR/pet/alerts.jsonl via Island.qml (`core`).
import QtQuick
import QtQuick.Layouts
import "PetSprites.js" as S
import "PetFx.js" as PetFx

Item {
    id: st
    required property var core
    readonly property string key: "alert"

    readonly property bool active: core.mode === key
    readonly property var list: core.alerts || []
    readonly property int count: list.length
    readonly property var first: count > 0 ? list[0] : ({ tool: "", title: "", detail: "", cwd: "", addr: "", ws: 0, ts: 0, id: "" })
    readonly property bool expanded: core.hovered || Boolean(core.alertExpanded)

    readonly property bool showResolved: count === 0 && Boolean(core.alertResolvedOn)
    readonly property bool showMulti: count > 1 && expanded
    readonly property bool showSingleExpanded: count === 1 && expanded
    readonly property bool showCompact: count >= 1 && !expanded

    readonly property string firstKey: count > 0
        ? String(first.id || first.ts || (first.tool + first.title + first.detail + count)) : ""
    property string reactedKey: ""
    property double jumpStart: -1
    readonly property bool petJumping: count > 0 && PetFx.jumping(jumpStart, core.petTick)
    readonly property real petLift: PetFx.lift(jumpStart, core.petTick)
    readonly property string petPose: petJumping ? "alert" : "sit"
    function reactPet() {
        if (!visible || firstKey === "") return
        if (firstKey === reactedKey) return
        reactedKey = firstKey
        jumpStart = core.petTick
    }
    onFirstKeyChanged: if (firstKey === "") { reactedKey = ""; jumpStart = -1 } else reactPet()
    onVisibleChanged: if (!visible) jumpStart = -1; else reactPet()

    readonly property real w: showResolved ? 200 : (showMulti || showSingleExpanded) ? 490 : 270
    readonly property real h: showResolved ? 40 : showMulti ? 190 : showSingleExpanded ? 150 : 40
    readonly property color tone: showResolved ? core.teal : showMulti ? core.lav : core.coral
    readonly property color accent: tone

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function headlineText(a) {
        if (!a) return ""
        return a.tool ? core.label(a.tool) + " needs permission" : "Permission requested"
    }

    // Combines title + detail just like original Alert.qml (`(a.title ? a.title + "  " : "") + a.detail`)
    function cmdText(a) {
        if (!a) return ""
        const t = a.title ? String(a.title).trim() : ""
        const d = a.detail ? String(a.detail).trim() : (a.cmd ? String(a.cmd).trim() : (a.command ? String(a.command).trim() : ""))
        if (t !== "" && d !== "") return t + "  " + d
        return d !== "" ? d : t
    }

    function canJump(a) {
        if (!a) return false
        return core.canJump(a)
    }

    function canRespond(a) {
        return !!a && a.respondable === true && typeof a.token === "string"
            && a.token !== "" && core.alertResponseIds.indexOf(a.id) < 0
    }

    function locBadge(a) {
        if (!a) return ""
        const parts = []
        const proj = core.project(a.cwd)
        if (proj !== "") parts.push(proj)
        if (a.ws !== undefined && a.ws !== null && String(a.ws) !== "" && Number(a.ws) > 0)
            parts.push("ws " + a.ws)
        return parts.join(" · ")
    }

    function metaFooter(a) {
        if (!a) return ""
        const parts = []
        if (a.id !== undefined && a.id !== null && String(a.id) !== "")
            parts.push("REQ_ID: #" + String(a.id))
        if (a.pid !== undefined && a.pid !== null && String(a.pid) !== "")
            parts.push("PID: " + String(a.pid))
        if (a.session !== undefined && a.session !== null && String(a.session) !== "")
            parts.push("SES: " + String(a.session))
        if (a.ts > 0)
            parts.push("WAIT: " + core.waited(a.ts))
        return parts.join(" · ")
    }

    function jumpHint(a) {
        if (a && a.ws !== undefined && a.ws !== null && String(a.ws) !== "" && Number(a.ws) > 0)
            return "[Super+" + a.ws + "] ⏎"
        return "[Enter] ⏎"
    }

    function rowTone(idx, a) {
        const t = a && a.tool ? String(a.tool).toLowerCase() : ""
        if (t === "opencode") return core.amber
        if (idx % 2 === 1) return core.amber
        return core.coral
    }

    function rowIcon(a) {
        const t = a && a.tool ? String(a.tool).toLowerCase() : ""
        return t === "opencode" ? "deployed_code" : "terminal"
    }

    // Parse command into up to 4 coloured syntax spans without HTML injection
    function cmdParts(raw) {
        const s = (raw || "").trim()
        if (s === "") return { bin: "", sub: "", arg: "", tail: "" }
        const tok = s.split(/\s+/)
        const bin = tok[0] || ""
        const sub = tok.length > 1 ? (" " + tok[1]) : ""
        const arg = tok.length > 2 ? (" " + tok[2]) : ""
        const tail = tok.length > 3 ? (" " + tok.slice(3).join(" ")) : ""
        return { bin: bin, sub: sub, arg: arg, tail: tail }
    }

    onActiveChanged: {
        if (active && expanded) keyFocus.forceActiveFocus()
    }
    onExpandedChanged: {
        if (active && expanded) keyFocus.forceActiveFocus()
    }

    Item {
        id: keyFocus
        anchors.fill: parent
        Keys.onEscapePressed: {
            if (st.count > 0) st.core.removeAlert(st.first.id)
            if (st.core.alertExpanded !== undefined) st.core.alertExpanded = false
            if (st.core.debugMode === "alert") st.core.debugMode = ""
        }
        Keys.onReturnPressed: if (st.count > 0 && st.canJump(st.first)) st.core.jump(st.first)
        Keys.onEnterPressed: if (st.count > 0 && st.canJump(st.first)) st.core.jump(st.first)
        Keys.onPressed: event => {
            if (!st.count || !st.canRespond(st.first)) return
            if (event.key === Qt.Key_A) {
                st.core.respondAlert(st.first, "allow")
                event.accepted = true
            } else if (event.key === Qt.Key_D) {
                st.core.respondAlert(st.first, "deny")
                event.accepted = true
            }
        }
    }

    // ── small local widgets ──
    component Txt: Text {
        color: st.core.text
        font.family: st.core.uiFont
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    component Mono: Text {
        color: st.core.dim
        font.family: st.core.monoFont
        font.pixelSize: 10
        elide: Text.ElideRight
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
    // Local pixel mascot; only the shared sprite data and island clock are reused.
    component PixelPet: Canvas {
        property string pose: st.petPose
        property int tick: st.visible && st.petJumping ? st.core.petTick : 0
        readonly property string skin: st.core.petSkin
        implicitWidth: S.W + 2
        implicitHeight: S.H + 2
        antialiasing: false
        Component.onCompleted: requestPaint()
        onPoseChanged: requestPaint()
        onTickChanged: requestPaint()
        onSkinChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: S.draw(getContext("2d"), skin, pose, tick, 1, false, false)
    }

    // ═══════════ STATE 01: PERSISTENT ALERT PILL (270×40) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showCompact ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (st.count > 0 && st.canJump(st.first)) st.core.jump(st.first)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            PixelPet {
                Layout.alignment: Qt.AlignVCenter
                transform: Translate { y: st.petLift }
            }

            // Warning Pulse Ring & Wiggle Icon (merged from original Alert.qml)
            Item {
                implicitWidth: 20
                implicitHeight: 20

                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1.5
                    border.color: st.core.coral
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showCompact
                        NumberAnimation { from: 0.9; to: 0.0; duration: 900 }
                    }
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: st.visible && st.showCompact
                        NumberAnimation { from: 1.0; to: 1.65; duration: 900 }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.22)

                    Ico {
                        anchors.centerIn: parent
                        name: "warning"
                        alt: "!"
                        font.pixelSize: 12
                        color: st.core.coral
                        SequentialAnimation on rotation {
                            loops: Animation.Infinite
                            running: st.visible && st.showCompact
                            NumberAnimation { to: -14; duration: 120 }
                            NumberAnimation { to: 14; duration: 240 }
                            NumberAnimation { to: 0; duration: 120 }
                            PauseAnimation { duration: 1600 }
                        }
                    }
                }
            }

            Txt {
                Layout.fillWidth: true
                text: st.headlineText(st.first)
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: st.core.text
            }

            // +N overflow counter when multiple agents are queued (from original Alert.qml)
            Mono {
                visible: st.count > 1
                text: "+" + (st.count - 1)
                font.pixelSize: 9
                font.weight: Font.Bold
                color: st.core.amber
            }

            RowLayout {
                visible: st.first.ts > 0
                spacing: 4

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: st.core.coral
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showCompact
                        NumberAnimation { to: 0.25; duration: 550 }
                        NumberAnimation { to: 1.0; duration: 550 }
                    }
                }

                Mono {
                    text: st.first.ts > 0 ? st.core.waited(st.first.ts) : ""
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    color: st.core.coral
                }
            }
        }
    }

    // ═══════════ STATE 02: EXPANDED PERMISSION DIALOG (460×150) ═══════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        opacity: st.showSingleExpanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Dialog Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PixelPet {
                Layout.alignment: Qt.AlignVCenter
                transform: Translate { y: st.petLift }
            }

            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.20)

                Ico {
                    anchors.centerIn: parent
                    name: "security"
                    alt: "!"
                    font.pixelSize: 13
                    color: st.core.coral
                }
            }

            Txt {
                Layout.fillWidth: true
                text: st.headlineText(st.first)
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: st.core.text
            }

            Rectangle {
                visible: st.locBadge(st.first) !== ""
                implicitHeight: 20
                implicitWidth: locRow.implicitWidth + 14
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)

                RowLayout {
                    id: locRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: st.core.teal
                    }

                    Mono {
                        text: st.locBadge(st.first)
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: st.core.teal
                    }
                }
            }
        }

        // Command Preview Inset Terminal
        Rectangle {
            Layout.fillWidth: true
            visible: st.cmdText(st.first) !== ""
            implicitHeight: 34
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.05)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Mono {
                    text: "$"
                    font.pixelSize: 12
                    color: st.core.dim
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 20
                    clip: true

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        property var parts: st.cmdParts(st.cmdText(st.first))

                        Mono {
                            text: parent.parts.bin
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: st.core.lav
                        }

                        Mono {
                            text: parent.parts.sub
                            font.pixelSize: 12
                            color: st.core.text
                        }

                        Mono {
                            text: parent.parts.arg
                            font.pixelSize: 12
                            color: st.core.amber
                        }

                        Mono {
                            width: Math.max(0, parent.width - x)
                            text: parent.parts.tail
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: st.core.teal
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Action Strip Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Mono {
                Layout.fillWidth: true
                visible: st.metaFooter(st.first) !== ""
                text: st.metaFooter(st.first)
                font.pixelSize: 9
                color: st.core.dim
            }

            Item {
                visible: st.metaFooter(st.first) === ""
                Layout.fillWidth: true
            }

            // Dismiss Button
            Rectangle {
                visible: st.canRespond(st.first)
                implicitHeight: 28
                implicitWidth: allowRow.implicitWidth + 18
                radius: 14
                color: allowMouse.containsMouse ? Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.30) : Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.18)

                RowLayout {
                    id: allowRow
                    anchors.centerIn: parent
                    spacing: 4
                    Mono { text: "Allow"; font.pixelSize: 10; font.weight: Font.DemiBold; color: st.core.teal }
                    Mono { text: "[A]"; font.pixelSize: 9; color: st.core.dim }
                }
                MouseArea {
                    id: allowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.core.respondAlert(st.first, "allow")
                }
            }

            Rectangle {
                visible: st.canRespond(st.first)
                implicitHeight: 28
                implicitWidth: denyRow.implicitWidth + 18
                radius: 14
                color: denyMouse.containsMouse ? Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.30) : Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.18)

                RowLayout {
                    id: denyRow
                    anchors.centerIn: parent
                    spacing: 4
                    Mono { text: "Deny"; font.pixelSize: 10; font.weight: Font.DemiBold; color: st.core.coral }
                    Mono { text: "[D]"; font.pixelSize: 9; color: st.core.dim }
                }
                MouseArea {
                    id: denyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: st.core.respondAlert(st.first, "deny")
                }
            }

            // Dismiss Button
            Rectangle {
                implicitHeight: 28
                implicitWidth: dismissRow.implicitWidth + 22
                radius: 14
                color: dismissMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
                scale: dismissMouse.containsMouse ? 1.04 : 1.0
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 100 } }

                RowLayout {
                    id: dismissRow
                    anchors.centerIn: parent
                    spacing: 6

                    Mono {
                        text: "Dismiss"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: dismissMouse.containsMouse ? st.core.text : st.core.dim
                    }

                    Mono {
                        text: "[Esc]"
                        font.pixelSize: 9
                        color: st.core.dim
                    }
                }

                MouseArea {
                    id: dismissMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (st.count > 0) st.core.removeAlert(st.first.id)
                }
            }

            // Jump to it Button (guarded by canJump like original Alert.qml)
            Rectangle {
                visible: st.canJump(st.first)
                implicitHeight: 28
                implicitWidth: jumpRow.implicitWidth + 24
                radius: 14
                color: st.core.coral
                scale: jumpMouse.pressed ? 0.96 : (jumpMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 100 } }

                RowLayout {
                    id: jumpRow
                    anchors.centerIn: parent
                    spacing: 6

                    Txt {
                        text: "Jump to it"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#000000"
                    }

                    Rectangle {
                        implicitHeight: 16
                        implicitWidth: jumpKeyTxt.implicitWidth + 8
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.22)

                        Mono {
                            id: jumpKeyTxt
                            anchors.centerIn: parent
                            text: st.jumpHint(st.first)
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: "#ffffff"
                        }
                    }
                }

                MouseArea {
                    id: jumpMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (st.count > 0) st.core.jump(st.first)
                }
            }
        }
    }

    // ═══════════ STATE 03: MULTI-AGENT WAITING (460×190) ═══════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        opacity: st.showMulti ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Multi-Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PixelPet {
                Layout.alignment: Qt.AlignVCenter
                transform: Translate { y: st.petLift }
            }

            Mono {
                Layout.fillWidth: true
                text: st.count + " AGENTS AWAITING PERMISSION"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: st.core.text
            }

            Rectangle {
                implicitHeight: 18
                implicitWidth: blockedTxt.implicitWidth + 14
                radius: 9
                color: Qt.rgba(st.core.coral.r, st.core.coral.g, st.core.coral.b, 0.16)

                Mono {
                    id: blockedTxt
                    anchors.centerIn: parent
                    text: st.count + " BLOCKED"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: st.core.coral
                }
            }
        }

        // Stacked Agent Cards (top 2)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Repeater {
                model: st.showMulti ? st.list.slice(0, 2) : []

                delegate: Rectangle {
                    id: agentCard
                    required property var modelData
                    required property int index
                    readonly property color cTone: st.rowTone(index, modelData)
                    readonly property string badgeStr: st.locBadge(modelData)
                    readonly property string cStr: st.cmdText(modelData)

                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.04)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: 9
                            color: Qt.rgba(agentCard.cTone.r, agentCard.cTone.g, agentCard.cTone.b, 0.20)

                            Ico {
                                anchors.centerIn: parent
                                name: st.rowIcon(agentCard.modelData)
                                alt: ">"
                                font.pixelSize: 11
                                color: agentCard.cTone
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Txt {
                                    text: st.core.label(agentCard.modelData.tool)
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: st.core.text
                                }

                                Mono {
                                    visible: agentCard.badgeStr !== ""
                                    text: agentCard.badgeStr
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: agentCard.index === 0 ? st.core.teal : agentCard.cTone
                                }

                                Mono {
                                    visible: agentCard.modelData.ts > 0
                                    text: agentCard.modelData.ts > 0 ? st.core.waited(agentCard.modelData.ts) : ""
                                    font.pixelSize: 9
                                    color: st.core.dim
                                }

                                Item { Layout.fillWidth: true }
                            }

                            Mono {
                                Layout.fillWidth: true
                                visible: agentCard.cStr !== ""
                                text: "$ " + agentCard.cStr
                                font.pixelSize: 10
                                color: st.core.dim
                            }
                        }

                        Rectangle {
                            visible: st.canJump(agentCard.modelData)
                            implicitHeight: 24
                            implicitWidth: rowJumpTxt.implicitWidth + 20
                            radius: 12
                            color: agentCard.cTone
                            scale: rowJumpMouse.pressed ? 0.95 : (rowJumpMouse.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 90 } }

                            Mono {
                                id: rowJumpTxt
                                anchors.centerIn: parent
                                text: (agentCard.modelData.ws !== undefined && agentCard.modelData.ws !== null && Number(agentCard.modelData.ws) > 0)
                                    ? "Jump (ws " + agentCard.modelData.ws + ")"
                                    : "Jump"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: "#000000"
                            }

                            MouseArea {
                                id: rowJumpMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: st.core.jump(agentCard.modelData)
                            }
                        }

                        // Dismiss fallback button if neither addr nor ws was provided
                        Rectangle {
                            visible: !st.canJump(agentCard.modelData)
                            implicitHeight: 24
                            implicitWidth: rowDismissTxt.implicitWidth + 18
                            radius: 12
                            color: rowDismissMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                            Mono {
                                id: rowDismissTxt
                                anchors.centerIn: parent
                                text: "Dismiss"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                color: st.core.text
                            }

                            MouseArea {
                                id: rowDismissMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: st.core.removeAlert(agentCard.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Multi Status Footnote
        RowLayout {
            Layout.fillWidth: true

            Mono {
                text: st.count > 2 ? ("+" + (st.count - 2) + " MORE IN FIFO QUEUE") : "HOLD QUEUE: PRIORITIZED FIFO"
                font.pixelSize: 9
                color: st.core.dim
            }

            Item { Layout.fillWidth: true }

            Mono {
                text: "FOCUS: HYPRCTL DISPATCH"
                font.pixelSize: 9
                color: st.core.dim
            }
        }
    }

    // ═══════════ STATE 04: RESOLVED & COLLAPSE (200×40) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showResolved ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Luminous Electric Teal 1.5px inner border matching State 04 spec
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: st.core.teal
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8

            Rectangle {
                implicitWidth: 16
                implicitHeight: 16
                radius: 8
                color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.22)

                Ico {
                    anchors.centerIn: parent
                    name: "check"
                    alt: "✓"
                    font.pixelSize: 12
                    color: st.core.teal
                }
            }

            Txt {
                Layout.fillWidth: true
                text: (st.core.alertResolvedLabel && st.core.alertResolvedLabel !== "") ? st.core.alertResolvedLabel : "Resolved"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: st.core.text
            }

            Mono {
                visible: st.core.alertResolvedElapsed !== undefined && st.core.alertResolvedElapsed !== ""
                text: st.core.alertResolvedElapsed || ""
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: st.core.teal
            }
        }
    }
}
