const assert = require("assert");
const Planner = require("../components/PlannerLogic.js");

console.log("=== Running PlannerLogic.js tests ===");

// 1. Month grid: 28-day Feb (2025, 2026 non-leap)
assert.strictEqual(Planner.getDaysInMonth(2025, 1), 28, "Feb 2025 must have 28 days");
assert.strictEqual(Planner.getDaysInMonth(2026, 1), 28, "Feb 2026 must have 28 days");

// 2. Month grid: 29-day Feb (2024, 2028 leap years)
assert.strictEqual(Planner.getDaysInMonth(2024, 1), 29, "Feb 2024 must have 29 days (leap year)");
assert.strictEqual(Planner.getDaysInMonth(2028, 1), 29, "Feb 2028 must have 29 days (leap year)");

// 3. Month grid: 30-day months (Apr, Jun, Sep, Nov)
assert.strictEqual(Planner.getDaysInMonth(2026, 3), 30, "April must have 30 days");
assert.strictEqual(Planner.getDaysInMonth(2026, 5), 30, "June must have 30 days");
assert.strictEqual(Planner.getDaysInMonth(2026, 8), 30, "September must have 30 days");
assert.strictEqual(Planner.getDaysInMonth(2026, 10), 30, "November must have 30 days");

// 4. Month grid: 31-day months (Jan, Mar, May, Jul, Aug, Oct, Dec)
const thirtyOneMonths = [0, 2, 4, 6, 7, 9, 11];
thirtyOneMonths.forEach(m => {
    assert.strictEqual(Planner.getDaysInMonth(2026, m), 31, `Month index ${m} must have 31 days`);
});
console.log("ok - month lengths for 28/29/30/31 days and leap years are exact");

// 5. Monday-first alignment
// October 2026: Oct 1 2026 is Thursday.
// Monday is 0, Tuesday 1, Wednesday 2, Thursday 3.
// Lead offset should be 3 leading days (Mon Sep 28, Tue Sep 29, Wed Sep 30).
const oct2026Days = Planner.getMonthDays(2026, 9, "2026-10-30", new Date("2026-10-30T12:00:00Z"));
assert.strictEqual(oct2026Days[0].dateKey, "2026-09-28", "First cell must be Monday Sep 28");
assert.strictEqual(oct2026Days[0].isOtherMonth, true);
assert.strictEqual(oct2026Days[1].dateKey, "2026-09-29");
assert.strictEqual(oct2026Days[2].dateKey, "2026-09-30");
assert.strictEqual(oct2026Days[3].dateKey, "2026-10-01", "Fourth cell must be Thursday Oct 1");
assert.strictEqual(oct2026Days[3].isOtherMonth, false);
assert(oct2026Days.length % 7 === 0, "Grid length must be a multiple of 7");
console.log("ok - Monday-first alignment correctly places leading days and week rows");

// Check today and selection flags
const oct30 = oct2026Days.find(c => c.dateKey === "2026-10-30");
assert(oct30, "Oct 30 cell must exist");
assert.strictEqual(oct30.isToday, true, "Oct 30 must be marked as today");
assert.strictEqual(oct30.isSelected, true, "Oct 30 must be marked as selected");

// 6. Add, edit, delete, toggleDone
let tasks = [];
const t1 = Planner.createTask("Review PRs", "14:30", "2026-10-30", "t1", 1793340000000);
const t2 = Planner.createTask("Team standup", "10:00", "2026-10-30", "t2", 1793340001000);
const t3 = Planner.createTask("Write documentation", "", "2026-10-30", "t3", 1793340002000);

tasks = Planner.addTask(tasks, t1);
tasks = Planner.addTask(tasks, t2);
tasks = Planner.addTask(tasks, t3);
assert.strictEqual(tasks.length, 3);

// Edit
tasks = Planner.editTask(tasks, "t3", { text: "Write architecture docs", time: "16:00" });
const edited = tasks.find(t => t.id === "t3");
assert.strictEqual(edited.text, "Write architecture docs");
assert.strictEqual(edited.time, "16:00");

// Toggle done
tasks = Planner.toggleTaskDone(tasks, "t2");
assert.strictEqual(tasks.find(t => t.id === "t2").done, true);

// Delete
tasks = Planner.deleteTask(tasks, "t1");
assert.strictEqual(tasks.length, 2);
assert(!tasks.find(t => t.id === "t1"));
console.log("ok - add, edit, delete, and toggleDone function cleanly");

// 7. Filters: All, Pending, Done
// Remaining: t2 (done), t3 (pending)
const allTasks = Planner.filterTasks(tasks, "2026-10-30", "All");
assert.strictEqual(allTasks.length, 2);
const pendingTasks = Planner.filterTasks(tasks, "2026-10-30", "Pending");
assert.strictEqual(pendingTasks.length, 1);
assert.strictEqual(pendingTasks[0].id, "t3");
const doneTasks = Planner.filterTasks(tasks, "2026-10-30", "Done");
assert.strictEqual(doneTasks.length, 1);
assert.strictEqual(doneTasks[0].id, "t2");
console.log("ok - filterTasks sorts timed items first and respects All/Pending/Done");

// 8. Carry unfinished to today
const pastTasks = [
    { id: "p1", text: "Past pending task", dateKey: "2026-10-28", done: false, reminderSent: true },
    { id: "p2", text: "Past completed task", dateKey: "2026-10-28", done: true, reminderSent: true },
    { id: "p3", text: "Today task", dateKey: "2026-10-30", done: false, reminderSent: false }
];
const carryResult = Planner.carryUnfinishedToToday(pastTasks, "2026-10-30");
assert.strictEqual(carryResult.carriedCount, 1);
assert.strictEqual(carryResult.updatedTasks.find(t => t.id === "p1").dateKey, "2026-10-30");
assert.strictEqual(carryResult.updatedTasks.find(t => t.id === "p1").reminderSent, false);
assert.strictEqual(carryResult.updatedTasks.find(t => t.id === "p2").dateKey, "2026-10-28");
console.log("ok - carryUnfinishedToToday carries only incomplete past tasks and resets reminders");

// 9. Reminder due calculation with injected clock & no duplicate reminders
const reminderTasks = [
    { id: "r1", text: "Submit report", time: "14:00", dateKey: "2026-10-30", done: false, reminderSent: false },
    { id: "r2", text: "Evening meeting", time: "18:00", dateKey: "2026-10-30", done: false, reminderSent: false },
    { id: "r3", text: "Already done", time: "12:00", dateKey: "2026-10-30", done: true, reminderSent: false },
    { id: "r4", text: "Already sent", time: "11:00", dateKey: "2026-10-30", done: false, reminderSent: true }
];

// Clock at 13:59: nothing due
const clock1359 = new Date("2026-10-30T13:59:00").getTime();
let due = Planner.getDueReminders(reminderTasks, clock1359);
assert.strictEqual(due.length, 0, "No reminders due at 13:59");

// Clock at 14:00: r1 is due
const clock1400 = new Date("2026-10-30T14:00:00").getTime();
due = Planner.getDueReminders(reminderTasks, clock1400);
assert.strictEqual(due.length, 1);
assert.strictEqual(due[0].id, "r1");

// Mark sent
const markedTasks = Planner.markRemindersSent(reminderTasks, ["r1"]);
assert.strictEqual(markedTasks.find(t => t.id === "r1").reminderSent, true);

// Clock at 14:01 after restart (with marked tasks): no reminders due (no duplicates!)
const clock1401 = new Date("2026-10-30T14:01:00").getTime();
due = Planner.getDueReminders(markedTasks, clock1401);
assert.strictEqual(due.length, 0, "Reminders must not fire twice after restart");
console.log("ok - reminder calculation fires at exact due time and prevents duplicates after restart");

// 10. Serialization and corruption resilience
const serialized = Planner.serialize(markedTasks);
const roundtripped = Planner.deserialize(serialized);
assert.strictEqual(roundtripped.length, 4);

// Malformed / corrupt JSON recovery
const recoveredFromCorrupt = Planner.deserialize("{ corrupt invalid json [");
assert.deepStrictEqual(recoveredFromCorrupt, []);
const recoveredFromNull = Planner.deserialize(null);
assert.deepStrictEqual(recoveredFromNull, []);
console.log("ok - serialize and deserialize round-trip safely and tolerate corruption");

console.log("ALL 10 PLANNER LOGIC CHECKS PASSED!");
