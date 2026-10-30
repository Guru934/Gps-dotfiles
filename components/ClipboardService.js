// Pure logic for GPS Clipboard Service & Picker
// No QML imports; safe for Node.js unit testing.

const MAX_HISTORY_ITEMS = 200;
const MAX_ENTRY_BYTES = 1048576; // 1 MB
const MAX_PREVIEW_LEN = 300;

function validateId(id) {
    if (typeof id === "number") {
        return Number.isInteger(id) && id > 0 ? id : null;
    }
    if (typeof id === "string") {
        const s = id.trim();
        if (/^\d+$/.test(s)) {
            const n = parseInt(s, 10);
            return n > 0 ? n : null;
        }
    }
    return null;
}

function classifyItem(text) {
    if (!text || typeof text !== "string") return "text";
    const trimmed = text.trim();

    // Binary image format from cliphist: [[ binary data 2 MiB png 1089x1200 ]]
    if (trimmed.startsWith("[[ binary data ") && trimmed.endsWith(" ]]")) {
        return "image";
    }

    // Hex color: #RGB, #RGBA, #RRGGBB, #RRGGBBAA
    if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(trimmed)) {
        return "color";
    }

    // RGB / HSL colors: rgb(..), rgba(..), hsl(..)
    if (/^(rgb|rgba|hsl|hsla)\([^)]+\)$/i.test(trimmed)) {
        return "color";
    }

    // URL: http, https, ftp
    if (/^(https?|ftp):\/\/[^\s/$.?#].[^\s]*$/i.test(trimmed)) {
        return "url";
    }

    // File path: absolute unix path or home path
    if (/^(\/|~\/)[^\0\n]+$/.test(trimmed) && trimmed.length < 500) {
        return "path";
    }

    return "text";
}

function parseLine(line) {
    if (!line || typeof line !== "string") return null;
    const tabIdx = line.indexOf("\t");
    if (tabIdx <= 0) return null;

    const idStr = line.slice(0, tabIdx).trim();
    const id = validateId(idStr);
    if (id === null) return null;

    const preview = line.slice(tabIdx + 1);
    const kind = classifyItem(preview);

    let colorHex = null;
    if (kind === "color" && preview.trim().startsWith("#")) {
        colorHex = preview.trim();
    }

    let isImage = kind === "image";
    let imageInfo = null;
    if (isImage) {
        // Parse metadata: e.g. "[[ binary data 2 MiB png 1089x1200 ]]"
        const m = /^\[\[ binary data (.+?) ([a-zA-Z0-9]+)(?: ([0-9]+x[0-9]+))? \]\]$/.exec(preview.trim());
        if (m) {
            imageInfo = {
                sizeStr: m[1],
                format: m[2].toUpperCase(),
                dims: m[3] || ""
            };
        }
    }

    return {
        id: id,
        raw: line,
        preview: preview,
        kind: kind,
        colorHex: colorHex,
        isImage: isImage,
        imageInfo: imageInfo
    };
}

function parseList(output, maxItems = MAX_HISTORY_ITEMS) {
    if (!output || typeof output !== "string") return [];
    const lines = output.split("\n");
    const result = [];
    const cap = (typeof maxItems === "number" && maxItems > 0) ? maxItems : MAX_HISTORY_ITEMS;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line.trim()) continue;
        const item = parseLine(line);
        if (item) {
            result.push(item);
            if (result.length >= cap) break;
        }
    }
    return result;
}

function filterItems(items, query) {
    if (!Array.isArray(items)) return [];
    if (!query || typeof query !== "string") return items.slice();
    const q = query.trim().toLowerCase();
    if (!q) return items.slice();

    return items.filter(it => {
        if (!it) return false;
        if (it.preview && it.preview.toLowerCase().includes(q)) return true;
        if (it.kind && it.kind.toLowerCase().includes(q)) return true;
        return false;
    });
}

function createDefaultSettings() {
    return {
        version: 1,
        paused: false,
        maxItems: MAX_HISTORY_ITEMS,
        autoPaste: false
    };
}

function createDefaultPinnedStore() {
    return {
        version: 1,
        pinned: []
    };
}

function isPinned(pinnedList, id, text) {
    if (!Array.isArray(pinnedList)) return false;
    const numId = validateId(id);
    for (let i = 0; i < pinnedList.length; i++) {
        const p = pinnedList[i];
        if (numId !== null && p.id === numId) return true;
        if (text && p.text && p.text === text) return true;
    }
    return false;
}

function togglePin(pinnedStore, item, now) {
    if (!pinnedStore || !Array.isArray(pinnedStore.pinned)) {
        pinnedStore = createDefaultPinnedStore();
    }
    const ts = typeof now === "number" ? now : Date.now();
    const id = validateId(item.id);
    const text = item.preview || "";
    const kind = item.kind || classifyItem(text);

    const existingIdx = pinnedStore.pinned.findIndex(p =>
        (id !== null && p.id === id) || (text && p.text === text)
    );

    if (existingIdx >= 0) {
        pinnedStore.pinned.splice(existingIdx, 1);
        return { pinned: false, count: pinnedStore.pinned.length };
    } else {
        pinnedStore.pinned.unshift({
            id: id,
            text: text,
            kind: kind,
            pinnedAt: ts
        });
        return { pinned: true, count: pinnedStore.pinned.length };
    }
}

function removePin(pinnedStore, id) {
    if (!pinnedStore || !Array.isArray(pinnedStore.pinned)) return 0;
    const numId = validateId(id);
    const before = pinnedStore.pinned.length;
    pinnedStore.pinned = pinnedStore.pinned.filter(p => p.id !== numId && p.id !== id);
    return before - pinnedStore.pinned.length;
}

function mergeHistoryAndPins(historyItems, pinnedStore) {
    const history = Array.isArray(historyItems) ? historyItems.slice() : [];
    const pins = (pinnedStore && Array.isArray(pinnedStore.pinned)) ? pinnedStore.pinned : [];

    // Mark items in history that are pinned
    const pinnedMap = new Map();
    pins.forEach(p => {
        if (p.id) pinnedMap.set(p.id, p);
        if (p.text) pinnedMap.set(p.text, p);
    });

    // Extract pinned entries that may have been wiped or rotated out of cliphist
    const existingIds = new Set(history.map(h => h.id));
    const extraPins = [];

    pins.forEach(p => {
        if (!existingIds.has(p.id)) {
            extraPins.push({
                id: p.id || 0,
                raw: (p.id || 0) + "\t" + (p.text || ""),
                preview: p.text || "",
                kind: p.kind || classifyItem(p.text || ""),
                colorHex: p.kind === "color" && p.text && p.text.startsWith("#") ? p.text : null,
                isImage: p.kind === "image",
                imageInfo: null,
                pinned: true,
                pinnedOnly: true
            });
        }
    });

    // Mark pinned property on regular items
    const mergedHistory = history.map(h => {
        const isPin = pinnedMap.has(h.id) || (h.preview && pinnedMap.has(h.preview));
        return Object.assign({}, h, { pinned: Boolean(isPin) });
    });

    // Pinned entries appear first
    const allPinned = extraPins.concat(mergedHistory.filter(h => h.pinned));
    const regular = mergedHistory.filter(h => !h.pinned);

    return allPinned.concat(regular);
}

function serializeJson(data) {
    try {
        return JSON.stringify(data, null, 2);
    } catch (e) {
        return "{}";
    }
}

function deserializeJson(text, fallback) {
    if (!text || typeof text !== "string") return fallback;
    try {
        return JSON.parse(text);
    } catch (e) {
        return fallback;
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MAX_HISTORY_ITEMS,
        MAX_ENTRY_BYTES,
        MAX_PREVIEW_LEN,
        validateId,
        classifyItem,
        parseLine,
        parseList,
        filterItems,
        createDefaultSettings,
        createDefaultPinnedStore,
        isPinned,
        togglePin,
        removePin,
        mergeHistoryAndPins,
        serializeJson,
        deserializeJson
    };
}
