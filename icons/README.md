These drawings are from the WhiteSur icon theme by vinceliuice
(https://github.com/vinceliuice/WhiteSur-icon-theme), licensed GPL-3.0.
Theme.panel() loads them by path for the power menu and the idle inhibitor.

The two caffeine cups are retouched: white rather than #ececec, and outlined
with a 0.4-unit stroke of their own colour. The bar draws them at 14px, where
WhiteSur's 1-unit walls came out under a pixel thick and a step greyer than
the outlined glyphs beside them (1.1px against the bell's 1.4px).

audio-volume-0 to -6 are Material Design's volume_high (Pictogrammers,
https://pictogrammers.com, licensed Apache-2.0), taken out of Symbols Nerd
Font as the bar drew it, split so each wave has its own opacity: 0 has both
waves at .25, 1 to 3 bring the inner one to .5, .75 and full, 4 to 6 the
outer one. audio-volume-muted is volume_off, taken out the same way.

launcher.svg is our own drawing in the manner of SF Symbols' magnifyingglass
(not a copy of it), in an 18px box so it lands on whole pixels. It is pure
white rather than WhiteSur's #ececec: Glyph gives a drawing the label's alpha,
and #ececec under that came out a step dimmer than the text beside it.
launcher-tabler.svg is Tabler's "search" (https://github.com/tabler/tabler-icons),
licensed MIT, redrawn the same way.

network-wireless-0 to -4 and -off are our own drawings in the manner of SF
Symbols' wifi (not a copy of it): a dot and three 1.5px arcs about it, in a
20px box with 13px of ink, which is what Glyph fits a drawing to at the bar's
glyph size, so nothing rescales them. 0 has every part at .25; each step
after lights one more, dot first. -off is the faint set struck through.
