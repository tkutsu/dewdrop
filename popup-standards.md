# Popup standards

AGENTS.md defines the current popup rules. This document explains the reasons
behind them. The references are macOS menu bar extras and Control Center.

## Shared structure

A common header and section structure makes controls predictable across popups.
The header holds actions for the whole popup; each section holds its own
controls. PopupSection owns its separator spacing so callers do not accumulate
extra padding.

The shared popup chrome, motion and keyboard handling belong to Popup.qml.
Music and the calendar retain the artwork and month grid that shape their
content. Tray menus remain untitled.

## Controls communicate their purpose

A switch represents an on/off state. A choice control selects among several
states. A lit framed button carries an option's state through its fill. An
action button keeps its label while it runs, with progress shown in a note.
Stable labels keep controls recognizable when their state changes.

The fuller application's button sits in the header so it is visible without
scrolling through the popup. Destructive actions require a second press to
reduce accidental activation.

## Consistent dimensions and text

List and control popups share a width so browsing between them does not keep
changing the box's width. Notifications, mail, tasks and updates use the wider
list width. Graphs, artwork and the month grid determine their own widths.

Text sizes express the role of a line: title or readout, two-line row title or
heading, and secondary information. Theme colours carry emphasis consistently
across popups. Title Case identifies controls; sentence case identifies notes.

PopupNote gives empty, progress and trouble messages consistent spacing and
colour. Keeping these messages separate from controls avoids changing a
button's identity while an operation runs.

## Verification

scripts/test-popup-standards.py builds each popup, checks warnings from its own
code and verifies the shared widths. Add new popups to its lists.
