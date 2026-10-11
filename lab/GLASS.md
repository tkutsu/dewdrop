# Pill sheen and fabric press prototypes

Run `LAB_SCENE=glass qs -p ~/.config/quickshell/lab.qml` to compare all six options. The lab sits at the bottom of the screen, takes no input, and repeats the same press on all three columns. Stop that lab instance when finished.

The first row shows the sheen at the bar's actual height. The larger dark samples below it make the two diagonal highlights and their quiet corners easier to compare.

| Sheen | Setting | Effect |
| --- | --- | --- |
| S1, Soft diagonal | `pillSheen: "soft"` | Broad top-left and bottom-right highlights |
| S2, Wide satin | `pillSheen: "wide"` | Broader and fainter highlights |
| S3, Steep diagonal | `pillSheen: "steep"` | A steeper angle toward the bottom right |

| Press | Setting | Effect |
| --- | --- | --- |
| P1, Cushion | `pillPressStyle: "cushion"` | A softer 7% dent with a broad 160-pixel spread |
| P2, Fabric | `pillPressStyle: "fabric"` | A deeper dent with a 115-pixel spread |
| P3, Deep fabric | `pillPressStyle: "deep"` | The deepest dent, with a 150-pixel spread |

Choose a sheen and a press independently in Settings, Bar, Appearance. Turn on "Press the bar's fabric" to use the chosen press. It stays off by default and under Reduce motion. A tap takes 55 ms to shrink the glass and 310 ms to recover; a held press keeps the dent until released. The timer and music outlines bend with the glass; icons and text keep their shape during fabric presses. Tracks hide during popup and arrival morphs, then fade in once the glass settles. Click lighting is reduced to a quarter of its previous strength.

The saved image and animation previews are in `~/.local/share/quickshell/prototypes/glass-2026-10-11/`.

The bar now stays on the Bottom layer, so floating windows can cover the pills. A separate transparent Top host holds popup anchors and receives popup keyboard input. Hovering no longer moves the pills above an active window's shadow, which caused the thin bottom highlight.

## More visible resting light

Run `LAB_SCENE=sheen qs -p ~/.config/quickshell/lab.qml` for S4, S5, and S6. All samples use the actual 30-pixel bar height, with hover and click light disabled. The dark middle row shows how far the light spreads beside each edge.

| Sheen | Setting | Effect |
| --- | --- | --- |
| S4, Visible edge | `pillSheen: "skim"` | A clearer diagonal rim, with light close to its edge |
| S5, Diffuse rim | `pillSheen: "rim"` | Broader light spreading inward from the rim |
| S6, Soft halo | `pillSheen: "halo"` | Light inside the rim and a faint halo outside it |

These are available in Settings, Bar, Appearance. S1 stays selected until you choose another style. The new comparison is saved as `resting-sheen.png` beside the earlier prototypes.
