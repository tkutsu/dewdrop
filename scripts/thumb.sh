#!/usr/bin/env bash
# What a file looks like, for the quickshell launcher's / mode.
# See ~/.config/quickshell/components/FilePreview.qml.
#
# Answers on stdout in two parts: a first line saying what kind of answer this
# is, and everything after it being the answer.
#
#   image\n<path>      a picture to draw — the file itself where Qt can read
#                      it, otherwise something rendered into the cache
#   text\n<contents>   the head of a text file, to be set as text: code and
#                      markdown are for reading, and a picture of a paragraph
#                      220px wide would be a picture of nothing
#   (nothing)          no preview — a binary, a dead renderer, a format with
#                      nothing in it to show
#
# Exit status is not the answer, empty output is: a missing tool, a corrupt
# file and a format with no picture in it are all the same event to the box,
# which draws the same glyph for all three.
#
# Renders are kept in ~/.cache/thumbnails/x-large, the size tier a 512px long
# edge belongs to. They are not spec entries — keyed by path, mtime and size
# rather than by the md5 of a URI, and carrying no Thumb::URI — so nothing
# else will read them. clear-thumbcache.sh sweeps whatever in there has gone
# a month unread, and that sweep is the reason they are there.

set -uo pipefail

src=${1:-}
[[ -n $src && -f $src && -r $src ]] || exit 0

cache="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails/x-large"
mkdir -p "$cache" || exit 0

mime=$(file -Lb --mime-type -- "$src" 2>/dev/null) || exit 0

# An image is already the answer to the question, for every format Qt reads
# without help. The rest of image/* — tiff, raw, psd, ico — goes through
# magick like anything else.
case $mime in
    image/jpeg | image/png | image/gif | image/bmp | image/webp | image/svg+xml)
        printf 'image\n%s\n' "$src"
        exit 0
        ;;
esac

# Text is read rather than looked at, so it is handed over as itself. 4000
# bytes and 80 lines is already more than a 220px column can show; the cut is
# here so that landing on a gigabyte of log costs one read of its first page.
# Tabs are expanded because the panel is not a terminal and would draw them as
# nothing at all.
case $mime in
    text/* | application/json | application/xml | application/javascript | application/x-shellscript | application/x-desktop | application/toml | application/x-yaml | application/x-perl | application/x-php)
        printf 'text\n'
        head -c 4000 -- "$src" 2>/dev/null | head -n 80 | expand -t 4
        exit 0
        ;;
esac

# mtime and size, so a file edited in place gets a new key rather than the old
# picture. Path included because two files can be identical and still want
# separate entries — the key is "this file as it is now", not its contents.
stamp=$(stat -Lc '%Y %s' -- "$src" 2>/dev/null) || exit 0
key=$(printf '%s\n%s' "$src" "$stamp" | sha1sum | cut -d' ' -f1)
out="$cache/$key.png"

# Already drawn, by this run of the launcher or by one last week.
[[ -s $out ]] && {
    printf 'image\n%s\n' "$out"
    exit 0
}

# Rendered beside the real name and moved into place, so a reader can never
# catch a half-written PNG: the launcher hands this path to an Image, and a
# truncated file would be cached by Qt as a broken one.
#
# Named .png, because ffmpeg takes the format it is writing from the name it
# is given and a suffixless file would simply not be a picture to it.
tmp=$(mktemp "$cache/.$key.XXXXXX.png") || exit 0
trap 'rm -f "$tmp" "$tmp.png"' EXIT

# 512 on the long edge. The panel is 220 wide on a 1x screen and this is the
# only copy that gets kept, so it is sized for the scaled-up case rather than
# for today's window.
px=512

case $mime in
    image/*)
        # [0] is the first frame or page: a multi-layer psd or an ico full of
        # sizes would otherwise write one file per layer.
        timeout 10 magick "$src[0]" -auto-orient -thumbnail "${px}x${px}" -background none -flatten "png:$tmp" 2>/dev/null
        ;;
    application/pdf)
        # -singlefile drops the page number pdftoppm otherwise appends. It
        # still adds .png to whatever it is given, so what it writes is
        # "$tmp.png", and that is what gets moved back over $tmp.
        timeout 10 pdftoppm -png -singlefile -f 1 -l 1 -scale-to "$px" -- "$src" "$tmp" 2>/dev/null && mv -f "$tmp.png" "$tmp"
        ;;
    video/*)
        # Three seconds in, because the first frame of a video is so often
        # black. A clip shorter than that gives nothing back, so it is asked
        # again from the start rather than left blank.
        timeout 15 ffmpeg -v error -ss 3 -i "$src" -frames:v 1 -vf "scale=$px:-2:force_original_aspect_ratio=decrease" -y "$tmp" 2>/dev/null
        [[ -s $tmp ]] || timeout 15 ffmpeg -v error -i "$src" -frames:v 1 -vf "scale=$px:-2:force_original_aspect_ratio=decrease" -y "$tmp" 2>/dev/null
        ;;
    application/vnd.oasis.opendocument.* | application/vnd.openxmlformats-officedocument.* | application/msword | application/vnd.ms-*)
        # soffice names its output after the input and will not be told
        # otherwise, so it gets a directory to itself to write into.
        #
        # The profile is a private one, kept between runs and kept out of the
        # thumbnail cache, which is swept: a headless convert sharing the
        # normal profile attaches to a LibreOffice that happens to be open and
        # then either does nothing or drags a window in front of the launcher.
        # Building it costs about a second, which is why it is built once here
        # rather than per file.
        #
        # No "--" before the filename: soffice has no end-of-options marker and
        # treats one as a file it cannot open. Every path the launcher passes
        # is absolute, so there is no leading dash for it to misread.
        profile="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/soffice"
        work=$(mktemp -d "$cache/.soffice.XXXXXX") || exit 0
        timeout 45 soffice --headless --norestore \
            "-env:UserInstallation=file://$profile" \
            --convert-to png --outdir "$work" "$src" >/dev/null 2>&1
        page=$(find "$work" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null)
        # Full page out of soffice, cut down here: --convert-to takes no size.
        [[ -n $page ]] && timeout 10 magick "$page" -thumbnail "${px}x${px}" "png:$tmp" 2>/dev/null
        rm -rf "$work"
        ;;
esac

[[ -s $tmp ]] || exit 0
mv -f "$tmp" "$out" 2>/dev/null || exit 0
printf 'image\n%s\n' "$out"
