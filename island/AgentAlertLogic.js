// Pure logic for Agent alert classification, deduplication keys, and reminder repetition.
// No QML dependencies; fully testable in Node.js and Python.

const DEFAULT_AGENT_APP_NAMES = [
    "antigravity",
    "codex",
    "opencode",
    "claude code",
    "gemini cli"
];

const PERMISSION_SUMMARY_REGEX = /(?:permission|approv|allow|requesting|needs confirmation)/i;
const DONE_SUMMARY_REGEX = /(?:finished|completed|done|succeeded|resolved)/i;
const ERROR_SUMMARY_REGEX = /(?:error|failed|rejected|denied)/i;

function normalizeString(str) {
    if (!str || typeof str !== "string") return "";
    return str.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 40);
}

function normalizeAgentKey(agent, text) {
    const normAgent = normalizeString(agent) || "agent";
    const normText = normalizeString(text);
    return "agent:" + normAgent + ":" + normText;
}

function isAgentApp(appName, configuredList) {
    if (!appName || typeof appName !== "string") return false;
    const name = appName.trim().toLowerCase();
    const list = Array.isArray(configuredList) && configuredList.length > 0
        ? configuredList.map(a => String(a).toLowerCase())
        : DEFAULT_AGENT_APP_NAMES;
    return list.some(a => name.includes(a) || a.includes(name));
}

function classifyAgentNotification(n, configuredAgentList) {
    if (!n) return null;
    const appName = n.appName || "";
    const summary = n.summary || "";
    const body = n.body || "";

    const agentApp = isAgentApp(appName, configuredAgentList);
    const hasPermissionKeyword = PERMISSION_SUMMARY_REGEX.test(summary) || PERMISSION_SUMMARY_REGEX.test(body);

    if (!agentApp && !hasPermissionKeyword) {
        return null; // Not an agent notification
    }

    let event = null;
    if (hasPermissionKeyword || PERMISSION_SUMMARY_REGEX.test(summary)) {
        event = "agent-permission";
    } else if (DONE_SUMMARY_REGEX.test(summary) || DONE_SUMMARY_REGEX.test(body)) {
        event = "agent-done";
    } else if (ERROR_SUMMARY_REGEX.test(summary) || ERROR_SUMMARY_REGEX.test(body)) {
        event = "agent-error";
    } else if (agentApp) {
        // Generic agent notification fallback
        event = "agent-permission";
    }

    if (!event) return null;

    const dedupeKey = normalizeAgentKey(appName, summary + ":" + body);
    return {
        event: event,
        agent: appName || "Agent",
        dedupeKey: dedupeKey,
        isPermission: event === "agent-permission"
    };
}

function createReminderTracker() {
    return {
        // map id -> { id, agent, text, count, lastTriggerMs, startMs }
        active: {}
    };
}

function addPermissionReminder(tracker, id, agent, text, nowMs) {
    if (!tracker || !id) return;
    const key = String(id);
    if (!tracker.active[key]) {
        tracker.active[key] = {
            id: key,
            agent: agent || "Agent",
            text: text || "",
            count: 0,
            lastTriggerMs: nowMs,
            startMs: nowMs
        };
    }
}

function cancelPermissionReminder(tracker, id) {
    if (!tracker || !id) return;
    const key = String(id);
    delete tracker.active[key];
}

function clearAllPermissionReminders(tracker) {
    if (!tracker) return;
    tracker.active = {};
}

function tickPermissionReminders(tracker, nowMs, isStillActiveFn, playReminderFn) {
    if (!tracker || !tracker.active) return [];
    const triggered = [];
    const keys = Object.keys(tracker.active);

    for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const rem = tracker.active[key];

        // 1. Check if still active
        if (isStillActiveFn && !isStillActiveFn(rem.id)) {
            delete tracker.active[key];
            continue;
        }

        // 2. Check if reached max repetitions (at most 3 times)
        if (rem.count >= 3) {
            delete tracker.active[key];
            continue;
        }

        // 3. Check elapsed interval (45 seconds = 45000 ms)
        if (nowMs - rem.lastTriggerMs >= 45000) {
            rem.count += 1;
            rem.lastTriggerMs = nowMs;
            triggered.push({
                id: rem.id,
                agent: rem.agent,
                count: rem.count
            });
            if (playReminderFn) {
                playReminderFn(rem.id, rem.count);
            }
            if (rem.count >= 3) {
                delete tracker.active[key];
            }
        }
    }

    return triggered;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_AGENT_APP_NAMES,
        PERMISSION_SUMMARY_REGEX,
        DONE_SUMMARY_REGEX,
        ERROR_SUMMARY_REGEX,
        normalizeString,
        normalizeAgentKey,
        isAgentApp,
        classifyAgentNotification,
        createReminderTracker,
        addPermissionReminder,
        cancelPermissionReminder,
        clearAllPermissionReminders,
        tickPermissionReminders
    };
}
