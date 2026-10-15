# Popup standards

Make every bar popup read as one family, with macOS's menu bar extras (Wi-Fi,
Bluetooth, Sound, Battery) and Control Center as the reference. The chrome is
already shared: one frosted box, one shadow, one keyboard model, one header.
What drifts is everything inside the box: widths, how a toggle looks, how a
section starts, text sizes and dimming, capitalisation, empty states.

**Status:** built 2026-10-15, all five phases. The rules a new popup follows
are in AGENTS.md; this file keeps the audit and the reasons. Two changes from
the plan: System keeps its 12 px padding (the standard 6 plus its rows' 6
inset looks the same, with less churn), and Music keeps its 21 px header
buttons, which need an eye on the artwork column to change.

Revised the same day after review: lit options are grey rather than white,
every header button has an icon, labels carry no "…", Parallax, Monochrome
and Night Mode are sections with switches, Updates' title is the upgrade
button, and Notifications, Mail and Tasks share one 400 px width. AGENTS.md
has the rules as they stand; the decisions below are the first pass.

## Audit

### Already standard, keep as is

- **Chrome.** Every popup is `Popup.qml`: `popupBg` frost, `Rim`, shadow,
  `popupRadius`, the backdrop probe.
- **Motion.** Three kinds: menus appear at once and fade out, popups grow out
  of their item from 86% on springs, and Music, Timers and Recording morph out
  of their pill. Reduce Motion turns all three into fades.
- **Keys.** Escape, the arrows, Return and Space through `keyPress` and
  `keyStep`; browsing to another popup after resting 300 ms on its item.
- **`PopupHeader`.** Title on the left, controls on the right, the plus
  through `addable`.
- **`PopupRow` and `PopupButton`.** One press policy, one hover fill,
  `PressGlass`.
- **The `ChoiceRow` grid.** Tick column at the inset, names at 32, status
  laid right to left. Keyboard, Network, Bluetooth, Sound and the batteries
  in Devices all use it.

### Drift

| | What varies | Where |
|---|---|---|
| Width | 220, 236, 240, 264, 264, 270, 300, and Sound takes the slider's | Keyboard, Timers, Network, Bluetooth, Devices, Display, Recording, Sound |
| Body spacing | 0, 3, 6, 8, 9, 10 | Tasks and Calendar 0, Mail 3, Weather, Wallpaper and Music 8, System 9, Updates 10 |
| Padding | System overrides `hPadding` and `vPadding` to 12 | `SysPopup` |
| Header | Notifications hand-builds a copy of `PopupHeader`; System has none | `NotificationsPopup`, `SysPopup` |
| On/off | Wi-Fi and Bluetooth: a button whose label flips ("turn Wi-Fi off"). Night mode, feels like, parallax, drift: a lit button. Schedule: a second header with an "on"/"off" button | Network, Bluetooth, Display, Weather, Wallpaper |
| Labels that flip | "look for devices"/"stop looking", "change"/"cancel", "refresh"/"loading..."/"checking…"/"retry" | Bluetooth, Weather, Updates |
| Section starts | a caption line ("Batteries", "Microphones"), a second `PopupHeader` ("Schedule", "Monochrome"), a bare hairline (Sound, Music), a hairline then a caption (Recording) | |
| Separators | the rows' width in popups, edge to edge in tray menus | `MenuPopup` |
| Checked items | a tick column in lists, a "● "/"○ " text prefix in tray menus | `MenuPopup` |
| One-line rows | 11 px in lists (`ChoiceRow`, Timers), 12 px in tray menus | |
| Dimming text | `label2`/`label3` in some places, opacity literals in others: 0.4, 0.45, 0.5, 0.55, 0.6, 0.75, 0.8, 0.85, 0.9 | System, Music, Timers, Mail |
| Case | lowercase buttons ("upgrade", "clean up", "night mode", "clear", "undo", "open", "task") beside Title Case ones ("Mute", "Unmute", "Stop") | |
| Ellipsis | "…" and "..." both ("Looking for networks…", "Reading mail...", "loading...") | Weather, Tasks, Mail, Updates |
| Empty state | the same `label2` `PopupText` written out about a dozen times, once at opacity 0.6 ("Nothing set") | |
| Forget | Network and Bluetooth forget at the first press; Music asks twice before quitting or deleting a playlist | |
| Fuller app | only on right-click (nm-connection-editor, blueman, btop, Google Tasks, Gmail), and nothing in the popup says it is there | |

## Decisions

- **One anatomy.** Top to bottom: header, sections, an optional footer. The
  header is the title on the left and controls on the right. The footer is a
  hairline and one row that opens the fuller app. Music and the calendar keep
  their own tops (artwork, month navigation), as Now Playing and the Calendar
  widget do. Tray menus stay untitled, like any NSMenu.
- **Three kinds of control, each drawn one way.**
  - A **master switch** turns the whole thing on or off: Wi-Fi, Bluetooth,
    the night mode schedule. It is a switch (`SettingSwitch`) at the right
    end of its header or section heading, as in the Wi-Fi menu.
  - An **option** changes what the popup shows or does: Night Mode, Feels
    Like, Parallax, Drift, Scan. It is a lit framed button, like Control
    Center's toggle tiles. Its label never changes; the fill says whether it
    is on.
  - An **action** does something once: Upgrade, Refresh, Clean Up, Clear,
    Undo, Open. It is a plain framed button. While it runs it goes faint
    (`live: false`) and keeps its label.

  State no longer lives in labels, so "turn Wi-Fi off", "stop looking",
  "checking…" and "loading..." go. Progress and trouble go on the note line.
- **Sections start with a heading.** `PopupSection` draws a hairline, then a
  heading: caption size, DemiBold, `label2`, Title Case, with optional
  controls on its right the way `PopupHeader` takes them. This is Apple's
  "Output" and "Input" in the Sound menu. No bare hairlines, and no second
  `PopupHeader` inside a popup.
- **Separators span the rows' fill**, in popups and in menus. Menus reach the
  box's edge today; macOS has inset them to the highlight since Big Sur. This
  reverses the comment on `MenuPopup`'s separator.
- **Checked menu rows use the tick column.** A menu with any checkable row
  reserves the column for all its rows, as NSMenu does. "●/○" goes.
- **Widths.** `Theme.popupWidth: 280` for every list and control popup:
  Keyboard, Network, Bluetooth, Sound, Display, Devices, Recording, Timers.
  Updates is at least that wide and grows for long package lines. Tasks and
  Mail take `Theme.popupWideWidth: 340`. Weather, Notifications, Wallpaper,
  Music, System and Calendar stay sized by their graph, cards, grid, artwork,
  cores and month. Apple's menu extras share one width, and here it also
  stops the box jumping when browsing from one popup to the next.
- **Padding and spacing.** Every popup uses `Popup`'s padding. System stops
  overriding it and insets its own rows by `popupInset`. Body spacing
  defaults to `Theme.popupSpacing: 6` in `Popup.qml`. A list whose rows
  should touch keeps them in its own `Column`.
- **Type.** Three sizes, each with one job:
  - `popupTextSize` (12): titles, one-line rows in lists and menus alike,
    readouts. `ChoiceRow` and Timers move up from 11.
  - `captionSize` (11): the title of a two-line row (Mail, Tasks, Devices,
    Recording, as now), section headings, framed button labels.
  - `footnoteSize` (10): second lines, metadata, credits.

  Emphasis comes from colour, not opacity: `Theme.fg`, `label2`, `label3`,
  `warn`. No opacity literals on text. Controls keep their own states inside
  `PopupButton` (quiet 0.6, faint 0.15).
- **Words.** Title Case for titles, headings, buttons and menu-like rows;
  sentence case for notes and descriptions. Ellipsis is "…", one character,
  never "...". A label ends in "…" only when it opens something more (a
  window, a terminal, a search): "Network Settings…", "Clean Up…", "Change
  Location…". `Accessible.name`s follow the same case.
- **Empty and status lines.** `PopupNote`: a `PopupText` at the inset in
  `label2` that wraps; `warn` turns it `Theme.warn`. "No devices", "Wi-Fi is
  off", "Looking for networks…", "System up to date".
- **Forget asks twice.** Network and Bluetooth arm Forget on the first press
  (the glyph turns to a check in the warning colour) and act on the second,
  as Music's quit and playlist delete do. The arm lasts until the pointer
  leaves the row. Apple confirms Forget This Network too.
- **The fuller app is a footer row.** `PopupLink`: one row at the inset in
  `popupTextSize` that opens the app and dismisses the popup. Network
  "Network Settings…", Bluetooth "Bluetooth Settings…", System "Open btop",
  Tasks "Open Google Tasks", Mail "Open Gmail". Right-click keeps doing the
  same thing. The calendar is covered by calendar-popover.md, which puts
  Google in its list header.
- **Left alone:** the chrome, motion, keys, browsing, the `ChoiceRow` grid,
  Timers' row buttons that are always drawn (a ringing alarm shouldn't need a
  hover), and the Forget buttons that appear on hover (as Notification Center
  does).

## Phase 1: primitives and tokens

`Theme.qml`, `components/Popup.qml`, `components/SettingSwitch.qml`,
`components/ChoiceRow.qml`, new `components/PopupSection.qml`,
`PopupSeparator.qml`, `PopupNote.qml`, `PopupLink.qml`

- Theme: `popupWidth: 280`, `popupWideWidth: 340`, `popupSpacing: 6`.
- `Popup`: body spacing defaults to `Theme.popupSpacing`.
- `PopupSeparator`: one `pillBorder` line in `Theme.stroke`, as wide as its
  parent.
- `PopupSection`: a `PopupSeparator`, then the heading row. `title`, and a
  default property for trailing controls laid from the right edge.
- `PopupNote`: `PopupText` with the inset on both sides, `label2`, word wrap,
  `property bool warn`.
- `PopupLink`: `PopupRow` with one `PopupText` at the inset; `text` and
  `tapped`.
- `SettingSwitch` takes `checked` and emits `toggled` when it has no
  `setting`, with `keyPress` and an `Accessible.CheckBox` role, so a header
  can hold one. `SettingRow` keeps working unchanged.
- `ChoiceRow` names go to `popupTextSize`.

Done when: the shell starts with no new warnings, the settings window's
toggles still work, and `ChoiceRow` names render at 12 px.

## Phase 2: list and control popups

`LanguagePopup`, `NetworkPopup`, `BluetoothPopup`, `AudioPopup`,
`DisplayPopup`, `DrivesPopup`, `PrivacyPopup`, `TimerPopup`, `UpdatesPopup`

- **Keyboard:** `popupWidth`.
- **Network:** `popupWidth`. Wi-Fi switch in the header. `PopupSection
  "Networks"` over the list. Notes through `PopupNote`. Forget asks twice.
  Footer "Network Settings…".
- **Bluetooth:** `popupWidth`. Bluetooth switch in the header and a lit
  "Scan" option beside it. `PopupSection "Devices"`. Notes through
  `PopupNote`. Forget asks twice. Footer "Bluetooth Settings…".
- **Sound:** `popupWidth`. The master slider straight under the header, as in
  the Sound menu, then `PopupSection "Output"`, `"Apps"` (only while
  something plays) and `"Input"`. The input section keeps the `modelData:
  Audio.source` the bare hairline carried, so the wheel over it still moves
  the mic.
- **Display:** `popupWidth`. "Night Mode" lit in the header, the brightness
  slider, then `PopupSection "Schedule"` with a switch on its right, then the
  dials.
- **Devices:** `popupWidth`. "Batteries" becomes a `PopupSection`.
- **Recording:** `popupWidth` (from 300; check that the Mute buttons and the
  input slider still fit). Sections "Apps Using the Microphone",
  "Microphones" and "Screen Sharing" through `PopupSection`; `shareDivider`
  goes. "No active captures" through `PopupNote`.
- **Timers:** `popupWidth`, row titles at 12. "Nothing set" and the phone
  warning through `PopupNote` (the warning with `warn`).
- **Updates:** at least `popupWidth`. "Upgrade", "Refresh" (faint while
  checking) and "Clean Up…". Trouble and "Checking for updates…" through
  `PopupNote`. Spacing from 10 to the default.

Done when: browsing across these popups with the pointer, the box keeps its
width (Updates aside, with a long list); every master on/off is a switch;
`scripts/a11y-tree.py` shows Title Case control names.

## Phase 3: content popups

`NotificationsPopup`, `EmailPopup`, `TasksPopup`, `WeatherPopup`,
`WallpaperPopup`, `MusicPopup`, `SysPopup`, `Calendar`

- **Notifications:** the hand-built header becomes `PopupHeader` with a
  framed "Clear All", keeping its `ChoiceBlink`. Group "clear" becomes
  "Clear". "No notifications" through `PopupNote`.
- **Mail:** `popupWideWidth`. "Undo", "Open", "Add Task", "Saving…". Status
  through `PopupNote` ("Reading mail…"). Opacity literals to tokens. Footer
  "Open Gmail". Body spacing to the default; the thread list keeps its own 3.
- **Tasks:** `popupWideWidth`. "Waiting to save…", "Connecting…" and "No
  tasks" through `PopupNote`. Footer "Open Google Tasks".
- **Weather:** "Feels Like" (lit), "Change Location…" (lit while the search
  is open; pressing it again closes the search), "Refresh" (faint while
  loading). "Searching…", "Loading the forecast…", "Updating the forecast…".
  Spacing from 8 to the default.
- **Wallpaper:** "Parallax" and "Drift". The second `PopupHeader`
  "Monochrome" becomes a `PopupSection` with Drift on its right; the
  hand-drawn hairline goes.
- **Music:** opacity literals to `label2` and `label3`. Hand-drawn hairlines
  become `PopupSeparator`. `headerButtonSize` (21) goes back to the framed
  default (20) if the artwork column still lines up. Spacing from 8 to the
  default if the artwork still fits.
- **System:** drop the padding override and inset rows by `popupInset`.
  `Head` stays (a heading that carries its figure, like the Battery menu's
  title). `Line` labels in Title Case ("Clock", "Fans", "Memory Clock",
  "VRAM", "Free", "Read / Write"). Opacity literals to `label2` and `label3`.
  Footer "Open btop".
- **Calendar:** words only ("Connecting…", case). The rest belongs to
  calendar-popover.md.

Done when: `grep -nE 'opacity: 0\.' components/*Popup*.qml
components/Calendar.qml` finds no `PopupText`, `grep -n '\.\.\."' components/*Popup*.qml` finds
nothing in the popups, and every framed label is Title Case.

## Phase 4: tray menus

`components/MenuPopup.qml`

- Check and radio rows draw `Theme.glyph.check` in a tick column, reserved
  for every row of a menu that has any checkable row; "● " and "○ " go.
- Separators span the rows' width instead of reaching the box's edge.

Done when: a tray menu with a check item shows the tick in the column and the
other rows' labels line up with it.

## Phase 5: write it down

`AGENTS.md`

- A short "Popups" section: the anatomy, the three kinds of control, the
  widths, the three type sizes and four colours, the words rule, and which
  primitive draws what. A new popup should only need to read that.

Done when: the section is there and matches what was built.
