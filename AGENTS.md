# UI links

Render every UI link in grey. Use `Theme.label2` for QML links.
For `Text.RichText`, set the colour inside the link markup; `linkColor` applies only to `Text.StyledText`.

# Popups

Build a bar popup from the shared parts, top to bottom, following macOS's menu bar extras (reasons in `popup-standards.md`):

- `PopupHeader`: the title, with controls for the whole popup on its right.
- `PopupSection` for each later part: a hairline and a heading, with controls for that part on its right.
- `PopupNote` for empty, in-progress and trouble lines (`warn: true` for trouble).
- `PopupSeparator` then `PopupLink` at the foot when a fuller app exists ("Network Settings…").

Width: `Theme.popupWidth` for lists and controls, `Theme.popupWideWidth` for tasks and mail. A popup sets its own width only when a graph, grid, artwork or month shapes it. Body spacing is the default `Theme.popupSpacing`.

Pick a control by what it does:

- On or off for the whole thing: `SettingSwitch` with `checked` and `onToggled`.
- An option: framed `PopupButton` with `lit`. The fill carries the state; the label stays fixed.
- An action: framed `PopupButton`, `live: false` while it runs, label fixed.
- Destructive: arm on the first press (check glyph, `warn`), act on the second, disarm when the pointer leaves the row.

Text: `popupTextSize` for titles, one-line rows and readouts; `captionSize` for two-line row titles and headings; `footnoteSize` for second lines. Emphasis comes from colour: `Theme.fg`, `label2`, `label3`, `warn`. Title Case for titles, headings and buttons; sentence case for notes. Write "…" as one character, and end a label with it only when it opens something more.

Add every new popup to the lists in `scripts/test-popup-standards.py`.
