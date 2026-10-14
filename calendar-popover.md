# Calendar popover

Make the clock's month view a place to work in, not only to look at. Clicking
a day selects it instead of leaving for Google. The list under the grid gets
a header, scrolls, knows what is on now, and its rows act: open an event,
join a call, move a task to a later day.

**Status:** planned 2026-10-15. Nothing built yet.

## Decisions

- **Clicking a day selects it.** The list shows the selected day and stays
  on it while the pointer moves. Hovering only lights a day; it no longer
  changes the list. This replaces "tapping a day opens Google Calendar" from
  calendar-events.md Phase 4. Google is one click away in the list's header.
- **Nothing selected means today.** The selection is `picked || Agenda.today`,
  so a popover left open across midnight moves on to the new day, and every
  open starts on today.
- **A faint day from a neighbouring month** turns the grid to that month as
  well as selecting the day.
- **Right-click still adds** on that day (calendar-events.md Phase 4), and
  selects it too.
- **No text field in the popover.** Adding still goes through the launcher's
  `,` line, because the bar avoids keyboard focus.
- **Now and next apply to today only.** Other days list their events
  unchanged.
- **"Next" looks only at months already fetched.** Agenda holds the shown
  month and two weeks past its end. If nothing turns up there, the line says
  "Nothing on" and no extra request is made.
- **Postponing pushes later, never earlier.** It counts from the later of the
  task's day and today: +1 day or +7 days. An overdue task goes to tomorrow
  or a week from today. A task due Friday goes to Saturday or the next Friday.
- **The event description is not kept.** There is no room to show it. It is
  read once, for a meeting link, and then dropped.

## Phase 1: Agenda keeps more of each event

`services/Agenda.qml`

- `normalise()` also keeps:
  - `url`: `htmlLink`, the event's own page in Google Calendar.
  - `place`: `location`, or `""`.
  - `link`: the first of `hangoutLink`, the `video` entry point in
    `conferenceData`, an `http(s)` URL in `location`, or a Meet, Zoom or
    Teams URL in `description`.
- `next(day)`: the earliest event that starts after `day`, from the months
  held, or `null`. Today's later events don't count. "Next" is only asked for
  when the day itself is empty.

Done when: an event with a Meet link and one with a Zoom URL in its location
both come back with `link` set, and `next()` finds an event two weeks out in
the following month.

## Phase 2: select a day, and the list's header

`components/Calendar.qml`

- `property string picked`, `readonly property string selected: picked ||
  Agenda.today`. Tap and Return on a day set `picked`. The month title,
  which goes back to the current month, clears it.
- The selected day, unless it is today, gets a filled disc in
  `Theme.selectionStrong`. Today keeps its own disc. Hover keeps the
  lighter `Theme.selection`.
- Delete `hoverDay`, `litDay`, `letGo` and `listHover`. They only kept the
  list from snapping back while the pointer moved to it.
- A `PopupHeader` over the list, `addable`:
  - Title: the date, then how far it is: `Wed 15 Oct · today`,
    `Thu 16 Oct · tomorrow`, `Thu 23 Oct · in 8 days`, `Mon 6 Oct · 9 days
    ago`.
  - The plus adds on the selected day (`addOn`).
  - A `PopupButton` with `Theme.glyph.openApp` opens that day in Google
    Calendar (`openDay`). Name: "Open in Google Calendar".
- Day cells' accessible description: "Pointer: click selects; right-click adds
  a task or event".
- `reserveHeight` takes the header into account.

Done when: clicking Friday keeps Friday's list under the pointer all the way
down to it; + opens the launcher with `, <friday> `; ↗ opens Friday in
Google; clicking the month title goes back to today.

## Phase 3: the list scrolls

`components/Calendar.qml`

- The `Column` and `Repeater` become a `ListView` with `SmoothScroll` and
  `ScrollEdges`, as in `TasksPopup`. Its height is the day's rows, up to
  `listRows`.
- `listRows` goes from 4 to 5 and the "+N more" line is removed. The window
  keeps the height it has now.
- Selecting another day scrolls the list back to the top. Phase 4 changes
  this for today.
- Rows keep `PopupRow`'s default gesture policy, so a drag scrolls and a tap
  still taps.

Done when: a day with eight events shows five rows and scrolls to the rest
with the wheel, with fades at the edges, and the popup doesn't change size.

## Phase 4: now, next, and what's coming

`components/Calendar.qml`, `services/Agenda.qml`, `services/Tasks.qml`

On today, from `Google.now` (updated every minute):

- **Over**: a timed event that has ended is drawn at 0.4 opacity, the same as
  a ticked-off task. All-day events are never over.
- **Now**: the time column says `now` in `Theme.fg`, and a 2px line under
  the row fills from its start to its end.
- **Next**: the first event still to come says `in 25m` when it is under an
  hour away, otherwise its time.
- When the list opens on today, it scrolls so the first event that isn't over
  is at the top. Earlier events stay above it, a scroll away.

On an empty day, today or later:

- Under "Nothing today" or "Nothing on", one row: `Next  Fri 17 · 15:00
  Dentist`. It is the earlier of `Agenda.next(day)` and the first dated task
  after `day` (`Tasks.topLevel`). If both fall on the same day, the event
  wins.
- Tapping it selects that day, turning the month if needed.
- If nothing is found, the row isn't shown.

For testing, the popover reads the time from a `now` property bound to
`Google.now`, which the test can override.

Done when: at 14:30, a 14:00–15:00 event shows `now` with its line half full,
a 15:00 event shows `in 30m`, a 9:00 event is dimmed, and an empty Sunday
shows Monday's first event and selects Monday when tapped.

## Phase 5: rows that act

`components/Calendar.qml`, `services/Tasks.qml`, `Theme.qml`

**Events**

- Tapping an event row opens its `url` in the Calendar app, through
  `Settings.webApp("pwa-gcalendar.sh", url, url)` like `openDay`. Name:
  "Open <title>".
- An event with a `link` gets a Join `PopupButton` at the right edge, with a
  new `Theme.glyph.video` (nf-md-video). It shows on hover, and all the time
  on the event that is on now and on the next one if it starts within 10
  minutes. It opens the link with `Qt.openUrlExternally`.
- An event with a `place` and no `link` gets `Theme.glyph.pin` in
  `Theme.label2` at the right edge. The place is shown in a `Tooltip` on
  hover and in the row's accessible description.
- The title gets narrower by however many buttons are showing.

**Tasks**

- `Tasks.reschedule(task, day)`: `PATCH` with `due: day + "T00:00:00.000Z"`.
  It changes the row straight away and puts it back on failure, like `edit()`.
  While another write is running, it is queued as `"due"` and run by
  `flushPending`. Ticked-off tasks are left alone.
- A hovered task row gets two caption-size buttons, `+1d` and `+1w`, named
  "Postpone a day" and "Postpone a week" (see Decisions).
- The task leaves the list and its dot moves to the new day. If the write
  fails, the row comes back and `Tasks.trouble` says why.

Done when: tapping an event opens it in the app; Join opens a Meet link and
is already showing five minutes before the call; `+1d` on an overdue task
moves it to tomorrow in the popover, the tasks popup and Google Tasks on the
phone.

## Across all phases

- Phase 2 goes first: the rows can only act once the list stays on a day.
  Phase 3 comes before Phase 4 because "scroll to now" needs a list that
  scrolls. Phases 1 and 5 can be built together.
- Extend `scripts/test-calendar-tasks.py`: selection (tap, Return, month
  title, faint day), header text, scroll limits, now/next/over with an
  overridden `now`, the next-up row, link extraction, and `reschedule`
  (body, queueing, revert on failure).
- `calendar-events.md` Phase 4: change "Tapping a day keeps opening Google
  Calendar" to point here.
- `GLOSSARY.md`: **Selected day**, the day the list is about.
- Work in a worktree; merge into main and push when a phase is done. Check
  each phase live in the bar.
