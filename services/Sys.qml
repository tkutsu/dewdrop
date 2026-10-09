pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// CPU, GPU and memory, behind the bar's thermometer.
//
// Three tiers of asking. The badge only ever shows a temperature, and that is
// one sysfs file read in place, no process at all. The CPU, memory and fan
// section runs while the popup is up, and every process's CPU time and the
// disks are only worth paying for while something is on screen to read them,
// so that half runs while `watchers` is up and stops when the popup closes.
// nvidia-smi is one long-lived process for as long as anything reads the
// card while the popup is open.
Singleton {
    id: root

    // --- what the bar shows --------------------------------------------------
    property real cpuTemp: 0            // °C — the badge's number
    property string cpuModel: ""
    property var cpuTemps: []           // [{ label, value }] from the CPU's own chip
    property real cpuUse: 0             // 0..1, every thread together
    property var coreUse: []            // 0..1 per thread
    property int cpuMhz: 0

    // Memory is carried in kB, the unit /proc/meminfo reports it in.
    property real memUsed: 0
    property real memTotal: 0
    property real memCache: 0
    property real swapUsed: 0
    property real swapTotal: 0

    // [{ label, rpm }] — every fan the machine will own up to, the GPU's own
    // excepted (that one comes from nvidia-smi, and in per cent rather than
    // revolutions). Empty on a machine whose fans no driver exposes, which is
    // most Asus boards until nct6775 is loaded.
    property var fans: []
    property var _fansSeen: ({})

    // { name, temp, util, clock, clockMax, memClock, memUsed, memTotal, power,
    // powerMax, fan } in MiB, MHz, W and per cent. Null until nvidia-smi
    // answers, and back to null if it cannot — no GPU section rather than a
    // section of dashes.
    property var gpu: null

    // [{ name, model, temp, total, free, read, write, util }] — one per physical
    // disk, the one the system is on first. Bytes, °C, bytes/second and 0..1.
    // `temp` is NaN on a drive whose controller publishes none, and `total` is
    // zero for a disk with nothing mounted off it.
    property var drives: []

    // [{ name, n, cpu, rss }], a program and its workers added together under
    // the program's name: a browser is a dozen processes and fills a seven row
    // list on its own otherwise, under a name ("Isolated Web Co") that is not
    // even the one on the window. `cpu` is in cores, the way top counts it —
    // 1.5 is a thread and a half. `rss` is summed resident memory, so pages a
    // program shares with its own workers are in there more than once.
    property var topCpu: []
    property var topMem: []

    // A failed probe pauses sampling; opening the popup, or 30 s with it
    // open, tries again.
    property bool gpuPresent: true

    // Raised by whatever is showing the detail (components/SysPopup.qml) for as
    // long as it is on screen, which is what gates the expensive poll.
    property int watchers: 0

    readonly property real temp: cpuTemp

    // The scale the tube is read against: an empty one at the bottom of it, a
    // full one at the top, and past the top the column changes colour.
    //
    // One scale for the chip and the card both, rather than one each. The two
    // do not run equally warm — Zen 4 reports Tctl with an offset baked in and
    // boosts into the 80s by design, where an Ada GPU is close to throttling in
    // the low 80s — but two scales mean the same height on the bar stands for
    // two different things depending on which one is showing, and the number
    // that settles it is in the popup anyway.
    //
    // The bottom is not zero: nothing here is ever cold, and a column that
    // spends its first third on temperatures the machine never sees is a third
    // of the tube wasted.
    readonly property real coolTemp: 35
    readonly property real hotTemp: 85
    readonly property real gauge: (temp - coolTemp) / (hotTemp - coolTemp)

    // How far up the tube the mercury stands: one step per row of the ball in
    // the bulb (three), then one per pixel of bore at bar size (seven, see
    // modules/Sys.qml) — which is as fine as the reading can be told. Empty at the bottom of the scale,
    // full at the top, and hot is the top and past it, where the mercury
    // changes colour.
    //
    // Both step with hysteresis, because Tctl swings ten degrees between one
    // sample and the next and a bare threshold would have the column twitching
    // up and down a pixel all afternoon: going up takes reaching the step,
    // coming back down takes a tenth of the scale clear of it.
    readonly property int steps: 10
    property int level: 0
    property bool hot: false

    onGaugeChanged: {
        let l = level;
        while (l < steps && gauge >= (l + 1) / steps)
            l++;
        while (l > 0 && gauge < l / steps - 0.1)
            l--;
        level = l;

        if (gauge >= 1)
            hot = true;
        else if (gauge < 0.9)
            hot = false;
    }


    // The label the CPU's temperature is read off, in order of preference:
    // AMD's Tctl, Intel's package, then any die sensor. Whatever the chip calls
    // its hottest reading is the fallback, so an unfamiliar one still shows a
    // number rather than nothing.
    readonly property var tempPreference: ["Tctl", "Tdie", "Package id 0", "CPU"]

    // --- the cheap poll ------------------------------------------------------
    // What the popup reads about the CPU, memory and fans, in sections rather
    // than one file per Process: four reads is four forks, and this runs every
    // two seconds while the popup is up. While it is not, only the badge's one
    // temperature is wanted, and that is read without a shell at all — see
    // tempFile below.
    //
    // Every sysfs value is taken with `read`, which is a shell builtin, rather
    // than with `$(cat ...)`, which is a fork each. The chip names alone were
    // one per hwmon directory whether or not the chip turned out to be the
    // CPU's, and the whole section measured six times what it costs now —
    // 8.6ms against 1.3ms on this machine. The greps are left as they are:
    // three processes for three files, where the shell equivalent would be
    // slower and unreadable.
    //
    // hwmon numbers are handed out in probe order and shuffle between boots, so
    // the CPU's chip is found by name every time instead of being remembered as
    // a path. Only the CPU's own chips are asked — the board, the NVMe and the
    // wifi card all publish temperatures too, and none of them are this module.
    // Label, reading and path per sensor; the path is what the badge's own
    // reader below is resolved from.
    readonly property string tempLoop: "for d in /sys/class/hwmon/*; do read -r n < \"$d/name\"; case $n in k10temp|zenpower*|coretemp|cpu_thermal) ;; *) continue;; esac; for f in \"$d\"/temp*_input; do l=\"${f%_input}_label\"; [ -r \"$l\" ] || continue; read -r lab < \"$l\"; read -r val < \"$f\"; printf '%s\\t%s\\t%s\\n' \"$lab\" \"$val\" \"$f\"; done; done"

    readonly property string lightScript: ["echo :cpu", "grep ^cpu /proc/stat", "echo :freq",
        // Measured, not requested: on AMD this line comes from aperf/mperf,
        // where cpufreq's scaling_cur_freq is the governor's last ask.
        "grep '^cpu MHz' /proc/cpuinfo", "echo :temp", root.tempLoop, "echo :mem", "grep -E '^(MemTotal|MemAvailable|Cached|SReclaimable|Shmem|SwapTotal|SwapFree):' /proc/meminfo", "echo :fan",
        // Every chip this time, not just the CPU's: the fans hang off whatever
        // the board's Super-I/O is, which is a different chip from the one that
        // reports the temperatures. Chip and file name first, so a fan with no
        // label of its own still has something to be called; the label goes
        // last because it is the field that can hold spaces.
        "for f in /sys/class/hwmon/*/fan*_input; do [ -r \"$f\" ] || continue; l=\"${f%_input}_label\"; d=\"${f%/*}\"; b=\"${f##*/}\"; read -r n < \"$d/name\"; read -r rpm < \"$f\"; lab=\"\"; [ -r \"$l\" ] && read -r lab < \"$l\"; printf '%s\\t%s\\t%s\\t%s\\n' \"$n\" \"${b%_input}\" \"$rpm\" \"$lab\"; done"].join("\n")

    // Every process's parent, accumulated CPU time and resident size in one
    // pass, which is the only way to get a *current* per-process load: ps and
    // /proc's own percentages are averages over a process's whole life, so a
    // browser that was busy an hour ago outranks the compile running now.
    //
    // /proc/<pid>/stat cannot simply be split on spaces — the command name sits
    // in brackets and may contain both spaces and brackets — so the name is cut
    // out between the first "(" and the last ")", and the numbered fields are
    // counted from what is left. ppid is field 4, utime + stime is 14 + 15, and
    // rss is 24.
    //
    // cat reads the files rather than awk: a process can exit between the
    // glob and the open, and gawk takes a file it cannot open as fatal and
    // stops there, dropping every pid above it from the sample. That was about
    // one sample in a hundred, and it emptied the lists. cat skips the file.
    readonly property string procScript: "cat /proc/[0-9]*/stat 2>/dev/null | awk '{n=$0;sub(/.*\\) /,\"\",n);split(n,f,\" \");c=$0;sub(/^[0-9]+ \\(/,\"\",c);sub(/\\)[^)]*$/,\"\",c);print $1,f[2],f[12]+f[13],f[22],c}'"

    // What each process is running, for the roll-up in rollUp. find rather
    // than a readlink per process: one command for all of them, and %l comes
    // back empty for the processes this user is not allowed to look inside,
    // which is exactly the answer that stops them being rolled anywhere.
    //
    // A binary does not change under a running pid, so this is asked once per
    // pid and remembered: the first sample of a popup looks at every process,
    // the ones after it only at whatever was started since.
    function exeScript(pids) {
        const where = pids.length ? pids.map(p => "/proc/" + p).join(" ") + " -maxdepth 1" : "/proc -maxdepth 2";
        return "find " + where + " -name exe -printf '%h\\t%l\\n' 2>/dev/null";
    }

    // The disks, which are three unrelated questions about the same hardware:
    // how warm it is, how hard it is being worked, and how much of it is left.
    //
    // The first two come out of sysfs with no forks at all. A block device's
    // `device` link is the controller, and the controller is where the driver
    // hangs its hwmon — so /sys/block/<d>/device/hwmon*/temp1_input is the
    // drive's own temperature without having to match a hwmon number against a
    // disk, which is the dance the CPU's sensors need and which nothing here
    // would survive a reboot doing (hwmon numbers are handed out in probe
    // order). temp1 is the composite reading on NVMe and the only one on SATA.
    //
    // /sys/block/<d>/stat is /proc/diskstats' line for that disk without the
    // name on the front: sectors read is field 3, sectors written field 7, and
    // field 10 is milliseconds spent with anything in flight — which over a
    // known interval is the drive's own utilisation, the same figure as the
    // card's and the CPU's beside it.
    readonly property string diskScript: "for d in /sys/block/*; do b=${d##*/}; case $b in loop*|ram*|zram*|dm-*|md*|sr*) continue;; esac; [ -r \"$d/device/model\" ] || continue; read -r m < \"$d/device/model\"; read -r st < \"$d/stat\"; t=; for h in \"$d\"/device/hwmon*/temp1_input; do [ -r \"$h\" ] && read -r t < \"$h\" && break; done; printf '%s\\t%s\\t%s\\t%s\\n' \"$b\" \"$t\" \"$st\" \"$m\"; done"

    // Free space is the one part that cannot come from sysfs: a disk does not
    // know what has been written on it, only the filesystems do, and df is the
    // thing that asks all of them at once. On its own, slower clock: a figure
    // that moves by the gigabyte a day does not need asking every second and a
    // half alongside the throughput counters.
    readonly property string dfScript: "df -B1 --output=source,target,size,avail -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x ramfs 2>/dev/null"

    // The tick rate of the utime/stime counters (getconf CLK_TCK), and the unit
    // rss is counted in.
    readonly property int hz: 100
    readonly property int pageSize: 4096

    property var _cpuPrev: null
    property var _corePrev: []
    property var _procPrev: ({})
    property real _procAt: 0
    property var _drivePrev: ({})
    property real _driveAt: 0
    // The last sysfs pass over the disks and the last df, kept apart because
    // they arrive on different clocks and `drives` is put together from both.
    property var _disks: []
    property var _df: []
    // pid → binary, "" for one this user may not read. See exeScript.
    property var _exe: ({})
    // The last process sample, waiting on the binaries it has not seen before.
    property var _procs: []

    // The reading the badge carries, chosen in the order tempPreference is
    // written rather than the order the chip happens to publish its sensors
    // in. Asking the readings which of them is preferred — `find` over the
    // sensors — answers with whichever came first on a chip that publishes
    // more than one of them, which is not what the list is for.
    function pickTemp(temps) {
        if (!temps.length)
            return null;
        for (const label of root.tempPreference) {
            const hit = temps.find(t => t.label === label);
            if (hit)
                return hit;
        }
        // Whatever the chip calls its hottest reading, so an unfamiliar one
        // still shows a number rather than nothing.
        return temps.reduce((a, b) => b.value > a.value ? b : a);
    }

    // label \t millidegrees \t path, one per sensor — the shape tempLoop
    // prints.
    function readTemps(text) {
        const temps = [];
        for (const line of text.split("\n")) {
            if (line === "")
                continue;
            const f = line.split("\t");
            temps.push({
                label: f[0],
                value: Number(f[1]) / 1000,
                path: f[2]
            });
        }
        return temps;
    }

    function parseLight(text) {
        const temps = [];
        const fans = [];
        const cores = [];
        const mem = {};
        let cpu = null;
        let freqSum = 0;
        let freqN = 0;
        let mode = "";

        for (const line of text.split("\n")) {
            if (line.startsWith(":")) {
                mode = line;
                continue;
            }
            if (line === "")
                continue;

            if (mode === ":cpu") {
                const f = line.split(/ +/);
                // user through steal: guest and guest_nice, the last two, are
                // already counted inside user and nice.
                const n = f.slice(1, 9).map(Number);
                // idle + iowait is the part of the interval the thread had
                // nothing to do; everything else it was carrying something.
                const sample = {
                    total: n.reduce((a, b) => a + b, 0),
                    idle: n[3] + n[4]
                };
                if (f[0] === "cpu")
                    cpu = sample;     // the sum of the others, and always first
                else
                    cores.push(sample);
            } else if (mode === ":freq") {
                freqSum += parseFloat(line.split(":")[1]);
                freqN++;
            } else if (mode === ":temp") {
                temps.push(line);
            } else if (mode === ":fan") {
                const f = line.split("\t");
                fans.push({
                    label: f[3] !== "" ? f[3] : `${f[0]} ${f[1]}`,
                    rpm: Number(f[2])
                });
            } else if (mode === ":mem") {
                const f = line.split(/:? +/);
                mem[f[0]] = Number(f[1]);
            }
        }

        function busy(now, prev) {
            const dt = now.total - prev.total;
            return dt > 0 ? Math.max(0, Math.min(1, 1 - (now.idle - prev.idle) / dt)) : 0;
        }

        if (cpu && root._cpuPrev)
            root.cpuUse = busy(cpu, root._cpuPrev);
        if (root._corePrev.length === cores.length)
            root.coreUse = cores.map((c, i) => busy(c, root._corePrev[i]));
        root._cpuPrev = cpu;
        root._corePrev = cores;

        if (freqN > 0)
            root.cpuMhz = Math.round(freqSum / freqN);

        root.cpuTemps = root.readTemps(temps.join("\n"));
        root.cpuTemp = root.pickTemp(root.cpuTemps)?.value ?? 0;

        // A board publishes a header whether or not anything is plugged into
        // it, so five of these are usually a steady zero. A fan counts as real
        // once it has been seen turning — and from then on a zero is worth
        // showing, because a fan that has stopped is news.
        for (const f of fans)
            if (f.rpm > 0)
                root._fansSeen[f.label] = true;
        root.fans = fans.filter(f => root._fansSeen[f.label] === true);

        // What the kernel will hand out without swapping, which is not
        // MemFree — most of what is free is cache it can drop.
        root.memTotal = mem.MemTotal ?? 0;
        root.memUsed = root.memTotal - (mem.MemAvailable ?? 0);
        // Page cache minus the part that is shared memory rather than a copy of
        // something on disk, the same sum htop's cache bar shows.
        root.memCache = (mem.Cached ?? 0) + (mem.SReclaimable ?? 0) - (mem.Shmem ?? 0);
        root.swapTotal = mem.SwapTotal ?? 0;
        root.swapUsed = root.swapTotal - (mem.SwapFree ?? 0);
    }

    // Which disk a filesystem is on. A partition's name is its disk's with a
    // suffix — "p2" where the disk's own name ends in a digit, bare digits
    // otherwise — and a filesystem mounted on the whole disk has no suffix at
    // all, which is why the disks found above get asked first.
    function diskOf(part, disks) {
        if (disks[part])
            return part;
        const m = part.match(/^(.*\d)p\d+$/);
        return m ? m[1] : part.replace(/\d+$/, "");
    }

    function parseDisks(text) {
        const now = Date.now();
        const dt = (now - root._driveAt) / 1000;
        const prev = root._drivePrev;
        const next = {};
        const list = [];

        for (const line of text.split("\n")) {
            if (line === "")
                continue;
            const f = line.split("\t");
            const st = f[2].split(/ +/).map(Number);
            const d = {
                name: f[0],
                model: f[3].trim(),
                // No sensor reads as no number rather than as zero: a drive
                // at 0 °C is a reading, and this is the absence of one.
                temp: f[1] === "" ? NaN : Number(f[1]) / 1000,
                _read: st[2],
                _write: st[6],
                _io: st[9]
            };
            next[d.name] = {
                read: d._read,
                write: d._write,
                io: d._io
            };
            const p = prev[d.name];
            // Counters, so the first sample of a popup has nothing to subtract
            // and reads as idle until the second one lands. Clamped low as
            // well as high: a disk that was hot-plugged between two samples
            // has counters that went backwards.
            const ok = p && dt > 0;
            d.read = ok ? Math.max(0, (d._read - p.read) * 512 / dt) : 0;
            d.write = ok ? Math.max(0, (d._write - p.write) * 512 / dt) : 0;
            d.util = ok ? Math.max(0, Math.min(1, (d._io - p.io) / 1000 / dt)) : 0;
            list.push(d);
        }

        root._drivePrev = next;
        root._driveAt = now;
        root._disks = list;
        root.placeDrives();
    }

    // "/dev/nvme1n1p2 /home 1999324123136 1121467109376", one per filesystem.
    // The mount point in the middle is the one field that can hold spaces, so
    // both ends are counted from their own end.
    function parseDf(text) {
        const rows = [];
        for (const line of text.split("\n")) {
            if (!line.startsWith("/dev/"))
                continue;
            const f = line.split(/ +/);
            rows.push({
                part: f[0].slice(5),
                mount: f[1],
                size: Number(f[f.length - 2]),
                avail: Number(f[f.length - 1])
            });
        }
        root._df = rows;
        root.placeDrives();
    }

    // The sysfs pass and the df joined into `drives`, whichever of the two
    // arrived last. Fresh objects each time: the space is summed onto the
    // disk, and summing onto the same object twice would double it.
    function placeDrives() {
        const byName = {};
        const seen = {};
        const list = root._disks.map(d => {
            const copy = Object.assign({}, d, {
                total: 0,
                free: 0
            });
            byName[copy.name] = copy;
            return copy;
        });
        let rootDisk = "";

        for (const fs of root._df) {
            if (fs.mount === "/")
                rootDisk = root.diskOf(fs.part, byName);
            // One filesystem however many places it is mounted: btrfs
            // subvolumes are one device mounted once per subvolume, and
            // every one of them reports the whole filesystem's free space.
            if (seen[fs.part])
                continue;
            seen[fs.part] = true;
            const disk = byName[root.diskOf(fs.part, byName)];
            if (!disk)
                continue;
            disk.total += fs.size;
            disk.free += fs.avail;
        }

        // The disk the system is on leads; the rest in the order the kernel
        // named them. A machine with four of them should not have to be read
        // through to find the one that matters.
        list.sort((a, b) => (b.name === rootDisk) - (a.name === rootDisk) || (a.name < b.name ? -1 : 1));
        root.drives = list;
    }

    function parseProcs(text) {
        const procs = [];
        for (const line of text.split("\n")) {
            if (line === "")
                continue;
            const f = line.split(" ");
            procs.push({
                pid: f[0],
                ppid: f[1],
                used: Number(f[2]),
                rss: Number(f[3]) * root.pageSize,
                // A name can hold spaces (kernel threads, and anything that
                // renamed itself), so it is everything after the numbers.
                name: f.slice(4).join(" ")
            });
        }
        root._procs = procs;

        // Forget the pids that have gone, so a number the kernel hands out
        // again is looked up afresh rather than filed under its last owner.
        const exe = {};
        const missing = [];
        for (const p of procs) {
            if (root._exe[p.pid] !== undefined)
                exe[p.pid] = root._exe[p.pid];
            else
                missing.push(p.pid);
        }
        root._exe = exe;

        if (missing.length === 0) {
            root.rollUp();
            return;
        }
        // Everything, or just the newcomers: a full /proc walk is one find
        // either way, and shorter to type than four hundred paths.
        exeProbe.command = ["sh", "-c", root.exeScript(Object.keys(exe).length === 0 ? [] : missing)];
        exeProbe.running = true;
    }

    // "/proc/1234\t/usr/lib/firefox/firefox", one per process find could
    // reach. Unreadable ones come back with nothing after the tab and are
    // remembered as such, so they are not asked about again every sample.
    function parseExe(text) {
        for (const line of text.split("\n")) {
            if (line === "")
                continue;
            const f = line.split("\t");
            root._exe[f[0].substring(6)] = f[1] ?? "";   // past "/proc/"
        }
        root.rollUp();
    }

    function rollUp() {
        const now = Date.now();
        const dt = (now - root._procAt) / 1000;
        const prev = root._procPrev;
        const exe = root._exe;
        const jiffies = {};
        const byName = {};
        const byPid = {};
        const procs = root._procs;
        for (const p of procs)
            byPid[p.pid] = p;

        // Which process a process's work belongs to: climb to the furthest
        // ancestor running the same binary, and stop there.
        //
        // That is what turns eleven rows of "Isolated Web Co" into one row of
        // firefox — they are all the same program, forked — without the thing
        // that goes wrong when you simply climb to the parent and keep going:
        // everything is descended from systemd, and everything started from a
        // terminal is descended from the terminal, so a compile would file
        // itself under kitty and a browser under systemd. A process whose
        // binary cannot be read (anything not this user's) is nobody's worker
        // and stays its own row.
        function owner(proc) {
            let cur = proc;
            // Bounded rather than trusted: a corrupt chain should cost a wrong
            // label, not the bar.
            for (let i = 0; i < 16; i++) {
                const parent = byPid[cur.ppid];
                if (!parent || !exe[cur.pid] || exe[parent.pid] !== exe[cur.pid])
                    break;
                cur = parent;
            }
            return cur;
        }

        for (const p of procs) {
            jiffies[p.pid] = p.used;
            const name = owner(p).name;
            const g = byName[name] ?? (byName[name] = {
                name: name,
                n: 0,
                cpu: 0,
                rss: 0
            });
            g.n++;
            g.rss += p.rss;
            // A process that was not in the last sample has no delta to take,
            // only a lifetime total — which is the number this whole pass
            // exists to avoid. It counts as idle until it has been seen twice.
            if (dt > 0 && prev[p.pid] !== undefined)
                g.cpu += (p.used - prev[p.pid]) / root.hz / dt;
        }

        root._procPrev = jiffies;
        root._procAt = now;

        const groups = Object.values(byName);
        // Half a per cent of one thread. High enough to keep the list off the
        // hundreds of processes that did nothing at all in the last second, low
        // enough that an idle machine still fills its seven rows rather than
        // leaving four of them as a hole above the next section.
        root.topCpu = groups.filter(g => g.cpu >= 0.005).sort((a, b) => b.cpu - a.cpu).slice(0, 7);
        root.topMem = groups.filter(g => g.rss > 0).sort((a, b) => b.rss - a.rss).slice(0, 7);
    }

    // The chip's own name for itself, read once — it is not going to change,
    // and the marketing in it is not worth a heading's width: "AMD Ryzen 7 7700
    // 8-Core Processor" is the same chip as "Ryzen 7 7700", and an Intel one
    // arrives with two (R)s and a clock speed attached.
    Process {
        id: model
        running: true
        command: ["sh", "-c", "grep -m1 '^model name' /proc/cpuinfo"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.cpuModel = text.split(":").slice(1).join(":").replace(/\((R|TM|r|tm)\)/g, "").replace(/^\s*(AMD|Intel)\s+/, "").replace(/\s+\d+-Core Processor\s*$/, "").replace(/\s+CPU\s*@.*$/, "").replace(/\s+/g, " ").trim();
            }
        }
    }

    // --- the badge alone -----------------------------------------------------
    // With nothing watching, the one reading wanted is the badge's, and that
    // is one sysfs file. Which file is settled once — the same search the
    // popup's poll makes, run for its path rather than its value — and from
    // then on the tick is a read of it, no shell and no grep, all day.
    // Settled again if the read ever fails, which is what a chip going away
    // (a module unloaded, a suspend the driver did not survive) looks like.
    property string tempPath: ""
    property bool tempLooked: false

    Process {
        id: tempFind
        command: ["sh", "-c", root.tempLoop]

        stdout: StdioCollector {
            onStreamFinished: {
                root.tempLooked = true;
                const temps = root.readTemps(text);
                root.tempPath = root.pickTemp(temps)?.path ?? "";
                root.cpuTemp = root.pickTemp(temps)?.value ?? 0;
            }
        }
    }

    FileView {
        id: tempFile
        path: root.tempPath
        printErrors: false

        onLoaded: root.cpuTemp = Number(text()) / 1000
        onLoadFailed: {
            root.tempPath = "";
            root.tempLooked = false;
        }
    }

    Process {
        id: light
        command: ["sh", "-c", root.lightScript]
        stdout: StdioCollector {
            onStreamFinished: root.parseLight(text)
        }
    }

    Process {
        id: procs
        command: ["sh", "-c", root.procScript]
        stdout: StdioCollector {
            onStreamFinished: root.parseProcs(text)
        }
    }

    Process {
        id: exeProbe
        stdout: StdioCollector {
            onStreamFinished: root.parseExe(text)
        }
    }

    Process {
        id: disks
        command: ["sh", "-c", root.diskScript]
        stdout: StdioCollector {
            onStreamFinished: root.parseDisks(text)
        }
    }

    Process {
        id: df
        command: ["sh", "-c", root.dfScript]
        stdout: StdioCollector {
            onStreamFinished: root.parseDf(text)
        }
    }

    // Stream GPU readings while the popup is open; one process samples card 0.
    readonly property bool gpuWanted: root.gpuPresent && root.watchers > 0

    Timer {
        interval: 30000
        running: root.watchers > 0 && !root.gpuPresent
        onTriggered: root.gpuPresent = true
    }

    Process {
        id: gpuPoll
        running: root.gpuWanted
        command: ["nvidia-smi", "-i", "0", "--query-gpu=name,temperature.gpu,utilization.gpu,clocks.current.graphics,clocks.max.graphics,clocks.current.memory,memory.used,memory.total,power.draw,power.limit,fan.speed", "--format=csv,noheader,nounits", "-lms", "2000"]

        stdout: SplitParser {
            onRead: line => root.parseGpu(line)
        }

        // No driver, no card, or a card that cannot be talked to: pause sampling.
        // Only while it was wanted — being stopped from here ends it the same
        // way, and that is not the card's fault.
        onExited: function (exitCode) {
            if (exitCode !== 0 && root.gpuWanted) {
                root.gpu = null;
                root.gpuPresent = false;
            }
        }
    }

    function parseGpu(line) {
        const f = line.split(",").map(s => s.trim());
        if (f.length < 11)
            return;
        const n = i => Number(f[i]);   // "[N/A]" becomes NaN, and reads as "—"
        root.gpu = {
            // "NVIDIA GeForce RTX 4070 SUPER" is a heading and a half.
            name: f[0].replace(/^NVIDIA\s+/, ""),
            temp: n(1),
            util: n(2),
            clock: n(3),
            clockMax: n(4),
            memClock: n(5),
            memUsed: n(6),
            memTotal: n(7),
            power: n(8),
            powerMax: n(9),
            fan: n(10)
        };
    }

    function sample() {
        // The whole section only while the popup is up to read it, or on a
        // machine whose chip the path search did not recognise, where the
        // shell's wider net is the only reading there is.
        if (root.watchers > 0 || (root.tempLooked && root.tempPath === "")) {
            if (!light.running)
                light.running = true;
        } else if (root.tempPath !== "") {
            tempFile.reload();
        } else if (!tempFind.running) {
            tempFind.running = true;
        }
    }

    function sampleDetail() {
        if (!procs.running)
            procs.running = true;
        if (!disks.running)
            disks.running = true;
    }

    // Every 2s while the popup is up, 5s otherwise. The badge is a ten-step
    // tube with hysteresis, so a temperature read every 2s all day bought
    // nothing.
    Timer {
        interval: root.watchers > 0 ? 2000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    // Started by the first watcher, which is when the first detail sample
    // runs — the popup counts itself in only once its reveal has finished, so
    // that this does not land in the middle of the slide.
    Timer {
        interval: 1500
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sampleDetail()
    }

    Timer {
        interval: 30000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!df.running)
            df.running = true
    }

    // A popup opening hours after the last one closed has counters from
    // hours ago to subtract, and a rate over that gap is an average of the
    // afternoon, not the load now. Dropped, so the first sample reads idle
    // and the second is honest — the same as a first popup of the session.
    // The cheap half is asked for at once rather than at its next tick.
    property bool watched: false

    onWatchersChanged: {
        const watching = watchers > 0;
        if (watching === root.watched)
            return;
        root.watched = watching;
        if (!watching)
            return;
        root.gpuPresent = true;
        root._cpuPrev = null;
        root._corePrev = [];
        // And the figures from then go too, or they stand in for the load now
        // until the second sample. Mapped, so the per-thread rows stay put.
        root.cpuUse = 0;
        root.coreUse = root.coreUse.map(() => 0);
        root._procPrev = {};
        root._drivePrev = {};
        root.sample();
    }
}
