pragma Singleton

import Quickshell
import qs.src.core

Singleton {
    // Games never name themselves. Steam gives each window steam_app_<id>,
    // gamescope (how jc141 launches them) answers to its own name, and Wine
    // takes the .exe's. Asked first, so a Steam game cannot fuzzy-match its
    // way to Steam's own icon.
    function isGame(windowClass: string): bool {
        return /^(steam_app_\d+|gamescope)$|\.exe$/i.test(windowClass);
    }

    // A Steam game's own drawing goes by the name Steam gives its shortcuts'
    // icons, steam_icon_<id>; the rest share the controller.
    function gameIcon(windowClass: string): string {
        const own = windowClass.replace(/^steam_app_(\d+)$/i, "steam_icon_$1");
        return own !== windowClass && Quickshell.hasThemeIcon(own) ? own : Theme.gameIcon;
    }

    // Prefer overrides and desktop metadata, then try the window class as a theme name.
    function resolve(windowClass: string, entry: var): string {
        const override = Theme.appIconOverride[windowClass];
        if (override)
            return override;
        if (isGame(windowClass))
            return gameIcon(windowClass);
        if (entry?.icon)
            return entry.icon;
        for (const candidate of [windowClass, windowClass.toLowerCase()])
            if (candidate && Quickshell.hasThemeIcon(candidate))
                return candidate;
        return "";
    }
}
