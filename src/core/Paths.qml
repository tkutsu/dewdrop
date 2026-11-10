pragma Singleton

import Quickshell

// Where the shell keeps what it writes. Nothing else builds a path out of
// $HOME, so a file moves in one place.
//
// Four kinds of file, each in a quickshell/ of its own under the matching
// XDG base directory: state is what the shell remembers across restarts (the
// drawer's pins, the timers, the notifications), data is what it was handed
// and cannot make again (the Google sign-in), cache is anything it can
// (wallpaper thumbnails), and runtime is what is only true for this session
// (the panel's brightness). Not Quickshell.stateDir and friends: those are one
// level further down, per shell, and the files were here first.
//
// Shared with Settings and the components through qs.src.core.
Singleton {
    id: root

    function state(name: string): string {
        return root.under("XDG_STATE_HOME", ".local/state", name);
    }

    function data(name: string): string {
        return root.under("XDG_DATA_HOME", ".local/share", name);
    }

    function cache(name: string): string {
        return root.under("XDG_CACHE_HOME", ".cache", name);
    }

    function runtime(name: string): string {
        return root.under("XDG_RUNTIME_DIR", ".cache", name);
    }

    function under(variable: string, fallback: string, name: string): string {
        return `${Quickshell.env(variable) || `${Settings.home}/${fallback}`}/quickshell/${name}`;
    }
}
