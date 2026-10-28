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

  if (inputs.privacyVisible) {
    return {
      visible: true,
      state: "privacy",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: "privacy_indicator"
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
  if (inputs.settings && inputs.settings.persistentMusicPill && inputs.isMusicPlaying) {
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
    return {
      visible: true,
      state: "idle",
      nextExpiry: null,
      wantsKeyboard: false,
      reason: inputs.workspaceEmpty ? "workspace_empty" : "no_window_focused"
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

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PRIORITY: PRIORITY,
    evaluateVisibility: evaluateVisibility,
    postEvent: postEvent
  };
}
