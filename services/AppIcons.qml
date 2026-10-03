pragma Singleton

import Quickshell
import qs

Singleton {
    // Prefer overrides and desktop metadata, then try the window class as a theme name.
    function resolve(windowClass: string, entry: var): string {
        const override = Theme.appIconOverride[windowClass];
        if (override)
            return override;
        if (entry?.icon)
            return entry.icon;
        for (const candidate of [windowClass, windowClass.toLowerCase()])
            if (candidate && Quickshell.hasThemeIcon(candidate))
                return candidate;
        return "";
    }
}
