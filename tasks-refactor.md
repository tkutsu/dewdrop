# Tasks refactor

The tasks workflow stays what it is: type a line from the phone, the launcher
or the right pill, see it on the desktop, cross it off. This makes it better
without adding moving parts. Google lists become sections you drag tasks
between, tasks can be nested by dropping one onto another, and ticking a task
crosses it out instead of making it vanish.

## Decisions

- **Sections are Google task lists**, drawn in Google's list order. Whether
  they are stages (Doing / Next / Later) or areas (Work / Home) is up to the
  user; the code treats them as plain lists.
- **Manual order.** Inside a section, tasks sit in Google's `position` order,
  which is the order you dragged them into. Dates no longer sort the popup.
  The dot and the date chip still say what is late.
- **The bar's count stays date-based**: overdue, due today and undated, as
  now (see GLOSSARY "Task count").
- **The launcher routes by word.** In `,` mode, the first word that is not a
  date names a section if it matches one; otherwise the task goes to the
  default section, chosen in settings.
- **One drag component** shared by the music queue and the tasks popup.
- **No timers or calendar.** Tasks stay tasks.

## What Google allows

Checked against the `tasks.move` reference:

- `tasks.move` takes `parent`, `previous` and `destinationTasklist`. Moving
  within a list, across lists and into or out of a parent is one call.
- Recurring tasks can't change lists. Repeating and assigned tasks can't be
  parents or be nested. A rejected move rolls back on screen.
- The reference does not say whether a parent's subtasks follow it across
  lists. Check this live before relying on it (Phase 2b).
- The API has no priority, no "in progress" status and no star. Position and
  section stand in for all three.
- Google Tasks shows one level of nesting, so the shell allows one level.

## Phase 1: sections, manual order, launcher routing

`services/Tasks.qml`

- Keep subtasks instead of dropping them (`if (item.parent) return null`).
  Each task gets `parent` and, on parents, `children` in position order.
- Add `sections`: one entry per list, `{ id, title, tasks }`, tasks in
  position order with their children.
- Add `rows`: the flat model the popup draws, in order: section header, task,
  its subtasks, next task, and so on. Each row has a `kind` of `header`,
  `task` or `subtask`. Empty sections are left out.
- `overdue` / `due` / `undated` / `count` / `tooltip` stay as they are. They
  feed the badge and the tooltip, not the popup's order. Subtasks don't count.
- `parse()` also returns `list`:
  - read an optional leading date word, as now;
  - check the next word against section names, ignoring case and spaces
    (`todo` matches "To do");
  - if no date was read before it, a date word may follow the section word,
    so `fri work call x` and `work fri call x` both work;
  - no match: `Settings.defaultTaskList`, else the first list;
  - a section with no title after it: error "No task, only a section".
- `add()` writes to `p.list`. `tasks add` over IPC follows for free.
- The launcher's task rows and `list()` over IPC use section order, so the
  popup, the launcher and the IPC read the same.

`Settings.qml`, `settings.default.json`, `modules/SettingsMenu.qml`

- Replace `omittedTaskList` with `defaultTaskList`, a `choice` control whose
  options come from `Tasks.lists`. Empty or unknown falls back to the first
  list.
- The list-name suffix after each title goes. The section headers carry that
  now, so the omit setting has nothing left to do.

`components/TasksPopup.qml`

- Swap `Flickable` + `Column` + `Repeater` for a `ListView` over
  `Tasks.rows`. Phase 2b needs one flat model.
- Headers: a thin label row with the section name. No headers when there is
  only one list.
- Subtask rows are indented one gutter and keep their own dot.
- A parent with open subtasks shows "N left" where its date would go. "2/5"
  would mean fetching every completed task, so this counts open ones only.
- Rewrite the file's opening comment. It argues against headings; those were
  date groups, and these headings are lists the user chose.

`services/Launcher.qml`

- The add row's subtitle shows the section the line resolved to (now always
  `lists[0].title`).
- Task rows follow section order when nothing is typed.

Done when: the popup shows sections in manual order with subtasks under their
parents; `, work fri call x`, `, fri work call x`, `, call x` and `, work` all
behave as described; and the default section setting changes where `, call x`
lands.

## Phase 2a: extract the drag

**Start from the user's WIP.** At the time of writing, main has uncommitted
changes in `components/MusicPopup.qml` (queue scroll restore, `Connections`
on `Mpd`) and `components/PopupRow.qml`. The reorder ends its settle from
that same `Connections` block. Do this phase once that WIP is committed, or
carry it across the merge without stashing.

New `components/ListReorder.qml`, lifted from `MusicPopup.qml` (the
`MouseArea { id: reorder }` block and the row `Translate`):

```qml
ListReorder {
    id: reorder              // keep the id: scripts/test-music-titles.py aliases it
    view: list               // the ListView
    model: Mpd.queue         // live array; the drag keeps a frozen copy and
                             // settles when this changes
    rowHeight: root.rowHeight
    rightGuard: root.buttonWidth   // presses here never start a drag
    lifted: Component { QueueTrack { … } }    // what the lifted row shows
    canNest: null            // (from, onto) => bool; unset = never
    onMoved: (from, to) => Mpd.moveTo(…)
    onNested: (from, onto) => {}
    onClicked: index => Mpd.playAt(…)
}
// each delegate: transform: Translate { y: reorder.shift(index) }
```

Generic and moving into the component: press and hold (300 ms), dragging and
settling state, elevation, slot from the held row's centre, edge
auto-scroll, the drop animation, holding the landed order until `model`
changes (1 s timeout), the lifted row's shadow, radius and scale, and the
shift formula. Music keeps only its hooks.

Done when: the music queue drags, scrolls at the edges, drops and taps
exactly as before; `scripts/test-music-titles.py` and
`scripts/test-music-queue-scroll.py` pass; `MusicPopup.qml` is about 140
lines shorter.

## Phase 2b: drag tasks, collapse on hold, nest

Interaction:

- Hold a task: every row eases to one line (`rowHeight`), anchored on the
  held row so it stays under the pointer. Empty sections appear as headers
  you can drop under.
- Drop **between** rows: the task moves there; rows slide apart as in the
  queue. Just under a header means first in that section.
- Drop **onto the middle third** of a task row: it becomes that task's
  subtask. The target lights up and nothing slides. This is how Apple
  Reminders does it.
- Drag a subtask out between top-level rows: it becomes a task again.
- Release: rows expand back to their full text.
- `canNest` refuses: onto a subtask, onto itself, and nesting a task that has
  subtasks (one level only). Headers are never lifted.
- A tap still completes. The hold is what starts a drag.

`services/Tasks.qml`

- `move(task, { list, parent, previous })`: show the new order at once and
  clear `snapshot` so the next fetch publishes, as `complete()` does. Then
  `POST …/tasks/{id}/move` with `parent`, `previous` and, across sections,
  `destinationTasklist`. On failure, put the old order back and set
  `trouble`.
- Verify live whether subtasks follow a parent across lists. If they don't,
  move the children after the parent, in order.

Done when: reordering, moving across sections, nesting and un-nesting all
show up on the phone after a sync; a refused move (a recurring task across
lists) snaps back with a message.

## Phase 3: tap to cross out

- A tap strikes the row through and fades it. Tapping again un-strikes it.
- The completion PATCHes when the popup closes, or 10 s after the last tap.
  Nothing is in flight while you can still change your mind.
- Ticking a parent completes its open subtasks too, as the phone app does.
- Delete: the header undo button, `undoable`, `completing`, `restore()` and
  the undo ageing `Timer`. The popup closes itself when the list is empty
  after the commit, not on the tap.
- The launcher's task rows use the same crossed state.
- Accepted cost: a cross-out not yet sent is lost if the bar dies in those
  seconds.

Done when: tap, tap again, close the popup → nothing completed; tap, close →
completed on the phone; tap, wait 10 s → completed with the popup still
open.

## Phase 4: inline editing

- An edit button on hover, in place of copy. The edit field can select and
  copy, so copy has nowhere left to be needed. (Open: keep both?)
- Also `e` on a focused row, through the popup-keys path.
- First line is the title, the rest is notes. Enter saves, Shift+Enter adds a
  line, Esc cancels. PATCH `title` and `notes`.
- Rows with notes show them as a faint line under the title, up to two lines.
- **Risk:** this needs keyboard focus in the popup. The bar takes no focus on
  purpose because a focus grab broke popup hover. Build on the existing popup
  keys (`scripts/test-popup-keys.py`) and check hover still works before
  going further.

Done when: edit, save and cancel work from mouse and keyboard; notes written
here show on the phone; popup hover is unaffected.

## Phase 5 (optional): scroll to reschedule

- On hover, the date chip shows on every row, a ghost "no date" where there
  is none.
- The wheel over the chip moves the day forward or back one per step; past
  today it clears. PATCH 600 ms after the last step.

## Across all phases

- Work in this worktree; merge into main and push when a phase is done.
- Check each phase live: restart the bar and click through it.
- New `scripts/test-tasks.py`, in the style of `scripts/test-launcher.py`:
  parsing (date and section in either order, default section, multi-word
  names, a section without a title), the flat row model, the order during a
  move and after a failed one, cross-out commit timing.
- `GLOSSARY.md`: a task list is drawn as a section; subtasks; the task count
  stays date-based.

## Order

First round: 1 → 2a → 2b → 3. Then 4, then 5 if it is still wanted.
