// Island state: clip — copy flash (360×56) · image buffer ingest (360×96) · history viewer (460×340) · empty state (460×120)
// Live Wayland clipboard telemetry from Island.qml (`core`) + `cliphist` & `wl-paste` inspection while active.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Io

Item {
    id: st
    required property var core
    readonly property string key: "clip"

    readonly property bool active: core.mode === key
    readonly property bool historyOpen: Boolean(core.clipHistoryOn) || core.hovered

    // Live image metadata (from core if present, or detected by syncProc when active)
    property string localKind: ""
    property string localMime: ""
    property int localBytes: 0
    property string localImgPath: ""
    property int imgReloadTick: 0
    property bool currentPinned: false

    readonly property string effectiveKind: (core.clipKind && core.clipKind !== "") ? core.clipKind : localKind
    readonly property string effectiveMime: (core.clipMime && core.clipMime !== "") ? core.clipMime : localMime
    readonly property int effectiveBytes: (core.clipBytes && core.clipBytes > 0) ? core.clipBytes : localBytes
    readonly property string effectiveImgPath: (core.clipImgPath && core.clipImgPath !== "") ? core.clipImgPath : localImgPath
    readonly property real effectiveTs: (core.clipTs && core.clipTs > 0) ? core.clipTs : core.now

    readonly property bool isImage: effectiveKind === "image" && effectiveImgPath !== ""
    readonly property bool hasFlashData: isImage || core.clipChars > 0 || core.clipText !== ""
    readonly property bool historyView: historyOpen || !hasFlashData

    property bool hasCliphist: false
    property bool syncDone: false
    property var historyItems: []            // [{id, text, raw, pinned, kind, colorHex, ts}]
    property var timeMap: ({})               // text -> unix timestamp (seconds) from current session
    property string searchQuery: ""
    property int selectedIndex: 0

    property string pendingDecodeId: ""
    property string pendingCopyText: ""
    property string pendingDeleteRaw: ""
    property string pendingPinText: ""

    readonly property var filteredItems: {
        const q = searchQuery.trim().toLowerCase()
        const all = historyItems
        const matched = q === ""
            ? all
            : all.filter(it => it.text.toLowerCase().indexOf(q) >= 0)
        return matched
    }
    readonly property int totalCount: {
        const q = searchQuery.trim().toLowerCase()
        if (q === "") return historyItems.length
        return historyItems.filter(it => it.text.toLowerCase().indexOf(q) >= 0).length
    }

    readonly property bool showHistory: historyView && historyItems.length > 0
    readonly property bool showEmpty: historyView && historyItems.length === 0
    readonly property bool showImageFlash: !historyView && isImage
    readonly property bool showTextFlash: !historyView && !isImage

    readonly property string imgFormat: {
        if (effectiveMime === "") return ""
        const slash = effectiveMime.indexOf("/")
        const sub = slash >= 0 ? effectiveMime.slice(slash + 1) : effectiveMime
        return sub.toUpperCase()
    }
    readonly property string imgDimsText: thumbImg.status === Image.Ready && thumbImg.implicitWidth > 0 && thumbImg.implicitHeight > 0
        ? "Image · " + thumbImg.implicitWidth + "×" + thumbImg.implicitHeight
        : thumbImg.status === Image.Error ? "Image unavailable"
        : (effectiveMime !== "" ? "Image" : "")
    readonly property string imgMetaText: {
        const parts = []
        if (effectiveMime !== "") parts.push(effectiveMime)
        if (effectiveBytes > 0) parts.push(fmtBytes(effectiveBytes))
        if (effectiveTs > 0) parts.push(core.ago(effectiveTs))
        return parts.join(" · ")
    }

    readonly property real w: (showHistory || showEmpty) ? 460 : 360
    readonly property real h: showHistory ? 340 : showEmpty ? 120 : showImageFlash ? 96 : 56
    readonly property color accent: showEmpty ? core.lav : core.teal

    anchors.fill: parent
    opacity: core.mode === key ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Component.onCompleted: core.register(key, st)

    function fmtBytes(b) {
        if (b <= 0) return ""
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return Math.max(1, Math.round(b / 1024)) + " KB"
        return b + " B"
    }

    function classifyItem(txt) {
        const s = (txt || "").trim()
        if (/^\[\[.*binary data.*\]\]$/i.test(s)) return { kind: "image", colorHex: "" }
        const m = s.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b/)
        if (m) return { kind: "color", colorHex: m[0] }
        if (/^https?:\/\/\S+/i.test(s)) return { kind: "url", colorHex: "" }
        if (/^(git|cargo|pacman|paru|yay|docker|podman|systemctl|journalctl|hyprctl|qs|wl-copy|wl-paste|npm|pnpm|bun|python|pip|sh|fish|bash|ssh|curl|wget|make|cmake|gcc|clang)\b/.test(s))
            return { kind: "cmd", colorHex: "" }
        if (/[{};]|=>|\b(const|let|var|function|def|class|import|export|return|readonly|property)\b/.test(s))
            return { kind: "code", colorHex: "" }
        return { kind: "text", colorHex: "" }
    }

    function recordCurrentTimestamp() {
        const txt = (core.clipText || "").trim()
        if (txt === "") return
        const m = Object.assign({}, timeMap)
        m[txt] = Math.floor(core.clipTs > 0 ? core.clipTs : Date.now() / 1000)
        timeMap = m
    }

    function refreshHistory() {
        if (!active) return
        if (!syncProc.running) syncProc.running = true
    }

    function activateItem(idx) {
        if (idx < 0 || idx >= filteredItems.length) return
        const it = filteredItems[idx]
        if (!it) return
        if (it.id !== "" && hasCliphist) {
            pendingDecodeId = it.id
            decodeProc.running = true
        } else {
            pendingCopyText = it.text
            copyRawProc.running = true
        }
        closeViewer()
    }

    function togglePinItem(idx) {
        if (idx < 0 || idx >= filteredItems.length) return
        const it = filteredItems[idx]
        if (!it || it.text === "") return
        pendingPinText = it.text
        pinProc.running = true
    }

    function togglePinCurrent() {
        const label = isImage
            ? (imgDimsText !== "" ? imgDimsText + " (" + effectiveMime + ")" : effectiveMime)
            : core.clipText
        if (!label || label === "") return
        currentPinned = !currentPinned
        pendingPinText = label
        pinProc.running = true
    }

    function removeItem(idx) {
        if (idx < 0 || idx >= filteredItems.length) return
        const it = filteredItems[idx]
        if (!it) return
        if (it.pinned) {
            pendingPinText = it.text
            pinProc.running = true
        } else if (it.raw !== "" && hasCliphist) {
            pendingDeleteRaw = it.raw
            deleteProc.running = true
        }
    }

    function closeViewer() {
        searchQuery = ""
        searchInput.text = ""
        if (core.clipHistoryOn !== undefined) core.clipHistoryOn = false
        core.clipOn = false
        if (core.debugMode === "clip") core.debugMode = ""
    }

    function ensureSelectedVisible() {
        if (!showHistory || filteredItems.length === 0) return
        const idx = Math.max(0, Math.min(selectedIndex, filteredItems.length - 1))
        Qt.callLater(() => {
            if (historyList.count > idx)
                historyList.positionViewAtIndex(idx, ListView.Contain)
        })
    }

    function clampSelection() {
        const max = filteredItems.length - 1
        selectedIndex = Math.max(0, Math.min(selectedIndex, max))
        ensureSelectedVisible()
    }

    function moveSelection(delta) {
        if (filteredItems.length === 0) return
        selectedIndex = Math.max(0, Math.min(filteredItems.length - 1, selectedIndex + delta))
        ensureSelectedVisible()
    }

    onActiveChanged: {
        if (active) {
            selectedIndex = 0
            imgReloadTick += 1
            refreshHistory()
            if (showHistory) {
                searchInput.forceActiveFocus()
                ensureSelectedVisible()
            }
        } else {
            searchQuery = ""
            searchInput.text = ""
        }
    }

    onShowHistoryChanged: {
        if (active && showHistory) {
            searchInput.forceActiveFocus()
            ensureSelectedVisible()
        }
    }

    onFilteredItemsChanged: {
        clampSelection()
    }

    Connections {
        target: st.core
        function onClipTextChanged() {
            st.recordCurrentTimestamp()
            st.currentPinned = false
            if (st.active) st.refreshHistory()
        }
        function onHoveredChanged() {
            if (st.active && st.core.hovered) {
                if (st.core.clipOn && typeof st.core.holdClip === "function") st.core.holdClip()
                st.refreshHistory()
            }
        }
        function onClipHistoryOnChanged() {
            if (st.active) st.refreshHistory()
        }
        function onClipImgPathChanged() {
            if (st.active) st.refreshHistory()
        }
    }

    // Keep the pill open while the user is hovering or interacting with the history viewer
    Timer {
        interval: 1500
        repeat: true
        running: false
        onTriggered: {
            st.core.now = Date.now() / 1000
            if (typeof st.core.holdClip === "function") st.core.holdClip()
            else if (st.core.clipOn) st.core.clipOn = true
        }
    }

    // One-shot clipboard & history inspection (only runs while state is active)
    Process {
        id: syncProc
        command: [
            "sh", "-c",
            'd="${XDG_RUNTIME_DIR:-/tmp}"; umask 077; ' +
            'pinf="$d/island-clip-pins.tsv"; touch "$pinf"; ' +
            'types=$(wl-paste --list-types 2>/dev/null); ' +
            'imgm=$(printf "%s\\n" "$types" | grep -m1 "^image/"); ' +
            'if [ -n "$imgm" ]; then ' +
            '  imgp="$d/island-clip-image"; ' +
            '  tmp=$(mktemp "$d/island-clip-image.XXXXXX") || exit 1; ' +
            '  if wl-paste --type "$imgm" > "$tmp" 2>/dev/null; then ' +
            '    sz=$(wc -c < "$tmp" 2>/dev/null || echo 0); ' +
            '    if [ "${sz:-0}" -gt 0 ]; then mv -f "$tmp" "$imgp" && printf "IMG\\t%s\\t%s\\t%s\\n" "$imgm" "$sz" "$imgp"; else rm -f "$tmp"; fi; ' +
            '  else rm -f "$tmp"; fi; ' +
            'else ' +
            '  printf "TXT\\n"; ' +
            'fi; ' +
            'if command -v cliphist >/dev/null 2>&1; then printf "CH\\t1\\n"; else printf "CH\\t0\\n"; fi; ' +
            'while IFS= read -r pline; do [ -n "$pline" ] && printf "PIN\\t%s\\n" "$pline"; done < "$pinf"; ' +
            'if command -v cliphist >/dev/null 2>&1; then ' +
            '  cliphist list 2>/dev/null | head -n 60 | while IFS= read -r cline; do ' +
            '    [ -n "$cline" ] && printf "HIST\\t%s\\n" "$cline"; ' +
            '  done; ' +
            'fi'
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                const pins = []
                const pinSet = ({})
                const hist = []
                let gotCh = false
                let foundImg = false

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i]
                    if (!line) continue
                    if (line.indexOf("IMG\t") === 0) {
                        const p = line.split("\t")
                        st.localKind = "image"
                        st.localMime = p[1] || "image/png"
                        st.localBytes = parseInt(p[2]) || 0
                        st.localImgPath = p[3] || ""
                        st.imgReloadTick += 1
                        foundImg = true
                    } else if (line === "TXT") {
                        st.localKind = "text"
                    } else if (line.indexOf("CH\t") === 0) {
                        gotCh = line.slice(3).trim() === "1"
                    } else if (line.indexOf("PIN\t") === 0) {
                        const rest = line.slice(4)
                        const tab = rest.indexOf("\t")
                        const ts = tab >= 0 ? (parseInt(rest.slice(0, tab)) || 0) : 0
                        const val = (tab >= 0 ? rest.slice(tab + 1) : rest).trim()
                        if (val !== "" && !pinSet[val]) {
                            pinSet[val] = true
                            const meta = st.classifyItem(val)
                            pins.push({
                                id: "",
                                text: val,
                                raw: "",
                                pinned: true,
                                kind: meta.kind,
                                colorHex: meta.colorHex,
                                ts: ts
                            })
                        }
                    } else if (line.indexOf("HIST\t") === 0) {
                        const raw = line.slice(5)
                        const tab = raw.indexOf("\t")
                        const id = tab >= 0 ? raw.slice(0, tab).trim() : ""
                        const val = (tab >= 0 ? raw.slice(tab + 1) : raw).trim()
                        if (val !== "") {
                            const meta = st.classifyItem(val)
                            const isPin = Boolean(pinSet[val])
                            hist.push({
                                id: id,
                                text: val,
                                raw: raw,
                                pinned: isPin,
                                kind: meta.kind,
                                colorHex: meta.colorHex,
                                ts: st.timeMap[val] || 0
                            })
                        }
                    }
                }

                if (!foundImg && st.localKind === "image") {
                    st.localKind = "text"
                }

                st.hasCliphist = gotCh
                const unpinnedHist = hist.filter(h => !pinSet[h.text])
                st.historyItems = pins.concat(unpinnedHist)
                st.syncDone = true
                st.clampSelection()
            }
        }
    }

    Process {
        id: decodeProc
        command: ["sh", "-c", 'cliphist decode "$1" 2>/dev/null | wl-copy', "sh", st.pendingDecodeId]
    }

    Process {
        id: copyRawProc
        command: ["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", st.pendingCopyText]
    }

    Process {
        id: deleteProc
        command: ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete 2>/dev/null', "sh", st.pendingDeleteRaw]
        onExited: st.refreshHistory()
    }

    Process {
        id: pinProc
        command: [
            "sh", "-c",
            'd="${XDG_RUNTIME_DIR:-/tmp}"; umask 077; f="$d/island-clip-pins.tsv"; touch "$f"; ' +
            't=$(printf "%s" "$1" | tr "\\n\\t" "  "); ' +
            'now=$(date +%s); ' +
            'tmp=$(mktemp "$f.XXXXXX") || exit 1; ' +
            'if awk -F "\\t" -v target="$t" "\\$2 == target { found=1 } END { exit !found }" "$f"; then ' +
            '  awk -F "\\t" -v target="$t" "\\$2 != target { print \\$0 }" "$f" > "$tmp" && mv -f "$tmp" "$f"; ' +
            'else ' +
            '  printf "%s\\t%s\\n" "$now" "$t" > "$tmp"; cat "$f" >> "$tmp"; mv -f "$tmp" "$f"; ' +
            'fi',
            "sh", st.pendingPinText
        ]
        onExited: st.refreshHistory()
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
        font.pixelSize: 15
        color: st.core.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // ═══════════ STATE 01: COPY FLASH (360×56) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showTextFlash ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.10)

                Ico {
                    anchors.centerIn: parent
                    name: "content_copy"
                    alt: "⎘"
                    font.pixelSize: 15
                    color: st.core.teal
                }
            }

            Mono {
                Layout.fillWidth: true
                visible: st.core.clipText !== ""
                text: st.core.clipPreview ? st.core.clipText : "••••••••"
                font.pixelSize: 13
                font.weight: Font.Medium
                color: st.core.text
            }

            RowLayout {
                spacing: 8

                Mono {
                    visible: st.core.clipChars > 0
                    text: st.core.clipChars + " chars"
                    font.pixelSize: 9
                    color: st.core.dim
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: copiedRow.implicitWidth + 16
                    radius: 10
                    color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.15)

                    RowLayout {
                        id: copiedRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: st.core.teal
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: st.visible && st.showTextFlash
                                NumberAnimation { to: 0.2; duration: 550 }
                                NumberAnimation { to: 1.0; duration: 550 }
                            }
                        }

                        Mono {
                            text: "COPIED"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            color: st.core.teal
                        }
                    }
                }
            }
        }
    }

    // ═══════════ STATE 02: IMAGE BUFFER INGEST (360×96) ═══════════
    Item {
        anchors.fill: parent
        opacity: st.showImageFlash ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // Left 72×72 circular thumbnail
            Item {
                implicitWidth: 72
                implicitHeight: 72

                Rectangle {
                    id: thumbMask
                    anchors.fill: parent
                    radius: 36
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 36
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    Ico {
                        anchors.centerIn: parent
                        visible: thumbImg.status !== Image.Ready
                        name: "image"
                        alt: "▣"
                        font.pixelSize: 24
                        color: st.core.teal
                    }
                }

                Image {
                    id: thumbImg
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: st.isImage && st.effectiveImgPath !== ""
                        ? "file://" + st.effectiveImgPath + "?t=" + st.imgReloadTick
                        : ""
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: thumbMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 2
                    visible: st.imgFormat !== ""
                    implicitHeight: 14
                    implicitWidth: fmtTag.implicitWidth + 8
                    radius: 7
                    color: Qt.rgba(0, 0, 0, 0.72)

                    Mono {
                        id: fmtTag
                        anchors.centerIn: parent
                        text: st.imgFormat
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                        color: st.core.teal
                    }
                }
            }

            // Center Content Spine
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: st.core.teal
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: st.visible && st.showImageFlash
                            NumberAnimation { to: 0.3; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }

                    Mono {
                        Layout.fillWidth: true
                        text: "IMAGE BUFFER DETECTED"
                        font.pixelSize: 9
                        font.letterSpacing: 0.9
                        color: st.core.teal
                    }
                }

                Txt {
                    Layout.fillWidth: true
                    visible: st.imgDimsText !== ""
                    text: st.imgDimsText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: st.core.text
                }

                Mono {
                    Layout.fillWidth: true
                    visible: st.imgMetaText !== ""
                    text: st.imgMetaText
                    font.pixelSize: 9
                    color: st.core.dim
                }
            }

            // Right Wing: CACHED badge + Pin button
            ColumnLayout {
                spacing: 6

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    implicitHeight: 18
                    implicitWidth: cachedRow.implicitWidth + 14
                    radius: 9
                    color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.12)

                    RowLayout {
                        id: cachedRow
                        anchors.centerIn: parent
                        spacing: 4

                        Ico {
                            name: "check"
                            alt: "✓"
                            font.pixelSize: 11
                            color: st.core.teal
                        }

                        Mono {
                            text: "CACHED"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            color: st.core.teal
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: 12
                    color: st.currentPinned
                        ? Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.22)
                        : (pinImgMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Ico {
                        anchors.centerIn: parent
                        name: "push_pin"
                        alt: "★"
                        font.pixelSize: 13
                        color: st.currentPinned ? st.core.amber : (pinImgMouse.containsMouse ? st.core.text : st.core.dim)
                    }

                    MouseArea {
                        id: pinImgMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: st.togglePinCurrent()
                    }
                }
            }
        }
    }

    // ═══════════ STATE 03: HISTORY VIEWER (460×340) ═══════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        opacity: st.showHistory ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Top: Search Bar Pill
        Item {
            Layout.fillWidth: true
            implicitHeight: 56

            Rectangle {
                anchors.fill: parent
                anchors.margins: 12
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.22)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 8

                    Ico {
                        name: "search"
                        alt: "?"
                        font.pixelSize: 15
                        color: st.core.teal
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 24

                        Mono {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === ""
                            text: "Search clipboard history..."
                            font.pixelSize: 12
                            color: st.core.dim
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: st.core.text
                            font.family: st.core.monoFont
                            font.pixelSize: 12
                            clip: true
                            selectByMouse: true
                            onTextChanged: {
                                st.searchQuery = text
                                st.selectedIndex = 0
                                st.ensureSelectedVisible()
                            }
                            Keys.onUpPressed: st.moveSelection(-1)
                            Keys.onDownPressed: st.moveSelection(1)
                            Keys.onReturnPressed: st.activateItem(st.selectedIndex)
                            Keys.onEnterPressed: st.activateItem(st.selectedIndex)
                            Keys.onDeletePressed: st.removeItem(st.selectedIndex)
                            Keys.onEscapePressed: st.closeViewer()
                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
                                    st.togglePinItem(st.selectedIndex)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_P && searchInput.text === "") {
                                    st.togglePinItem(st.selectedIndex)
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Mono {
                        text: st.totalCount + (st.totalCount === 1 ? " item" : " items")
                        font.pixelSize: 9
                        color: st.core.dim
                    }

                    Rectangle {
                        implicitHeight: 18
                        implicitWidth: escLbl.implicitWidth + 12
                        radius: 9
                        color: escMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)

                        Mono {
                            id: escLbl
                            anchors.centerIn: parent
                            text: "ESC"
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                            color: st.core.text
                        }

                        MouseArea {
                            id: escMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: st.closeViewer()
                        }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }
        }

        // Mid: Scrollable Clips List
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: historyList
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: st.showHistory ? st.filteredItems : []

                delegate: Rectangle {
                    id: rowRect
                    required property var modelData
                    required property int index
                    readonly property bool isSel: index === st.selectedIndex

                    width: ListView.view.width
                    height: 36
                    radius: 18
                    color: isSel
                        ? Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.15)
                        : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04))
                    border.width: isSel ? 1 : 0
                    border.color: Qt.rgba(st.core.teal.r, st.core.teal.g, st.core.teal.b, 0.35)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                            // Star icon if pinned
                            Ico {
                                visible: Boolean(rowRect.modelData.pinned)
                                name: "star"
                                alt: "★"
                                font.pixelSize: 14
                                color: st.core.amber
                            }

                            // Color swatch for hex colour clips
                            Rectangle {
                                visible: rowRect.modelData.kind === "color" && rowRect.modelData.colorHex !== ""
                                width: 12
                                height: 12
                                radius: 6
                                color: rowRect.modelData.colorHex !== "" ? rowRect.modelData.colorHex : st.core.teal
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.25)
                            }

                            // Semantic type icon for non-swatch clips
                            Ico {
                                visible: rowRect.modelData.kind !== "color"
                                name: rowRect.modelData.kind === "image"
                                    ? "image"
                                    : rowRect.modelData.kind === "url"
                                        ? "link"
                                        : rowRect.modelData.kind === "cmd"
                                            ? "terminal"
                                            : rowRect.modelData.kind === "code"
                                                ? "code"
                                                : "notes"
                                alt: rowRect.modelData.kind === "image" ? "▣" : "⎘"
                                font.pixelSize: 14
                                color: rowRect.isSel
                                    ? st.core.teal
                                    : rowRect.modelData.kind === "image"
                                        ? st.core.lav
                                        : st.core.dim
                            }

                            // Clip text preview
                            Mono {
                                Layout.fillWidth: true
                                text: st.core.clipPreview ? rowRect.modelData.text : "••••••••"
                                font.pixelSize: 13
                                font.weight: rowRect.isSel ? Font.Medium : Font.Normal
                                color: rowRect.isSel ? st.core.teal : st.core.text
                            }

                            // PINNED chip
                            Rectangle {
                                visible: Boolean(rowRect.modelData.pinned)
                                implicitHeight: 16
                                implicitWidth: pinChipTxt.implicitWidth + 10
                                radius: 8
                                color: Qt.rgba(st.core.amber.r, st.core.amber.g, st.core.amber.b, 0.15)

                                Mono {
                                    id: pinChipTxt
                                    anchors.centerIn: parent
                                    text: "PINNED"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.6
                                    color: st.core.amber
                                }
                            }

                            // Relative age (only shown when real timestamp is known)
                            Mono {
                                visible: rowRect.modelData.ts > 0
                                text: rowRect.modelData.ts > 0 ? st.core.ago(rowRect.modelData.ts) : ""
                                font.pixelSize: 9
                                color: rowRect.isSel ? st.core.teal : st.core.dim
                            }

                            // Selected Enter badge
                            Rectangle {
                                visible: rowRect.isSel
                                width: 16
                                height: 16
                                radius: 8
                                color: st.core.teal

                                Mono {
                                    anchors.centerIn: parent
                                    text: "↵"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#000000"
                                }
                            }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: {
                            st.selectedIndex = rowRect.index
                            st.ensureSelectedVisible()
                        }
                        onClicked: mouse => {
                            st.selectedIndex = rowRect.index
                            if (mouse.button === Qt.RightButton) st.togglePinItem(rowRect.index)
                            else st.activateItem(rowRect.index)
                        }
                    }
                }
            }
        }

        // Bottom: Action Keyboard Bar (also clickable via mouse)
        Item {
            Layout.fillWidth: true
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.03)
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                Item {
                    implicitWidth: actPaste.implicitWidth
                    implicitHeight: 20
                    RowLayout {
                        id: actPaste
                        anchors.centerIn: parent
                        spacing: 3
                        Mono { text: "[Enter]"; font.pixelSize: 9; font.weight: Font.DemiBold; color: st.core.text }
                        Mono { text: "Paste"; font.pixelSize: 9; color: st.core.dim }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.activateItem(st.selectedIndex) }
                }

                Mono { text: "·"; font.pixelSize: 9; color: st.core.dim }

                Item {
                    implicitWidth: actPin.implicitWidth
                    implicitHeight: 20
                    RowLayout {
                        id: actPin
                        anchors.centerIn: parent
                        spacing: 3
                        Mono { text: "[P]"; font.pixelSize: 9; font.weight: Font.DemiBold; color: st.core.text }
                        Mono { text: "Pin/Unpin"; font.pixelSize: 9; color: st.core.dim }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.togglePinItem(st.selectedIndex) }
                }

                Mono { text: "·"; font.pixelSize: 9; color: st.core.dim }

                Item {
                    implicitWidth: actDel.implicitWidth
                    implicitHeight: 20
                    RowLayout {
                        id: actDel
                        anchors.centerIn: parent
                        spacing: 3
                        Mono { text: "[Del]"; font.pixelSize: 9; font.weight: Font.DemiBold; color: st.core.text }
                        Mono { text: "Remove"; font.pixelSize: 9; color: st.core.dim }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.removeItem(st.selectedIndex) }
                }

                Mono { text: "·"; font.pixelSize: 9; color: st.core.dim }

                Item {
                    implicitWidth: actEsc.implicitWidth
                    implicitHeight: 20
                    RowLayout {
                        id: actEsc
                        anchors.centerIn: parent
                        spacing: 3
                        Mono { text: "[Esc]"; font.pixelSize: 9; font.weight: Font.DemiBold; color: st.core.text }
                        Mono { text: "Close"; font.pixelSize: 9; color: st.core.dim }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.closeViewer() }
                }
            }
        }
    }

    // ═══════════ STATE 04: EMPTY STATE (460×120) ═══════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        opacity: st.showEmpty ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.07)

                Ico {
                    anchors.centerIn: parent
                    name: "inventory_2"
                    alt: "∅"
                    font.pixelSize: 18
                    color: st.core.dim
                }
            }

            ColumnLayout {
                spacing: 2

                Txt {
                    text: !st.syncDone ? "Checking clipboard..."
                        : st.hasCliphist ? "Clipboard history is empty"
                        : "Clipboard history unavailable"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: st.core.text
                }

                Txt {
                    text: !st.syncDone ? "Reading the current clipboard state."
                        : st.hasCliphist ? "Items copied with Super+C or wl-copy will appear here automatically."
                        : "Install cliphist to keep searchable history. Copy flashes still work."
                    font.pixelSize: 11
                    color: st.core.dim
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 20
            implicitWidth: emptyTagRow.implicitWidth + 20
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.06)

            RowLayout {
                id: emptyTagRow
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: st.core.lav
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: st.visible && st.showEmpty
                        NumberAnimation { to: 0.3; duration: 700 }
                        NumberAnimation { to: 1.0; duration: 700 }
                    }
                }

                Mono {
                    text: !st.syncDone ? "CHECKING CLIPBOARD"
                        : st.hasCliphist ? "CLIPHIST HISTORY AVAILABLE"
                        : "CLIPHIST NOT INSTALLED"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: st.core.lav
                }
            }
        }
    }
}
