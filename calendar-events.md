# Calendar events

Put tasks on the calendar popover, and add events from the same `,` line that
already writes tasks, timers and alarms. No new prefix and no new popup.

**Status:** all four phases implemented 2026-10-14. Writing events needs one
re-consent (`gtasks-auth`) for the `calendar.events` scope. Leaving a day for
the list under the grid keeps that day's list, so its tasks can be ticked.
Alarm previews keep their day word: `alarm 15:00 today  ·  event 15:00–16:00`.

## Decisions

The `,` line grows by one rule: the more of a time you give, the bigger the
thing it makes.

| Typed                        | Makes                                              |
| ---------------------------- | -------------------------------------------------- |
| `, call bank`                | task, default section                              |
| `, work call bank`           | task in the Work section (tasks-refactor.md)       |
| `, fri call bank`            | task due Friday                                    |
| `, 25m tea`                  | timer, as now                                      |
| `, 15:00 call bank`          | alarm at 15:00 **and** an event 15:00–16:00        |
| `, today 15:00 call bank`    | event today 15:00–16:00, no alarm                  |
| `, fri 15:00 call bank`      | event Friday 15:00–16:00                           |
| `, 2026-11-03 9:30 dentist`  | event on that date                                 |

- **A dated task needs nothing extra.** Google Calendar on the web and the
  phone already shows dated Google Tasks from the same account on their day.
  The shell writes the task and Google puts it on the calendar. What is
  missing is the shell's own calendar popover, which reads only events
  (Phase 1).
- **Events last one hour.**
- **A day plus a time is an event.** A time with no day is an alarm plus an
  event on the day the alarm rings, which is tomorrow if that time has passed
  today. Writing the day (`today 15:00`) is how to put something on the
  calendar without an alarm.
- **Durations never make events.** `25m tea` is only a timer.
- **The event an alarm makes has no reminders of its own**
  (`reminders: { useDefault: false, overrides: [] }`). The alarm is the ring,
  and it already reaches the phone through Pushover; a calendar reminder on
  top would ring twice. Events with a day keep the calendar's default
  reminders.
- **The alarm and its event are independent.** Cancelling the alarm leaves
  the event, which is a record of the plan; delete it in Google Calendar.
- **Primary calendar.** Events go to `primary`. A setting can come later if
  another calendar is ever wanted.
- **Section words are for tasks.** On an event line, a section word stays in
  the title.

## What Google allows

- Tasks carry a due **date** only. The API drops any time written to `due`
  and never returns one set in the phone app. That is why a timed thing is an
  event, not a task.
- The Calendar API doesn't return Google Tasks among events, so the popover
  takes them from `services/Tasks.qml`, not from Calendar.
- Writing events needs the `calendar.events` scope. Reading the list of
  calendars still needs `calendar.readonly`, so the scope is added, not
  swapped. One re-consent: run `gtasks-auth`.
- `events.quickAdd` parses free text on Google's side, but shows what it
  understood only after creating the event, and only in English. Not used:
  the launcher previews the parse before anything is sent.

## Phase 1: tasks on the calendar popover

Read-only here; nothing new is written to Google.

`components/Calendar.qml`, `services/Agenda.qml`

- The day list under the grid shows that day's dated tasks after its events,
  with the task glyph and the urgency dot. Subtasks are left out.
- A day with only tasks gets the same busy dot as a day with events. A dated
  task is something written down for that day, which is what the dot means.
- Merged in the popover, not in `Agenda`: `Agenda` stays the Calendar API
  service, and `Tasks` stays the Tasks one.
- Tapping a task row in the day list crosses it out, the same way as in the
  tasks popup, once tasks-refactor.md Phase 3 lands. Until then the rows are
  only read.

Done when: a task due Friday shows in Friday's list and gives Friday a dot,
and completing it elsewhere removes both at the next poll.

## Phase 2: writing events

`scripts/gtasks-auth`

- Add `calendar.events` to `SCOPE`, keeping `calendar.readonly`. Update the
  comment above it: the agenda now writes events too. The shell already
  flags a missing scope (`Google.scopeMissing`) and offers reconnect.

`services/Agenda.qml`

- `insert({ title, start, end, reminders })`:
  `POST /calendars/primary/events` with `start.dateTime` and `end.dateTime`
  as local times with their UTC offset. On success, refetch the month it
  landed in so the dot and the day list show it.
- On failure: set `trouble`, and tell the user right away through the
  shell's notice, because the event was made from the launcher and no
  popup is open to show `trouble`. The alarm, if any, is already set and
  stays set.

Done when: an event inserted over IPC shows in Google Calendar and in the
popover within a refetch; with the scope missing, the failure is visible and
reconnect fixes it.

## Phase 3: the `,` line

`services/Launcher.qml`, `services/Tasks.qml`, `services/Timers.qml`

- One classification for a `,` line, in this order:
  1. A duration or clock time first (`TimersParse.js`, as now): timer, or
     alarm plus event when it is a clock time.
  2. A day word (`Tasks.readDay`), then a clock time that `TimersParse.js`
     reads as an alarm: event on that day, at that time, titled with the
     alarm's label.
  3. Otherwise: a task, with day and section as in tasks-refactor.md.
- No time parsing of its own. Event times come from `TimersParse.js`, days
  from `Tasks.readDay`, so `9:30`, `21:30`, `9pm` and `9:30am` mean the same
  thing for alarms and events. A bare `9` stays a nine-minute timer, so
  `fri 9 x` is a task due Friday titled "9 x", not an event.
- A time with no title: "No event, only a time".
- The launcher's top row previews what Enter will make, from the parse, not
  the raw line:
  - `alarm 15:00  ·  event 15:00–16:00`
  - `event  ·  fri 15:00–16:00`
  - and when the scope is missing: `alarm 15:00  ·  calendar needs reconnect`.
- For an alarm line, the event's day is the one the alarm resolved to, so the
  two never disagree across midnight.
- `qs ipc call tasks add` takes the same line and makes the same things.

Done when: every row of the table above does what it says, with the preview
matching; `scripts/test-tasks.py` (from tasks-refactor.md) covers the
classification, including a past time today going to tomorrow for both the
alarm and its event.

## Phase 4: new event from the popover

`components/Calendar.qml`

- Tapping a day keeps opening Google Calendar on that day.
- Right-clicking a day opens the launcher with `, 2026-10-23 ` typed in for
  that day: a title makes a dated task, a time and a title make an event. The
  same move as the + in the tasks popup (`Launcher.openWith`), and no text
  field inside the popover, which would need keyboard focus the bar avoids.

Done when: right-click a day, type `15:00 call bank`, Enter, and the event is
on that day in both the popover and Google Calendar.

## Across all phases

- Do this after tasks-refactor.md Phase 1, which changes `Tasks.parse()`
  (sections). Phase 3 here builds on that parse.
- Work in a worktree; merge into main and push when a phase is done. Check
  each phase live in the bar.
- `GLOSSARY.md`: Event, as made from the `,` line. Wherever the `,` grammar
  is described (the launcher hint, README), add the table above.
