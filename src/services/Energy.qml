pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.src.core

// The machine's power, for the energy module: the laptop's battery when it
// has one, the energy mode (power-profiles-daemon), and the idle timers that
// turn the display off and put the machine to sleep.
//
// The timers are the bar's own rather than hypridle's, so a change in the
// popup holds at once. They count from the last input and wait while an idle
// inhibitor is held, Caffeine's among them. Sleep goes through Power.run,
// which locks the screen first.
Singleton {
    id: root

    // The laptop's own battery, or null. A wired gadget's battery is the
    // Disks popup's (Drives.batteries).
    readonly property var battery: UPower.devices.values.find(d => d.isLaptopBattery && d.isPresent) ?? null
    readonly property int percent: root.battery ? Math.round(root.battery.percentage * 100) : -1
    // On the adapter: charging, full, or held at a charge limit.
    readonly property bool plugged: root.battery !== null && !UPower.onBattery
    readonly property bool charging: root.battery?.state === UPowerDeviceState.Charging
    readonly property bool full: root.battery?.state === UPowerDeviceState.FullyCharged
    readonly property bool low: root.battery !== null && !root.plugged && root.percent <= 20
    // Hours and minutes to empty, or to full while charging; "" while
    // UPower is still estimating.
    readonly property string timeLeft: {
        const seconds = !root.battery ? 0 : root.charging ? root.battery.timeToFull : root.plugged ? 0 : root.battery.timeToEmpty;
        if (seconds <= 0)
            return "";
        const minutes = Math.round(seconds / 60);
        return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
    }
    // Watts in or out, "" when nothing flows.
    readonly property string draw: {
        const rate = Math.abs(root.battery?.changeRate ?? 0);
        return rate >= 0.05 ? `${rate.toFixed(1)} W` : "";
    }
    // How much the battery holds against new, -1 where it does not say.
    // Read on either scale: the docs do not give one.
    readonly property int health: {
        if (!root.battery?.healthSupported)
            return -1;
        const health = root.battery.healthPercentage;
        return Math.round(health <= 1 ? health * 100 : health);
    }
    // One line for the tooltip.
    readonly property string summary: {
        if (!root.battery)
            return "";
        const state = root.charging ? (root.timeLeft ? `${root.timeLeft} until full` : "charging")
            : root.full ? "fully charged" : root.plugged ? "not charging"
            : root.timeLeft ? `${root.timeLeft} left` : "";
        return `${root.percent}%` + (state ? ` · ${state}` : "");
    }

    // The energy mode, under macOS's names: Automatic is the daemon's
    // Balanced, its default. High Power only where the machine has it.
    readonly property bool hasModes: Tools.has("powerprofilesctl")
    readonly property var modes: [
        { value: PowerProfile.PowerSaver, label: "Low Power" },
        { value: PowerProfile.Balanced, label: "Automatic" },
        ...(PowerProfiles.hasPerformanceProfile ? [{ value: PowerProfile.Performance, label: "High Power" }] : [])
    ]
    readonly property int mode: PowerProfiles.profile
    readonly property string modeName: root.modes.find(m => m.value === root.mode)?.label ?? ""
    // Why High Power is not giving all it could, while it is chosen.
    readonly property string heldBack: root.mode !== PowerProfile.Performance ? ""
        : PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected ? "High Power is held back while the laptop is on a lap"
        : PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature ? "High Power is held back while the machine is hot"
        : ""

    function setMode(profile: int): void {
        PowerProfiles.profile = profile;
    }

    // The waits the popup and the settings window offer, in minutes; 0 is
    // never.
    readonly property var displayOffStops: [1, 2, 5, 10, 15, 30, 60, 0]
    readonly property var sleepStops: [10, 15, 30, 45, 60, 120, 180, 0]

    // As a pop-up button's options, Never last. A wait typed into
    // settings.json that is not among them joins them, so the button never
    // comes up blank.
    function waits(stops: var, current: int): var {
        const say = minutes => minutes === 0 ? "Never"
            : minutes % 60 === 0 ? (minutes === 60 ? "1 Hour" : `${minutes / 60} Hours`)
            : minutes === 1 ? "1 Minute" : `${minutes} Minutes`;
        return [...new Set([...stops, current])]
            .sort((a, b) => (a || Infinity) - (b || Infinity))
            .map(minutes => ({ value: minutes, label: say(minutes) }));
    }

    // A timeout of 0 would report idle at once, so Never turns the monitor
    // off instead.
    //
    // Caffeine turns both off too: Hyprland ignores the inhibitor of a
    // surface it doesn't show, and a fullscreen window hides the bar's.
    // Turned off with the screen already dark (Caffeine from a script or
    // its timer), this one would never send "on", and a key press doesn't
    // wake the screen by itself, so it sends that first.
    IdleMonitor {
        enabled: Settings.displayOffMinutes > 0 && !Caffeine.active
        timeout: Settings.displayOffMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: Hyprland.dispatch(`hl.dsp.dpms({ action = "${isIdle ? "off" : "on"}" })`)
        onEnabledChanged: if (!enabled && isIdle)
            Hyprland.dispatch(`hl.dsp.dpms({ action = "on" })`)
    }

    IdleMonitor {
        enabled: Settings.sleepMinutes > 0 && !Caffeine.active
        timeout: Settings.sleepMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle)
            Power.run("--suspend")
    }
}
