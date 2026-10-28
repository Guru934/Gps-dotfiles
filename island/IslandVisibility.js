.pragma library

// IslandVisibility.js — Pure decision logic for GPS Island visibility
// Zero QML types, zero internal timers. 100% testable via Node.js.

/**
 * Priority constants
 */
var PRIORITY = {
  ALERT: 1,
  USER_INTERACTION: 2,
  TRANSIENT: 3,
  PERSISTENT: 4,
  RESTING: 5
};

/**
 * Default Island settings
 */
var DEFAULT_SETTINGS = {
  persistentMusicPill: false,
  hoverDelay: 300,
  hoverZoneWidth: 300,
  hoverZoneHeight: 5,
  durations: {
    workspace: 1500,
    clipboard: 2500,
    notification: 4000,
    osd: 1500,
    musicChange: 3000,
    charge: 3000
  }
};

/**
 * Safely parses and resolves island settings from JSON or object with robust defaults.
 *
 * @param {string|Object} raw - JSON string or settings object
 * @returns {Object} Safe settings object
 */
function resolveIslandSettings(raw) {
  var base = {
    persistentMusicPill: DEFAULT_SETTINGS.persistentMusicPill,
    hoverDelay: DEFAULT_SETTINGS.hoverDelay,
    hoverZoneWidth: DEFAULT_SETTINGS.hoverZoneWidth,
    hoverZoneHeight: DEFAULT_SETTINGS.hoverZoneHeight,
    durations: {
      workspace: DEFAULT_SETTINGS.durations.workspace,
      clipboard: DEFAULT_SETTINGS.durations.clipboard,
      notification: DEFAULT_SETTINGS.durations.notification,
      osd: DEFAULT_SETTINGS.durations.osd,
      musicChange: DEFAULT_SETTINGS.durations.musicChange,
      charge: DEFAULT_SETTINGS.durations.charge
    }
  };

  if (!raw) return base;

  var parsed = raw;
  if (typeof raw === "string") {
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      return base;
    }
  }

  if (!parsed || typeof parsed !== "object") return base;

  var island = (parsed.island && typeof parsed.island === "object") ? parsed.island : parsed;

  if (typeof island.persistentMusicPill === "boolean") {
    base.persistentMusicPill = island.persistentMusicPill;
  }
  if (typeof island.hoverDelay === "number" && !isNaN(island.hoverDelay) && island.hoverDelay >= 0) {
    base.hoverDelay = island.hoverDelay;
  }
  if (typeof island.hoverZoneWidth === "number" && !isNaN(island.hoverZoneWidth) && island.hoverZoneWidth > 0) {
    base.hoverZoneWidth = island.hoverZoneWidth;
  }
  if (typeof island.hoverZoneHeight === "number" && !isNaN(island.hoverZoneHeight) && island.hoverZoneHeight > 0) {
    base.hoverZoneHeight = island.hoverZoneHeight;
  }

  if (island.durations && typeof island.durations === "object") {
    var durKeys = ["workspace", "clipboard", "notification", "osd", "musicChange", "charge"];
    for (var i = 0; i < durKeys.length; i++) {
      var k = durKeys[i];
      if (typeof island.durations[k] === "number" && !isNaN(island.durations[k]) && island.durations[k] >= 0) {
        base.durations[k] = island.durations[k];
      }
    }
  }

  return base;
}

/**
 * Computes next visibility state and timer requirement.
 *
 * @param {Object} inputs
 *   - now: number (epoch ms, defaults to Date.now())
 *   - windowFocused: boolean
 *   - fullscreen: boolean
 *   - workspaceEmpty: boolean
 *   - hovered: boolean
 *   - pinned: boolean
 *   - activeAlert: boolean
 *   - transientQueue: Array<{ id, kind, priority, expiry, duration, wantsKeyboard }>
 *   - hoverLeaveExpiry: number (ms timestamp when hover grace ends, or 0)
 *   - settings: { persistentMusicPill: boolean, ... }
 *   - isMusicPlaying: boolean
 *   - privacyVisible: boolean (optional)
 *   - launcherOpen: boolean (optional)
 *   - dnd: boolean (optional)
 *   - focusOn: boolean (optional)
 *
 * @returns {Object}
 *   - visible: boolean
 *   - state: "hidden" | "idle" | "control" | "alert" | "osd" | "clip" | "notify" | "charge" | "music" | ...
 *   - nextExpiry: number | null (epoch ms when single controller timer should fire, or null if indefinite)
 *   - wantsKeyboard: boolean
 *   - reason: string
 */
function evaluateVisibility(inputs) {
  if (!inputs) inputs = {};
  var now = typeof inputs.now === "number" ? inputs.now : Date.now();
  var settings = resolveIslandSettings(inputs.settings);

  // 1. Alert / Approval (Priority 1) — beats fullscreen and all other states
  if (inputs.activeAlert) {
    return {
      visible: true,
      state: "alert",
      nextExpiry: null,
      wantsKeyboard: true,
      reason: "active_alert"
    };
  }

  // Explicit manual hide (e.g. gps-ipc island hide)
  if (inputs.manualHide) {
    return {
      visible: false,
      state: "hidden",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "manual_hide"
    };
  }

  // Fullscreen suppresses all non-alert states
  if (inputs.fullscreen) {
    return {
      visible: false,
      state: "hidden",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "fullscreen_suppressed"
    };
  }

  // 2. Explicit User Interaction (Priority 2)
  if (inputs.pinned) {
    return {
      visible: true,
      state: "control",
      nextExpiry: null,
      wantsKeyboard: true,
      reason: "pinned_open"
    };
  }

  if (inputs.manualShow) {
    return {
      visible: true,
      state: "control",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "manual_show"
    };
  }

  if (inputs.hovered) {
    return {
      visible: true,
      state: "control",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "hover_active"
    };
  }

  if (inputs.hoverLeaveExpiry && inputs.hoverLeaveExpiry > now) {
    return {
      visible: true,
      state: "control",
      nextExpiry: inputs.hoverLeaveExpiry,
      wantsKeyboard: false,
      reason: "hover_leave_grace"
    };
  }

  // Optional modal interactions when not fullscreen
  if (inputs.launcherOpen) {
    return {
      visible: true,
      state: "launcher",
      nextExpiry: null,
      wantsKeyboard: true,
      reason: "launcher_open"
    };
  }

  // Filter expired transient events
  var activeTransients = (inputs.transientQueue || []).filter(function(ev) {
    return ev && typeof ev.expiry === "number" && ev.expiry > now;
  });

  // 3. Transient System Feedback (Priority 3)
  if (activeTransients.length > 0) {
    // Top event by highest priority (lowest number), then latest expiry
    activeTransients.sort(function(a, b) {
      var pa = a.priority !== undefined ? a.priority : PRIORITY.TRANSIENT;
      var pb = b.priority !== undefined ? b.priority : PRIORITY.TRANSIENT;
      if (pa !== pb) return pa - pb;
      return b.expiry - a.expiry;
    });

    var topEvent = activeTransients[0];
    return {
      visible: true,
      state: topEvent.kind,
      nextExpiry: topEvent.expiry,
      wantsKeyboard: Boolean(topEvent.wantsKeyboard),
      reason: "transient_" + topEvent.kind
    };
  }

  // 4. Persistent Activity (Priority 4)
  if (inputs.privacyVisible) {
    return {
      visible: true,
      state: "privacy",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "privacy_indicator"
    };
  }

  if (settings.persistentMusicPill && inputs.isMusicPlaying) {
    return {
      visible: true,
      state: "music",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "persistent_music"
    };
  }

  // 5. Resting / Idle (Priority 5)
  if (inputs.workspaceEmpty || !inputs.windowFocused) {
    var restingState = "idle";
    var restingReason = inputs.workspaceEmpty ? "workspace_empty" : "no_window_focused";
    if (inputs.dnd) {
      restingState = "dnd";
      restingReason = "dnd_active";
    } else if (inputs.focusOn) {
      restingState = "focus";
      restingReason = "focus_active";
    }

    return {
      visible: true,
      state: restingState,
      nextExpiry: null,
      wantsKeyboard: false,
      reason: restingReason
    };
  }

  return {
    visible: false,
    state: "hidden",
    nextExpiry: null,
    wantsKeyboard: false,
    reason: "window_focused_resting"
  };
}

/**
 * Manages transient event queue according to priority replacement rules:
 * - Purges expired events
 * - Lower-priority event never overrides higher-priority active event
 * - Same-priority or same-kind replaces previous
 */
function postEvent(queue, newEvent, now) {
  now = typeof now === "number" ? now : Date.now();
  var current = (queue || []).filter(function(e) {
    return e && typeof e.expiry === "number" && e.expiry > now;
  });

  var duration = typeof newEvent.duration === "number" ? newEvent.duration : 1500;
  var expiry = typeof newEvent.expiry === "number" ? newEvent.expiry : (now + duration);
  var priority = newEvent.priority !== undefined ? newEvent.priority : PRIORITY.TRANSIENT;

  var item = {
    id: newEvent.id || newEvent.kind,
    kind: newEvent.kind,
    priority: priority,
    duration: duration,
    expiry: expiry,
    wantsKeyboard: Boolean(newEvent.wantsKeyboard)
  };

  var replaced = false;
  var result = [];
  for (var i = 0; i < current.length; i++) {
    var existing = current[i];
    if (existing.kind === item.kind || existing.id === item.id) {
      if (item.priority <= existing.priority) {
        result.push(item);
        replaced = true;
      } else {
        result.push(existing);
        replaced = true;
      }
    } else if (existing.priority === item.priority) {
      if (!replaced) {
        result.push(item);
        replaced = true;
      }
    } else {
      result.push(existing);
    }
  }

  if (!replaced) {
    result.push(item);
  }

  return result;
}

/**
 * Formats island status into standard human-readable and scriptable string:
 * state: <mode>, reason: <reason>, visible: <bool>, pinned: <bool>
 *
 * @param {string|Object} state - State string or object with { state, reason, visible, pinned }
 * @param {string} [reason] - Reason string
 * @param {boolean} [visible] - Visibility boolean
 * @param {boolean} [pinned] - Pinned boolean
 * @returns {string} Formatted status string
 */
function formatStatus(state, reason, visible, pinned) {
  var s = (typeof state === "object" && state !== null) ? state : {
    state: state,
    reason: reason,
    visible: visible,
    pinned: pinned
  };
  var stateVal = s.state !== undefined && s.state !== null ? s.state : "hidden";
  var reasonVal = s.reason !== undefined && s.reason !== null ? s.reason : "unknown";
  var visibleVal = Boolean(s.visible);
  var pinnedVal = Boolean(s.pinned);
  return "state: " + stateVal + ", reason: " + reasonVal + ", visible: " + visibleVal + ", pinned: " + pinnedVal;
}

/**
 * Formats state transition message for GPS_DEBUG logging.
 *
 * @param {string} oldState - Previous state
 * @param {string} newState - Next/new state
 * @param {string} reason - Transition reason
 * @returns {string} Formatted log message
 */
function formatTransitionLog(oldState, newState, reason) {
  var oldVal = oldState ? oldState : "none";
  var newVal = newState ? newState : "none";
  var r = reason ? reason : "unknown";
  return "[GPS Island] Transition: " + oldVal + " -> " + newVal + " (reason: " + r + ")";
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PRIORITY: PRIORITY,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    resolveIslandSettings: resolveIslandSettings,
    evaluateVisibility: evaluateVisibility,
    postEvent: postEvent,
    formatStatus: formatStatus,
    formatTransitionLog: formatTransitionLog
  };
}


