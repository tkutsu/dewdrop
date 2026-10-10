import QtQuick
import qs
import qs.services

// One day of hourly forecasts for the weather popup. Each measurement keeps
// its own scale, sharing the day's time axis.
Item {
    id: graph

    property var hours: []
    property var scaleHours: graph.plotHours
    property bool feelsLike: false
    property real contentOffset: 0
    property bool showAxes: true
    property bool showReadout: true
    property Item readoutSource: graph
    readonly property var readoutHour: graph.readoutSource.selectedHour
    property MouseArea cursor: plotHover
    // The three measurements, in drawing order.
    readonly property var series: [
        {key: graph.feelsLike ? "feelsLike" : "temperature", label: graph.feelsLike ? "Feels like · °C" : "Celsius · °C", color: "#f2b36e", minimum: 0, maximum: 40, step: 10, pixels: 1.5},
        {key: "rain", label: "Rain chance · %", color: "#86b8f0", minimum: 0, maximum: 100, step: 25, pixels: 0.6},
        {key: "wind", label: "Wind · km/h", color: "#b4cfa0", minimum: 0, maximum: 40, step: 10, pixels: 1.5}
    ]
    readonly property int spacing: 5
    readonly property int plotLeft: 56
    readonly property real plotWidth: Math.max(1, graph.width - graph.plotLeft - 12)
    implicitHeight: stack.implicitHeight
    readonly property double start: graph.hours[0]?.at ?? 0
    readonly property double end: graph.hours.length ? graph.hours[graph.hours.length - 1].at + 3600 : graph.start
    // Midnight belongs to both plot edges, joining consecutive days at one point.
    readonly property var nextHour: graph.hours.length ? Weather.allHours.find(hour => hour.at === graph.end) ?? null : null
    readonly property var plotHours: graph.nextHour ? graph.hours.concat([graph.nextHour]) : graph.hours
    readonly property var iconRanges: Weather.hourRanges(graph.hours, "icon")
    readonly property real pointerX: graph.cursor.mouseX - graph.contentOffset
    readonly property var currentHour: graph.hours.includes(Weather.thisHour) ? Weather.thisHour : null
    readonly property var selectedHour: graph.hoveredHour ?? graph.currentHour
    readonly property var hoveredHour: {
        if (!graph.cursor.containsMouse || !graph.hours.length || graph.pointerX < 0 || graph.pointerX > graph.plotWidth)
            return null;
        const fraction = graph.pointerX / graph.plotWidth;
        const at = graph.start + fraction * (graph.end - graph.start);
        return graph.hours.reduce((nearest, hour) => Math.abs(hour.at - at) < Math.abs(nearest.at - at) ? hour : nearest, graph.hours[0]);
    }

    // What a series reads at an hour, shown over its dot.
    function reading(key: string, hour: var): string {
        if (key === "rain")
            return Weather.measure(hour.rain, "%");
        if (key === "wind")
            return [Weather.windLabel(hour.wind).toLowerCase(), hour.wind >= 1 ? Weather.windBearing(hour.windDirection) : "", Weather.measure(hour.wind, " km/h")].filter(part => part !== "").join(" ");
        return Weather.measure(hour[key], "°");
    }

    Column {
        id: stack
        width: graph.width
        spacing: graph.spacing

        Item {
            id: strip
            x: graph.plotLeft
            width: graph.plotWidth
            height: 22
            clip: true

            Repeater {
                model: graph.iconRanges
                delegate: Item {
                    id: interval
                    required property var modelData
                    x: graph.contentOffset + (modelData.start - graph.start) / Math.max(1, graph.end - graph.start) * graph.plotWidth
                    width: (modelData.end - modelData.start) / Math.max(1, graph.end - graph.start) * graph.plotWidth
                    height: parent.height
                    readonly property bool hasRange: modelData.end - modelData.start > 3600
                    readonly property color tint: Weather.tint(modelData.hour.icon)
                    opacity: modelData.end <= Weather.now ? 0.35 : 0.8

                    Glyph {
                        id: rangeIcon
                        x: (interval.width - width) / 2
                        height: 22
                        text: modelData.hour.icon
                        color: interval.tint
                        fontSize: Theme.popupGlyphSize
                    }
                    Rectangle {
                        x: 2
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: Math.max(0, rangeIcon.x - x - 4)
                        height: 1
                        visible: interval.hasRange
                        color: interval.tint
                    }
                    Rectangle {
                        x: rangeIcon.x + rangeIcon.width + 4
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: Math.max(0, parent.width - x - 2)
                        height: 1
                        visible: interval.hasRange
                        color: interval.tint
                    }
                    Rectangle {
                        x: 2
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: 1
                        height: 5
                        visible: interval.hasRange
                        color: interval.tint
                    }
                    Rectangle {
                        x: interval.width - 3
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: 1
                        height: 5
                        visible: interval.hasRange
                        color: interval.tint
                    }
                }
            }
        }

        Column {
            id: plots
            width: graph.width
            spacing: graph.spacing

            Repeater {
                model: graph.series
                delegate: Item {
                    id: series
                    required property var modelData
                    width: graph.width
                    height: Math.max(plot.height + 4, seriesTitle.implicitWidth + 8)
                    readonly property var values: graph.scaleHours.map(hour => hour[series.modelData.key]).filter(value => typeof value === "number" && Number.isFinite(value))
                    readonly property real low: Math.min(modelData.minimum, values.length ? Math.floor(Math.min(...values) / modelData.step) * modelData.step : modelData.minimum)
                    readonly property real high: Math.max(modelData.maximum, values.length ? Math.ceil(Math.max(...values) / modelData.step) * modelData.step : modelData.maximum)
                    readonly property var ticks: Array.from({length: Math.round((high - low) / modelData.step) + 1}, (_, index) => high - index * modelData.step)

                    // Emphasize what the six-hour summary calls freezing, hot, rain
                    // likely and strong winds (the windy icon's limit too).
                    function isSevere(value: var): bool {
                        if (typeof value !== "number" || !Number.isFinite(value))
                            return false;
                        if (modelData.key === "rain")
                            return value >= 70;
                        if (modelData.key === "wind")
                            return value >= 39;
                        return value <= 0 || value >= 35;
                    }

                    PopupText {
                        id: seriesTitle
                        visible: graph.showAxes
                        x: 10 - width / 2
                        y: (series.height - height) / 2
                        rotation: -90
                        text: series.modelData.label
                        color: series.modelData.color
                        font.pixelSize: Theme.footnoteSize
                    }

                    Repeater {
                        model: series.ticks
                        delegate: PopupText {
                            required property real modelData
                            visible: graph.showAxes
                            x: 20
                            width: 28
                            y: plot.parent.y + (series.high - modelData) / (series.high - series.low) * (plot.height - 4) - height / 2 + 2
                            text: Math.round(modelData)
                            horizontalAlignment: Text.AlignRight
                            color: Theme.label2
                            font.pixelSize: Theme.footnoteSize
                        }
                    }

                    // Slide only the plot inside its viewport; axes stay outside it.
                    Item {
                        x: graph.plotLeft
                        y: (series.height - height) / 2
                        width: graph.plotWidth
                        height: (series.high - series.low) * series.modelData.pixels + 4
                        clip: true

                        Canvas {
                            id: plot
                            x: graph.contentOffset
                            width: parent.width
                            height: parent.height
                            readonly property var hours: graph.plotHours
                            readonly property double now: Weather.now
                            readonly property color seriesColor: series.modelData.color
                            readonly property color futureColor: Qt.rgba(seriesColor.r, seriesColor.g, seriesColor.b, 0.8)
                            readonly property color pastColor: Qt.rgba(seriesColor.r * 0.65, seriesColor.g * 0.65, seriesColor.b * 0.65, 0.4)
                            readonly property real passedX: graph.end > graph.start ? Math.max(0, Math.min(width, (now - graph.start) / (graph.end - graph.start) * width)) : now > graph.start ? width : 0
                            readonly property real low: series.low
                            readonly property real high: series.high
                            readonly property color gridColor: Qt.rgba(Theme.stroke.r, Theme.stroke.g, Theme.stroke.b, Theme.stroke.a * 0.45)
                            readonly property var selectedValue: graph.selectedHour?.[series.modelData.key] ?? null
                            readonly property bool marked: typeof selectedValue === "number" && Number.isFinite(selectedValue)
                            readonly property real markY: marked ? 2 + (high - selectedValue) / (high - low) * (height - 4) : height / 2
                            readonly property real markX: graph.selectedHour && graph.end > graph.start ? (graph.selectedHour.at - graph.start) / (graph.end - graph.start) * width : width / 2
                            // Everything onPaint reads, so any change repaints once.
                            readonly property var paintInputs: [hours, now, low, high, width, height, pastColor, futureColor, gridColor]
                            onPaintInputsChanged: requestPaint()

                            Rectangle {
                                x: plot.markX - width / 2
                                y: plot.markY - height / 2
                                width: 6
                                height: 6
                                radius: 3
                                color: series.modelData.color
                                visible: plot.marked
                            }
                            // Over the dot, or under it where the plot's top
                            // would cut it off; kept inside the plot's ends.
                            PopupText {
                                x: Math.max(0, Math.min(plot.width - width, plot.markX - width / 2))
                                y: plot.markY - 6 - height >= 0 ? plot.markY - 6 - height : plot.markY + 6
                                visible: plot.marked
                                text: plot.marked ? graph.reading(series.modelData.key, graph.selectedHour) : ""
                                color: series.modelData.color
                                font.pixelSize: Theme.footnoteSize
                            }

                            // Gaps stay gaps; epoch spacing keeps repeated DST hours distinct.
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = gridColor;
                                ctx.lineWidth = 1;
                                for (const tick of series.ticks) {
                                    const y = 2 + (high - tick) / (high - low) * (height - 4);
                                    ctx.beginPath();
                                    ctx.moveTo(0, y);
                                    ctx.lineTo(width, y);
                                    ctx.stroke();
                                }
                                // Keep the series hue on both sides of now, dimming elapsed time.
                                function drawSeries(color) {
                                    ctx.strokeStyle = color;
                                    ctx.fillStyle = color;
                                    ctx.lineCap = "round";
                                    let previous = null;
                                    for (let index = 0; index < hours.length; index++) {
                                        const hour = hours[index];
                                        const value = hour[series.modelData.key];
                                        if (typeof value !== "number" || !Number.isFinite(value)) {
                                            previous = null;
                                            continue;
                                        }
                                        const x = graph.end > graph.start ? (hour.at - graph.start) / (graph.end - graph.start) * width : width / 2;
                                        const y = 2 + (high - value) / (high - low) * (height - 4);
                                        const severe = series.isSevere(value);
                                        if (previous) {
                                            ctx.lineWidth = severe || previous.severe ? 4 : 2;
                                            ctx.beginPath();
                                            ctx.moveTo(previous.x, previous.y);
                                            ctx.lineTo(x, y);
                                            ctx.stroke();
                                        }
                                        const isolated = !previous && !Number.isFinite(hours[index + 1]?.[series.modelData.key]);
                                        if (severe || isolated) {
                                            ctx.beginPath();
                                            ctx.arc(x, y, severe ? 3 : 2, 0, Math.PI * 2);
                                            ctx.fill();
                                        }
                                        previous = {x, y, severe};
                                    }
                                }
                                ctx.save();
                                ctx.beginPath();
                                ctx.rect(0, 0, passedX, height);
                                ctx.clip();
                                drawSeries(pastColor);
                                ctx.restore();
                                ctx.save();
                                ctx.beginPath();
                                ctx.rect(passedX, 0, width - passedX, height);
                                ctx.clip();
                                drawSeries(futureColor);
                                ctx.restore();
                            }
                        }
                    }
                }
            }
        }
    }

    // A single hover surface over the icons and the plots keeps the readings
    // active between them too.
    MouseArea {
        id: plotHover
        x: graph.plotLeft
        y: strip.y
        width: graph.plotWidth
        height: plots.y + plots.height - strip.y
        enabled: graph.cursor === plotHover && graph.enabled
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
    }

    Rectangle {
        x: graph.hoveredHour ? Math.round(graph.plotLeft + graph.contentOffset + (graph.hoveredHour.at - graph.start) / Math.max(1, graph.end - graph.start) * graph.plotWidth) : 0
        y: plots.y + 2
        width: 1
        height: Math.max(0, plots.height - 4)
        visible: graph.hoveredHour !== null && x >= graph.plotLeft && x <= graph.plotLeft + graph.plotWidth
        color: Theme.stroke
        opacity: 0.7
    }

    // The readings' hour, in the corner left of the icons; it stays put while
    // the days slide, like the axes.
    PopupText {
        x: 8
        y: stack.y + strip.y + (strip.height - height) / 2
        visible: graph.showReadout
        text: graph.readoutHour ? graph.readoutSource.hoveredHour ? graph.readoutHour.time : "Now" : ""
        color: Theme.label2
        font.pixelSize: Theme.captionSize
    }
}
