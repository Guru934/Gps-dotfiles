// Pure logic for GPS Planner calendar, tasks, and reminder triggers
// Compatible with both QML and Node.js testing environments

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

function formatDateKey(year, monthIndex, day) {
    return year + "-" + pad2(monthIndex + 1) + "-" + pad2(day);
}

function parseDateKey(dateKey) {
    if (!dateKey || typeof dateKey !== "string") return null;
    const parts = dateKey.split("-");
    if (parts.length !== 3) return null;
    return {
        year: parseInt(parts[0], 10),
        monthIndex: parseInt(parts[1], 10) - 1,
        day: parseInt(parts[2], 10)
    };
}

function getDaysInMonth(year, monthIndex) {
    // monthIndex is 0-11
    return new Date(year, monthIndex + 1, 0).getDate();
}

function getMonthDays(year, monthIndex, selectedDateKey, now) {
    const today = (typeof now === "number" || now instanceof Date) ? new Date(now) : new Date();
    const todayKey = formatDateKey(today.getFullYear(), today.getMonth(), today.getDate());

    const daysInCurrent = getDaysInMonth(year, monthIndex);
    const prevMonthIndex = monthIndex === 0 ? 11 : monthIndex - 1;
    const prevYear = monthIndex === 0 ? year - 1 : year;
    const daysInPrev = getDaysInMonth(prevYear, prevMonthIndex);

    const nextMonthIndex = monthIndex === 11 ? 0 : monthIndex + 1;
    const nextYear = monthIndex === 11 ? year + 1 : year;

    // Monday-first: Monday is 0, Sunday is 6
    const firstDay = new Date(year, monthIndex, 1).getDay();
    const leadOffset = (firstDay + 6) % 7;

    const cells = [];

    // 1. Leading days from previous month
    for (let i = leadOffset - 1; i >= 0; i--) {
        const d = daysInPrev - i;
        const key = formatDateKey(prevYear, prevMonthIndex, d);
        cells.push({
            dayNumber: d,
            dateKey: key,
            isOtherMonth: true,
            isToday: key === todayKey,
            isSelected: key === selectedDateKey,
            year: prevYear,
            monthIndex: prevMonthIndex
        });
    }

    // 2. Days in current month
    for (let d = 1; d <= daysInCurrent; d++) {
        const key = formatDateKey(year, monthIndex, d);
        cells.push({
            dayNumber: d,
            dateKey: key,
            isOtherMonth: false,
            isToday: key === todayKey,
            isSelected: key === selectedDateKey,
            year: year,
            monthIndex: monthIndex
        });
    }

    // 3. Trailing days to round out 5 or 6 complete 7-day weeks (35 or 42 cells)
    const targetCount = cells.length <= 35 ? 35 : 42;
    const trailCount = targetCount - cells.length;
    for (let d = 1; d <= trailCount; d++) {
        const key = formatDateKey(nextYear, nextMonthIndex, d);
        cells.push({
            dayNumber: d,
            dateKey: key,
            isOtherMonth: true,
            isToday: key === todayKey,
            isSelected: key === selectedDateKey,
            year: nextYear,
            monthIndex: nextMonthIndex
        });
    }

    return cells;
}

function validateTime(timeStr) {
    if (!timeStr || typeof timeStr !== "string") return "";
    const clean = timeStr.trim();
    if (/^([01]\d|2[0-3]):[0-5]\d$/.test(clean)) {
        return clean;
    }
    return "";
}

function createTask(text, timeStr, dateKey, customId, now) {
    const cleanText = (text || "").trim();
    if (!cleanText) return null;

    const currentTs = (typeof now === "number") ? now : Date.now();
    const id = customId || ("task-" + currentTs + "-" + Math.floor(Math.random() * 10000));
    const validTime = validateTime(timeStr);

    return {
        id: id,
        text: cleanText,
        time: validTime,
        dateKey: dateKey,
        done: false,
        reminderSent: false,
        createdAt: currentTs
    };
}

function addTask(taskList, task) {
    if (!task) return (taskList || []).slice();
    const list = Array.isArray(taskList) ? taskList.slice() : [];
    list.push(task);
    return list;
}

function editTask(taskList, id, updates) {
    if (!Array.isArray(taskList)) return [];
    return taskList.map(function(t) {
        if (t.id !== id) return t;
        const copy = Object.assign({}, t, updates);
        if (updates.time !== undefined) {
            copy.time = validateTime(updates.time);
            // If time was updated and moved forward, allow reminder to fire again
            if (copy.time !== t.time) {
                copy.reminderSent = false;
            }
        }
        return copy;
    });
}

function deleteTask(taskList, id) {
    if (!Array.isArray(taskList)) return [];
    return taskList.filter(function(t) { return t.id !== id; });
}

function toggleTaskDone(taskList, id) {
    if (!Array.isArray(taskList)) return [];
    return taskList.map(function(t) {
        if (t.id !== id) return t;
        return Object.assign({}, t, { done: !t.done });
    });
}

function filterTasks(taskList, dateKey, filterMode) {
    if (!Array.isArray(taskList)) return [];
    const mode = filterMode || "All";
    return taskList.filter(function(t) {
        if (t.dateKey !== dateKey) return false;
        if (mode === "Pending") return !t.done;
        if (mode === "Done") return t.done;
        return true;
    }).sort(function(a, b) {
        // Timed tasks first
        if (a.time && !b.time) return -1;
        if (!a.time && b.time) return 1;
        if (a.time && b.time) return a.time.localeCompare(b.time);
        return a.createdAt - b.createdAt;
    });
}

function carryUnfinishedToToday(taskList, todayKey) {
    if (!Array.isArray(taskList)) return { updatedTasks: [], carriedCount: 0 };
    let carried = 0;
    const updated = taskList.map(function(t) {
        if (!t.done && t.dateKey < todayKey) {
            carried++;
            return Object.assign({}, t, {
                dateKey: todayKey,
                reminderSent: false
            });
        }
        return t;
    });
    return { updatedTasks: updated, carriedCount: carried };
}

function getTaskDotsMap(taskList) {
    const map = {};
    if (!Array.isArray(taskList)) return map;
    for (let i = 0; i < taskList.length; i++) {
        const t = taskList[i];
        if (!map[t.dateKey]) {
            map[t.dateKey] = { total: 0, pending: 0, done: 0 };
        }
        map[t.dateKey].total++;
        if (t.done) map[t.dateKey].done++;
        else map[t.dateKey].pending++;
    }
    return map;
}

function getDueReminders(taskList, now) {
    if (!Array.isArray(taskList)) return [];
    const current = (typeof now === "number" || now instanceof Date) ? new Date(now) : new Date();
    const todayKey = formatDateKey(current.getFullYear(), current.getMonth(), current.getDate());
    const currentTimeStr = pad2(current.getHours()) + ":" + pad2(current.getMinutes());

    const due = [];
    for (let i = 0; i < taskList.length; i++) {
        const t = taskList[i];
        if (!t.done && !t.reminderSent && t.dateKey === todayKey && t.time) {
            if (t.time <= currentTimeStr) {
                due.push(t);
            }
        }
    }
    return due;
}

function markRemindersSent(taskList, dueIds) {
    if (!Array.isArray(taskList)) return [];
    const set = {};
    for (let i = 0; i < dueIds.length; i++) {
        set[dueIds[i]] = true;
    }
    return taskList.map(function(t) {
        if (set[t.id]) {
            return Object.assign({}, t, { reminderSent: true });
        }
        return t;
    });
}

function serialize(taskList) {
    return JSON.stringify({
        version: 1,
        tasks: Array.isArray(taskList) ? taskList : []
    }, null, 2);
}

function deserialize(raw) {
    try {
        if (!raw || typeof raw !== "string") return [];
        const parsed = JSON.parse(raw);
        if (parsed && Array.isArray(parsed.tasks)) {
            return parsed.tasks;
        }
        return [];
    } catch (e) {
        return [];
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        pad2,
        formatDateKey,
        parseDateKey,
        getDaysInMonth,
        getMonthDays,
        validateTime,
        createTask,
        addTask,
        editTask,
        deleteTask,
        toggleTaskDone,
        filterTasks,
        carryUnfinishedToToday,
        getTaskDotsMap,
        getDueReminders,
        markRemindersSent,
        serialize,
        deserialize
    };
}
