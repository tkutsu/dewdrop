# Fabric press prototypes

Run `LAB_SCENE=glass qs -p ~/.config/quickshell/lab.qml` to compare the three press styles. The lab sits at the bottom of the screen, takes no input, and repeats the same press on all three columns. Stop that lab instance when finished.

All samples use the fixed Wide satin border shared by the pills and workspace glass. The first row shows it at the bar's actual height; the larger dark samples make the border easier to inspect.

| Press | Setting | Effect |
| --- | --- | --- |
| P1, Cushion | `pillPressStyle: "cushion"` | A softer 7% dent with a broad 160-pixel spread |
| P2, Fabric | `pillPressStyle: "fabric"` | A deeper dent with a 115-pixel spread |
| P3, Deep fabric | `pillPressStyle: "deep"` | The deepest dent, with a 150-pixel spread |

Choose a press style in Settings, Bar, Appearance. Turn on "Press the bar's fabric" to use the chosen press. It stays off by default and under Reduce motion. A tap takes 160 ms to shrink the glass and 310 ms to recover; a held press keeps the dent until released. The timer and music outlines bend with the glass; icons and text keep their shape during fabric presses. Tracks hide during popup and arrival morphs, then fade in once the glass settles. Click lighting is reduced to a quarter of its previous strength.

The saved image and animation previews are in `~/.local/share/quickshell/prototypes/glass-2026-10-11/`.

Popups anchor directly to their bar items. The bar rests on Bottom and moves to Top while hovered or while a popup is open, holding that layer through the popup fade. Popup keyboard input comes through the bar.
