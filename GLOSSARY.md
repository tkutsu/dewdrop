# Quickshell Desktop Shell

This shell provides the desktop bar, launcher, and power menu, with controls and information for the current desktop session.

## Language

### Bar and workspaces

**Bar**:
The strip at the top of a screen that contains workspace navigation, the clock, and desktop status and controls. Each configured screen has its own bar.
_Avoid_: Panel, taskbar (for the whole bar)

**Pill**:
A rounded glass container on the bar that holds one module or a group of modules.
_Avoid_: Island, slab (for the whole container)

**Module**:
A unit of information or control within the bar, such as music, audio, or tasks. A module may contain several interactive items.
_Avoid_: Widget, plugin

**Workspace**:
A numbered desktop containing windows. The bar groups application icons by workspace.
_Avoid_: Tag, desktop (when referring to a workspace)

**Application group**:
The windows belonging to the same application within one workspace, represented by one icon. Windows of that application on another workspace belong to a separate group.
_Avoid_: Application (when referring to the group of windows)

**Urgency**:
A window's request for attention, reflected by its application icon on the bar. Urgency is independent of which window or workspace is focused.
_Avoid_: Focus, selection (for an attention request)

### Drawer and module visibility

**Drawer**:
The collapsible group of quiet, unpinned modules in the right pill. Its handle reveals those modules in their usual places on the bar.
_Avoid_: Overflow menu, hidden modules menu

**Present module**:
A module that is available on the bar in the current session. A present module may be stowed in the drawer.
_Avoid_: Visible module (for presence alone)

**Quiet module**:
A module whose current state does not call for a place outside the closed drawer. A present quiet module remains accessible through the drawer.
_Avoid_: Disabled module, inactive module

**Pinned module**:
A drawer module the user has chosen to keep visible even when quiet and the drawer is closed. A pin persists across shell restarts, but does not override absence.
_Avoid_: Enabled module, always-on module

**Stowed module**:
A module currently folded out of view. Drawer modules are stowed when quiet, unpinned, and the drawer is closed; the music, countdown, and notice modules can also be stowed when they have nothing to display.
_Avoid_: Disabled module, removed module

### Popups and overlays

**Popup**:
A window anchored to a bar item that contains details, controls, or a menu. An opened popup stays available until dismissed or replaced by another bar popup.
_Avoid_: Tooltip, overlay, popover

**Popup owner**:
The bar item whose popup is currently open. Across the bars, only one item owns an open popup at a time.
_Avoid_: Hovered item, focused window

**Popup browsing**:
Switching an already open popup to another item's popup by resting the pointer on that item's popup control.
_Avoid_: Tooltip handover, hover opening (when no popup is open)

**Tooltip**:
A short description of a bar item's name or state, shown after the pointer rests on it. Tooltips are suppressed while a bar popup is open.
_Avoid_: Popup, help menu

**Overlay**:
A screen-sized presentation for the launcher or power menu on the focused screen. The open menu takes keyboard input, and a click outside its box dismisses it.
_Avoid_: Popup, fullscreen application

### Launcher

**Launcher**:
The keyboard-driven menu for opening applications and accessing files, windows, clipboard history, web search, mail, music, tasks, timers, calculations, and commands.
_Avoid_: Application launcher (when referring to all its capabilities), quick-entry overlay

**Launcher query**:
The text entered into the launcher, including any prefix that selects a mode. A query can express a search or a direct action such as creating a task or setting a timer.
_Avoid_: Search term (for every kind of query)

**Launcher mode**:
The kind of request the launcher is currently handling. A mode can be selected by a prefix or inferred from the query; an unprefixed query can produce several kinds of result.
_Avoid_: Tab, search engine (for a mode)

**Mode prefix**:
A leading character that explicitly selects a launcher mode.
_Avoid_: Shortcut, engine key

**Search engine**:
A destination for a web query, selectable within the launcher's web search mode.
_Avoid_: Launcher mode, browser

**Launcher result**:
A row offered in response to a launcher query, representing an action, an item, or an informational status. Informational results have no action to activate.
_Avoid_: Application, match (for every result)

**Frecency**:
A measure of how often and how recently the user has chosen a launcher item. It influences ranking alongside how well an item matches the query.
_Avoid_: Frequency, recency (for the combined measure)

**File preview**:
The launcher's view of the selected file's contents or the selected folder's entries.
_Avoid_: File popup, search result

### Tasks, mail, and agenda

**Task**:
A Google Tasks item that can be created or completed through the shell, with an optional due day. Tasks belong to task lists.
_Avoid_: Reminder, calendar event, timer

**Due day**:
The calendar day on which a task is due, without a time of day. A task is overdue when its due day precedes today.
_Avoid_: Deadline time, due instant

**Task count**:
The number of incomplete tasks that are overdue, due today, or undated. Future-dated tasks appear in the task list but do not contribute to the bar's count.
_Avoid_: Total tasks, tasks due today (for the badge count)

**Mail thread**:
A Gmail conversation containing one or more messages, presented as one mail item in the shell.
_Avoid_: Message, email (when counting conversations)

**Unread mail count**:
The number of unread threads in the Gmail inbox, including threads not shown in the popup.
_Avoid_: Unread message count, visible mail count

**Agenda**:
The read-only view of events from the Google account's selected, owned calendars, associated with the clock's calendar view.
_Avoid_: Task list, alarm schedule

**Calendar event**:
A timed or all-day entry in the agenda. An event spanning several local calendar days belongs to each day it touches.
_Avoid_: Task, alarm

### Timers and alarms

**Countdown**:
A timer set for a duration, with an optional label. It can be paused, resumed, or adjusted.
_Avoid_: Alarm, stopwatch

**Alarm**:
A timer set for a local time of day, optionally repeating on selected weekdays.
_Avoid_: Countdown, duration timer

**Focused countdown**:
The countdown represented on the bar: the running countdown due soonest, or the first paused countdown when none are running. Ringing entries take precedence over it in the bar's display.
_Avoid_: Selected timer, focused alarm

**Ringing entry**:
A countdown or alarm that has fired and is awaiting dismissal or the end of its ringing period. A repeating alarm can have a ringing entry while its next occurrence is already scheduled.
_Avoid_: Running timer, pending alarm

### Notifications

**Notification**:
A desktop message from an application or the shell, possibly carrying actions and an urgency level.
_Avoid_: Notice (for the underlying message), unread mail

**Notice**:
The temporary presentation of an arriving notification beside the clock. Closing a notice leaves a retained notification available in the notification centre.
_Avoid_: Notification (when referring only to its bar presentation), popup

**Notification centre**:
The bell's popup containing notifications currently retained by the shell. Its count includes retained notifications regardless of whether their notices have been seen.
_Avoid_: Unread notifications, notification history (implying a permanent archive)

**Fleeting notification**:
A notification intended only for the moment of arrival and normally released when its notice ends. Opening it in the notification centre retains it for later interaction.
_Avoid_: Retained notification, notice (for the underlying message)

**Notification burst**:
The additional arrivals during an already visible notice, represented by the notice's extra count.
_Avoid_: Notification total, unread count

**Do not disturb**:
A mode that suppresses arriving notices except those marked critical. Retained notifications remain available in the notification centre.
_Avoid_: Disable notifications, mute all alerts

### Music

**Music library**:
The collection of tracks known to the music player, browsable in the launcher by artist, album, and track. Stored playlists are offered alongside the library.
_Avoid_: Queue, playlist

**Queue**:
The current ordered sequence of tracks available for playback, including when playback is paused or stopped.
_Avoid_: Library, stored playlist

**Stored playlist**:
A named, saved sequence of tracks that can be loaded into the queue.
_Avoid_: Queue, album

**Queue action**:
Adding selected music to the end of the current queue.
_Avoid_: Play action, play-next action

**Play action**:
Replacing the current queue with the selected music and starting playback.
_Avoid_: Resume, queue action

### Desktop controls

**Caffeine**:
The shell's switch for keeping the screen awake by inhibiting desktop idling.
_Avoid_: Power mode, night mode

**Night mode**:
The desktop display mode that combines warmer screen colour with dimmed monitor backlight. A low brightness setting alone does not mean night mode is on.
_Avoid_: Dark theme, brightness level
