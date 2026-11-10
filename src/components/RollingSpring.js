.pragma library

// A damped spring's step response at time t, with damping ratio zeta,
// scaled to settle within 2% at `settle` (all in durations). Shared by
// RollingText and RollingGlyph.
function damped(t, zeta, settle) {
    if (t <= 0)
        return 0;
    if (zeta >= 0.999) {
        const k = 5.83 / settle;
        return 1 - (1 + k * t) * Math.exp(-k * t);
    }
    const omega = 4 / (zeta * settle);
    const k = zeta * omega;
    const wd = omega * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-k * t) * (Math.cos(wd * t) + (k / wd) * Math.sin(wd * t));
}
