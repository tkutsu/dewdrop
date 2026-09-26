import QtQuick
import qs
import qs.components
import qs.services

// The thermometer's tooltip: the whole machine in three sections — the CPU and
// the memory it is working in, and then the card, which is its own machine.
// Each one is a heading carrying its headline figure, and rows of detail under
// it.
//
// While this is on screen the service polls for the parts only shown here (top
// processes, nvidia-smi); the counter is what tells it to.
Popup {
    id: root

    spacing: 9

    // A fixed width, and every figure in a mono face. The contents are replaced
    // once a second and a popup that took its width from them would breathe in
    // and out under the pointer; 302 is what the core strip divides into evenly
    // (see cores below).
    readonly property int w: 302
    // One below the rest of the popups rather than at their size: this one is
    // three sections of figures where they are a line or two, and it is the
    // only place where a whole machine has to fit under a pointer. It is a
    // step off the shared size rather than a number of its own, so it moves
    // when that does.
    readonly property int fontSize: Theme.popupTextSize - 1
    readonly property int rows: 5

    // The service only samples processes and the card while someone is
    // looking. Counted in a beat after opening rather than at once: the first
    // detail sample is the heaviest work the popup does, and landing it during
    // the slide-in stalled the slide. The pointer has to rest for half a second
    // before the popup exists at all, so a further fade's worth costs nothing.
    property bool watching: false

    Timer {
        interval: Theme.fadeMs
        running: true
        onTriggered: {
            root.watching = true;
            Sys.watchers++;
        }
    }

    Component.onDestruction: if (root.watching)
        Sys.watchers--

    function gib(kb) {
        return (kb / 1048576).toFixed(1);
    }

    function mib(mb) {
        return (mb / 1024).toFixed(1);
    }

    // Anything nvidia-smi could not answer for, and a drive with no sensor.
    function num(v, digits) {
        return isNaN(v) ? "—" : v.toFixed(digits ?? 0);
    }

    // A pair of byte counts in one unit, chosen off the larger of the two so
    // "1.0 / 1.8 TiB" does not come back as a four-figure number of gibibytes.
    function space(part, whole) {
        const tib = whole >= 1099511627776;
        const div = tib ? 1099511627776 : 1073741824;
        return `${(part / div).toFixed(1)} / ${(whole / div).toFixed(1)} ${tib ? "TiB" : "GiB"}`;
    }

    function rate(bytes) {
        return (bytes / 1048576).toFixed(1);
    }

    // --- the three shapes every section is built from ------------------------
    component Head: Item {
        id: head

        property string glyph
        property string title
        property string value

        width: root.w
        implicitHeight: name.implicitHeight

        Glyph {
            id: mark
            text: head.glyph
            fontSize: root.fontSize + 2
            implicitHeight: head.height
            opacity: 0.8
        }

        PopupText {
            id: name
            x: mark.implicitWidth + 7
            text: head.title
            font.pixelSize: root.fontSize
            font.weight: Font.DemiBold
            // Whatever the figure on the right does not need, less a gap: the
            // left hand side is the part worth cutting, and the only one of the
            // two that can be.
            width: root.w - x - figure.implicitWidth - 10
            elide: Text.ElideRight
        }

        PopupText {
            id: figure
            anchors.right: parent.right
            anchors.baseline: name.baseline
            text: head.value
            font.pixelSize: root.fontSize
            font.weight: Font.DemiBold
        }
    }

    component Line: Item {
        id: line

        property string label
        property string value

        width: root.w
        implicitHeight: key.implicitHeight

        PopupText {
            id: key
            text: line.label
            font.pixelSize: root.fontSize
            opacity: 0.55
            // As above: the figure is measured and the label takes the rest.
            width: root.w - figure.implicitWidth - 10
            elide: Text.ElideRight
        }

        PopupText {
            id: figure
            anchors.right: parent.right
            anchors.baseline: key.baseline
            text: line.value
            font.pixelSize: root.fontSize
            opacity: 0.85
        }
    }

    // How full something is, for the two numbers that are a fraction of a fixed
    // total. The track is the pill outline's idea: enough to show what the bar
    // is a part of, quiet enough that an empty one is not a bright line.
    component Meter: Rectangle {
        id: meter

        property real value: 0

        width: root.w
        height: 3
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            width: Math.round(meter.width * Math.max(0, Math.min(1, meter.value)))
            height: meter.height
            color: Theme.fg
        }
    }

    // Always `rows` rows, filled or not: the list is rebuilt every second and a
    // popup that grew and shrank a row at a time as processes came and went
    // would move the things under the pointer while it was being read.
    component Procs: Column {
        id: procs

        property var model: []
        property bool byCpu: false

        spacing: 1

        Repeater {
            model: root.rows

            delegate: Line {
                required property int index

                readonly property var proc: procs.model[index] ?? null

                // A bullet in front of the name, because these rows are the
                // one part of the popup that is not a measurement: every other
                // line pairs a thing with its reading, and these pair a name
                // with whatever that program happens to be holding at the
                // moment. Set the same way round as the rest of the section so
                // the names still line up under each other.
                //
                // A dozen web content processes are one entry with a count on
                // it, so the name has to say how many it stands for.
                label: proc ? "• " + (proc.n > 1 ? `${proc.name} ×${proc.n}` : proc.name) : ""
                // A decimal under ten per cent: the bottom of this list is
                // made of small numbers, and rounded to whole ones they are all
                // the same number in a different order.
                value: !proc ? "" : procs.byCpu ? `${root.num(proc.cpu * 100, proc.cpu < 0.1 ? 1 : 0)} %` : `${root.gib(proc.rss / 1024)} GiB`
                opacity: 0.9
            }
        }
    }

    // --- CPU -----------------------------------------------------------------
    Column {
        spacing: 3

        // Temperatures first and the load beside them, the same way round as
        // the card's heading below. Which sensor is which is in the order, not
        // in a label: the package reading leads, the die follows.
        Head {
            glyph: Theme.glyph.cpu
            title: Sys.cpuModel
            value: `${Sys.cpuTemps.map(t => Math.round(t.value) + "°").join(" / ")}   ${Math.round(Sys.cpuUse * 100)} %`
        }

        // One bar per thread. The load a machine is under is not one number —
        // a single thread pinned and every thread pinned are the same 6 % and
        // 100 % apart in what they mean — and sixteen bars say which it is
        // without a legend.
        Row {
            id: cores

            readonly property int count: Math.max(1, Sys.coreUse.length)
            readonly property int gap: 2
            // Integer widths, so sixteen bars are sixteen crisp bars rather
            // than a grey smear on half pixels.
            readonly property int barWidth: Math.floor((root.w - (count - 1) * gap) / count)

            spacing: gap
            visible: Sys.coreUse.length > 0
            bottomPadding: 2
            topPadding: 1

            Repeater {
                model: Sys.coreUse

                delegate: Rectangle {
                    required property real modelData

                    width: cores.barWidth
                    height: 11
                    color: Qt.rgba(1, 1, 1, 0.12)

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.round(parent.height * Math.max(0, Math.min(1, parent.modelData)))
                        color: Theme.fg
                        opacity: 0.85
                    }
                }
            }
        }

        // Every sensor the CPU's own chip publishes, which on this one is the
        // package reading the badge carries and the die under it. The badge's
        // own sensor is named first; the rest are context for it.
        Line {
            label: "clock"
            value: `${Sys.cpuMhz} MHz`
        }

        // The case fans, in the order the board lists them. The card's own fan
        // is in its own section and in per cent, because that is the only way
        // nvidia-smi will say it.
        Line {
            visible: Sys.fans.length > 0
            label: "fans"
            value: `${Sys.fans.map(f => f.rpm).join(" / ")} rpm`
        }

        Item {
            width: 1
            height: 2
        }

        Procs {
            model: Sys.topCpu
            byCpu: true
        }
    }

    // --- memory --------------------------------------------------------------
    Column {
        spacing: 3

        Head {
            glyph: Theme.glyph.ram
            title: "RAM"
            value: `${root.gib(Sys.memUsed)} / ${root.gib(Sys.memTotal)} GiB`
        }

        Meter {
            value: Sys.memTotal > 0 ? Sys.memUsed / Sys.memTotal : 0
        }

        Line {
            label: `cache ${root.gib(Sys.memCache)} GiB`
            value: Sys.swapTotal > 0 ? `swap ${root.gib(Sys.swapUsed)} / ${root.gib(Sys.swapTotal)}` : ""
        }

        Item {
            width: 1
            height: 2
        }

        Procs {
            model: Sys.topMem
        }
    }

    // --- GPU -----------------------------------------------------------------
    Column {
        id: gpuSection

        spacing: 3
        visible: Sys.gpu !== null

        // Stood in for while it is null so the bindings below have something to
        // read; the section is not on screen until it is real.
        readonly property var gpu: Sys.gpu ?? ({})

        Head {
            glyph: Theme.glyph.gpu
            title: gpuSection.gpu.name ?? ""
            value: `${root.num(gpuSection.gpu.temp)}°   ${root.num(gpuSection.gpu.util)} %`
        }

        // A meter under the heading, the way the other two sections have one:
        // the CPU's is its cores and RAM's is how much of it is gone. The
        // card's is its clock against the ceiling it is allowed — what a GPU
        // is doing is how hard it is being run, and its vram is mostly a
        // number that was claimed once and stays claimed. The figure the bar
        // is drawn from leads the lines under it, as in the other two.
        Meter {
            value: gpuSection.gpu.clockMax > 0 ? gpuSection.gpu.clock / gpuSection.gpu.clockMax : 0
        }

        Line {
            label: "clock"
            value: `${root.num(gpuSection.gpu.clock)} / ${root.num(gpuSection.gpu.clockMax)} MHz`
        }

        Line {
            label: "memory clock"
            value: `${root.num(gpuSection.gpu.memClock)} MHz`
        }

        Line {
            label: "vram"
            value: `${root.mib(gpuSection.gpu.memUsed)} / ${root.mib(gpuSection.gpu.memTotal)} GiB`
        }

        Line {
            label: `fan ${root.num(gpuSection.gpu.fan)} %`
            value: `${root.num(gpuSection.gpu.power, 1)} / ${root.num(gpuSection.gpu.powerMax)} W`
        }
    }

    // --- the disks -----------------------------------------------------------
    // One block per drive rather than one section for all of them: a disk is a
    // piece of hardware with its own temperature and its own load, the same way
    // the card above is, and two drives in one list would need a column of
    // names to say which figure belonged to which.
    //
    // The heading carries what the other headings carry — how warm it is and
    // how hard it is being worked — and the meter below is the one thing a disk
    // has that nothing else here does: how much of it is already spent. That is
    // the figure worth a bar, because it is the one that only ever goes one way.
    Repeater {
        model: Sys.drives

        delegate: Column {
            id: drive

            required property var modelData

            spacing: 3

            Head {
                glyph: Theme.glyph.disk
                title: drive.modelData.model
                value: `${root.num(drive.modelData.temp)}°   ${Math.round(drive.modelData.util * 100)} %`
            }

            // A disk with nothing mounted off it — an empty one, or one whose
            // filesystems this user cannot see — has a size and no answer about
            // what is on it. Its heading and its traffic are still worth having.
            Meter {
                visible: drive.modelData.total > 0
                value: drive.modelData.total > 0 ? (drive.modelData.total - drive.modelData.free) / drive.modelData.total : 0
            }

            Line {
                visible: drive.modelData.total > 0
                label: "free"
                value: root.space(drive.modelData.free, drive.modelData.total)
            }

            Line {
                label: "read / write"
                value: `${root.rate(drive.modelData.read)} / ${root.rate(drive.modelData.write)} MiB/s`
            }
        }
    }
}
