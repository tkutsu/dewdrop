# UI links

Render every UI link in grey. Use `Theme.label2` for QML links.
For `Text.RichText`, set the colour inside the link markup; `linkColor` applies only to `Text.StyledText`.

# Popups

Build a bar popup from the shared parts, top to bottom, following macOS's menu bar extras (reasons in `popup-standards.md`):

- `PopupHeader`: the title, with controls for the whole popup on its right. When the popup has one main action (add, upgrade), the title is that button: `addable`, with `addGlyph` at its right end.
- `PopupSection` for each later part: a hairline and a heading, with controls for that part on its right. It owns the air round its hairline, so never pad above one by hand. The first part straight under the header takes `ruled: false`.
- `PopupNote` for empty, in-progress and trouble lines (`warn: true` for trouble).
- When a fuller app exists (Network Settings, btop, Gmail), a framed glyph-only `PopupButton` with `Theme.glyph.openApp` at the far right of the header. It dismisses the popup and opens the app. No footers.

Width: `Theme.popupWidth` for lists and controls, `Theme.popupWideWidth` for notifications, mail, tasks and updates. A popup sets its own width only when a graph, grid, artwork or month shapes it. Body spacing is the default `Theme.popupSpacing`.

Pick a control by what it does:

- On or off for the whole thing or for a section (Wi-Fi, Parallax): `SettingSwitch` with `checked` and `onToggled`, first among the controls of its header or `PopupSection` so the buttons follow it, with `anchors.verticalCenter: parent.verticalCenter`. More states than two (Night Mode's Off, On, Auto) take a `SettingChoice` in the same place, never a second switch; what only one state uses unfolds under the heading while it is chosen (Night Mode's hours).
- An option: framed `PopupButton` with `lit`, which fills it grey. The fill carries the state; the label stays fixed.
- An action: framed `PopupButton`, `live: false` while it runs, label fixed.
- Destructive: arm on the first press (check glyph, `warn`), act on the second, disarm when the pointer leaves the row.

Every framed header button carries a `glyph` after its label (`PopupButton` draws it on the right); add a named one to `Theme.glyph` when none fits.

Text: `popupTextSize` for titles, one-line rows and readouts; `captionSize` for two-line row titles and headings; `footnoteSize` for second lines. Emphasis comes from colour: `Theme.fg`, `label2`, `label3`, `warn`. Title Case for titles, headings and buttons; sentence case for notes. Button and link labels are plain words; "…", one character, belongs to notes about something under way ("Looking for networks…").

Add every new popup to the lists in `scripts/test-popup-standards.py`.
