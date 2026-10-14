# Gmail triage

Turn the mail popup from a list you read into a list you clear: one click
(or one swipe) per mail, every action undoable, the next mail opening by
itself. Plus the small things that save a trip to Gmail: copying a login
code, saving an attachment, unsubscribing, turning a mail into a task.

**Status:** all five phases built 2026-10-15, one commit each. Tests:
`scripts/test-email` (offline service and popup), `scripts/test-email-popup.py`
(the real popup in a scratch shell; pass a folder to keep screenshots) and
`scripts/test-gmail-attachment.py`. Swiping on the touchpad is tested with
synthetic wheel events only: ydotool cannot make touchpad gestures, and a
live mouse drag would have archived real mail. Its direction follows how
content scrolls on this machine (`pixelDelta.x`); check it by hand.

## Scope

| From the brainstorm             | In  |
| ------------------------------- | --- |
| 1 Count Primary only            | yes |
| 2 Hover actions on every row    | yes |
| 3 Archive as the main verb      | yes |
| 4 Undo instead of caution       | yes |
| 5 Auto-advance                  | yes |
| 6 Gmail letter keys             | no  |
| Swipe on a row                  | yes |
| One-time code chip              | yes |
| New-mail notifications          | yes |
| Sender monograms                | yes |
| Badge as a dot                  | no (see below) |
| Inline quick reply              | no  |
| Mail → task                     | yes |
| Attachments                     | yes |
| One-click unsubscribe           | yes |

**The badge stays a number.** A dot is better only when the number is noise.
Counting Primary alone makes it signal: 1 and 7 call for different
responses, and a dot can't tell them apart.

## Decisions

- **Primary is what counts.** The badge, the popup's list, `@` in the
  launcher and notifications all read `category:primary`. Everything else
  unread in the inbox is one folded row at the end of the list,
  `Other · 14`, which unfolds into the same rows with the same actions.
- **Archive means done.** It removes both `INBOX` and `UNREAD`. Gmail's own
  archive leaves the mail unread, but here the archive comes after you've
  seen the row, so the mail is read. A read archived mail can't come back to
  inflate a count anywhere.
- **Three verbs on every row, always in the same place:** archive, mark read,
  star. They take over the time column on hover. A starred row keeps a small
  star beside its time when it isn't hovered.
- **The open mail adds a footer** under its text: open in Gmail, make a task,
  unsubscribe (only when the mail offers it), and its attachment chips above
  that. The header line keeps the same three verbs as a closed row, so
  nothing moves when a row opens.
- **Every action from the popup waits 4 s before it reaches Gmail.** The row
  leaves at once. A pill at the popup's foot says what happened
  ("Archived · Undo"). Undo cancels the latest action and puts its row back
  where it was, opened if it was open. Closing the popup sends everything
  still waiting immediately. If the bar dies in those 4 s the action is
  lost, which only means the mail comes back.
- **Compound actions undo as one.** Task + archive, unsubscribe + archive,
  copy code + mark read: the whole thing waits, so Undo cancels all of it.
  The clipboard copy is the one part that happens at once.
- **Notification buttons act at once.** By then the notification is gone, so
  there is nothing left to show an undo on.
- **Auto-advance:** after an action on the open mail, the mail below it
  opens. If there is nothing below, the one above opens. When the list is
  empty the popup closes, as it already does for mark read.
- **Swipe left archives, swipe right marks read**, on the touchpad (a
  horizontal wheel gesture) and with a mouse drag. The coloured action shows
  behind the row as it moves. Past 40 % of the row's width the glyph pops,
  and letting go commits. Short of that, the row springs back on
  `Theme.drawerSpring`. The axis locks on the first movement, so a vertical
  scroll never turns sideways.
- **Code chip:** a 4–8 digit code (also `123 456`, `123-456`, `G-123456`)
  near a keyword (code, verification, OTP, passcode, PIN, one-time, κωδικός,
  επαλήθευση) in the subject, the snippet or the loaded text. The chip shows
  on the row's second line. Clicking it copies the code and marks the mail
  read.
- **Notifications are for Primary only**, one per new thread, through
  `notify-send` like any other app, so they get the server's own cards, DND
  and centre. Buttons: Archive, Mark read, plus Copy code when there is one.
  Clicking the card opens the thread in Gmail. More than 3 new in one poll is
  one card ("5 new mails") whose click opens the popup. Nothing is sent for
  the first poll after the bar starts, or while the popup is open. A mail
  dealt with anywhere in the shell dismisses its card, matched by an
  `x-gmail-thread` hint.
- **Monograms:** a 26 px circle with the sender's initials, coloured from a
  hash of the address over a fixed set of 8 muted tones. The popup widens
  from 320 to 340 px to make room.
- **Mail → task:** title is the subject, notes are the sender and a link to
  the thread (`#all/<id>`, which works after archiving), in the default list
  with no date. Then the mail is archived.
- **Attachments:** chips under each message's text with name and size. A
  click saves the file to `~/Downloads` (a numbered name if one already
  exists) and opens it. Inline images (`Content-ID` + `inline`, e.g.
  signature logos) are left out.
- **Unsubscribe** shows only when `List-Unsubscribe` has an https address.
  With `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (RFC 8058, which
  Gmail requires of bulk senders) it's one queued POST, then archive, all
  undoable within the 4 s. Without that header the button opens the page in
  the browser. A mailto-only sender gets no button.
- **The Google token never leaves Google.** The unsubscribe POST goes through
  `Http.request` with no auth header, not through `Google.send`.

## What Google allows

- `gmail.modify` covers archive, star, mark read, attachments and send.
  Nothing here needs a new consent. The comment in `scripts/gtasks-auth`
  that says it "cannot send" is wrong. Fix it in phase 1.
- `threads.list` takes `q` together with `labelIds`, so Primary is the
  current call plus `q=category:primary`. The `Other` count is the
  unfiltered list (what runs now) minus the Primary ids: one more list call
  per poll.
- `threads.list` doesn't return labels or headers. The unsubscribe headers
  come with the metadata call that already runs per changed thread: add
  `List-Unsubscribe` and `List-Unsubscribe-Post` to `metadataHeaders`.
- Attachment ids, names and sizes are in the `format=full` payload the body
  read already fetches. Nothing extra to ask for until a chip is clicked.
- Starring is per message in Gmail: star adds `STARRED` to the thread's last
  message, unstar removes it from the whole thread.

## Phases

Each phase works on its own and gets merged on its own.

### Phase 1: the action queue (services/Email.qml)

- Primary/Other split in `fetchThreads`, `total` = Primary, new `other`
  count and `otherThreads` (detailed lazily, when the row unfolds).
- `pending` queue: `{kind, row, index, wasOpen, at}`, one Timer for the
  oldest due. `act(kind, row)`, `undo()`, `flush()`.
- `restore(row)`: back into `threads` in date order, `opened` marker
  cleared, `total` + 1.
- Verbs: `archive`, `markRead` (rewired through the queue), `star`,
  `unstar`.
- Tooltip: `3 unread · 12 other`.
- Fix the `gtasks-auth` scope comment.
- Tests in `scripts/test-email`: the split's counts, commit after the delay,
  undo restoring order, flush on close, a poll in the 4 s not bringing back
  a pending row.

### Phase 2: the popup (components/EmailPopup.qml)

- Monograms and the 340 px width.
- Hover verbs replacing the time column; the persistent star.
- Footer on the open mail (open, task and unsubscribe stubs hidden until
  phase 5).
- Undo pill at the foot, inside the reserved height so the popup doesn't
  resize.
- Auto-advance.
- The `Other` row and its unfold.
- Every verb also an accessible button (the a11y tree tests).

### Phase 3: swipe

- `WheelHandler` (horizontal, pixel deltas only) and `DragHandler` (x
  axis) on each row, sharing one offset.
- Gesture end from the wheel's `ScrollEnd` phase, with a 150 ms idle
  fallback.
- Backing colours and glyphs, threshold pop, spring back, slide off then
  collapse.
- Checked live with synthetic input (announced once, per the usual
  routine).

### Phase 4: codes and notifications

- `codeOf(text)` in Email.qml; `code` on each row; the chip.
- New-thread detection against the last poll's message ids; the batching
  rule; `notify-send --wait` per card, its stdout is the chosen action.
- `drop()` dismisses the matching card.
- Tests: `codeOf` against real-looking subjects, including near misses
  (prices, years, order numbers); the batching and first-poll rules.

### Phase 5: task, attachments, unsubscribe

- `Tasks.add` gains a `notes` argument; the `task` verb.
- `files` map (message id → parts) filled by the body read; chips;
  `scripts/gmail-attachment` (reads the token from the environment, never
  argv; fetches, decodes base64url, writes, prints the path); then
  `xdg-open`.
- Header parsing for unsubscribe; the queued POST; the browser fallback.
- Tests: part collection with inline images; header parsing of the common
  shapes; file-name sanitising (no `/`, no leading `.`).

## Not touched

- The launcher's `@` keeps reading and Tab-to-read. It only follows the
  Primary change; its rows get no verbs.
- Compose stays the Gmail PWA.

## Defaults to confirm

1. Archive also marks read.
2. Swipe works with the mouse as well as the touchpad.
3. The `Other` row unfolds in place, and there is no "archive all" on it.
