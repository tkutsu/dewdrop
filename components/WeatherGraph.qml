import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// One day of hourly forecasts for the weather popup. Each measurement keeps
// its own scale, sharing the day's time axis.
Item {
    id: graph

    property var hours: []
    property bool feelsLike: false
    // The three measurements, in drawing order; the readout above the plots
    // takes its colours from here too.
    readonly property var series: [
        {key: graph.feelsLike ? "feelsLike" : "temperature", label: graph.feelsLike ? "Feels like · °C" : "Temperature · °C", color: "#f2b36e", minimum: 10, maximum: 30, step: 5, pixels: 3.2},
        {key: "rain", label: "Rain chance · %", color: "#86b8f0", minimum: 0, maximum: 100, step: 25, pixels: 0.6},
        {key: "wind", label: "Wind · km/h", color: "#b4cfa0", minimum: 0, maximum: 40, step: 10, pixels: 1.5}
    ]
    readonly property int spacing: 5
    readonly property int plotLeft: 56
    readonly property real plotWidth: Math.max(1, graph.width - graph.plotLeft - 12)
    implicitHeight: stack.implicitHeight
    readonly property double start: graph.hours[0]?.at ?? 0
    readonly property double end: graph.hours.length ? graph.hours[graph.hours.length - 1].at + 3600 : graph.start
    readonly property bool showsNow: graph.hours.length > 0 && Weather.now >= graph.start && Weather.now < graph.end
    readonly property real nowX: 2 + Math.max(0, Math.min(1, (Weather.now - graph.start) / Math.max(1, graph.end - graph.start))) * (graph.plotWidth - 4)
    readonly property var iconRanges: Weather.hourRanges(graph.hours, "icon")
    property Item hoveredPlot: null
    readonly property var currentHour: graph.hours.includes(Weather.thisHour) ? Weather.thisHour : null
    readonly property var selectedHour: graph.hoveredHour ?? graph.currentHour
    readonly property var hoveredHour: {
        if (!graph.hoveredPlot || !graph.hours.length)
            return null;
        const plot = graph.hoveredPlot;
        const fraction = Math.max(0, Math.min(1, (plot.pointerX - 2) / Math.max(1, plot.width - 4)));
        const at = graph.start + fraction * (graph.end - graph.start);
        return graph.hours.reduce((nearest, hour) => Math.abs(hour.at - at) < Math.abs(nearest.at - at) ? hour : nearest, graph.hours[0]);
    }

    Column {
        id: stack
        width: graph.width
        spacing: graph.spacing

        Rectangle {
            width: graph.width
            height: 30
            radius: Theme.selectionRadius
            color: Theme.selection

            PopupText {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.captionSize
                visible: graph.selectedHour === null
                color: Theme.label2
                text: "Hover over a graph to see the hourly forecast"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8
                visible: graph.selectedHour !== null

                PopupText {
                    Layout.fillWidth: true
                    text: graph.selectedHour ? `${graph.hoveredHour ? graph.selectedHour.time : "Now"}  ${graph.selectedHour.description}` : ""
                    font.pixelSize: Theme.captionSize
                    elide: Text.ElideRight
                }
                PopupText {
                    Layout.preferredWidth: 100
                    text: `${graph.feelsLike ? "feels like " : ""}${Weather.measure(graph.selectedHour?.[graph.series[0].key], "°C")}`
                    color: graph.series[0].color
                    font.pixelSize: Theme.captionSize
                }
                PopupText {
                    Layout.preferredWidth: 80
                    text: `Rain ${Weather.measure(graph.selectedHour?.rain, "%")}`
                    color: graph.series[1].color
                    font.pixelSize: Theme.captionSize
                }
                PopupText {
                    Layout.preferredWidth: 160
                    text: [Weather.windLabel(graph.selectedHour?.wind).toLowerCase(), graph.selectedHour?.wind >= 1 ? Weather.windBearing(graph.selectedHour?.windDirection) : "", Weather.measure(graph.selectedHour?.wind, " km/h")].filter(part => part !== "").join(" ")
                    color: graph.series[2].color
                    font.pixelSize: Theme.captionSize
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            x: graph.plotLeft
            width: graph.plotWidth
            height: 22

            Repeater {
                model: graph.iconRanges
                delegate: Item {
                    id: interval
                    required property var modelData
                    x: 2 + (modelData.start - graph.start) / Math.max(1, graph.end - graph.start) * (graph.plotWidth - 4)
                    width: (modelData.end - modelData.start) / Math.max(1, graph.end - graph.start) * (graph.plotWidth - 4)
                    height: parent.height
                    readonly property bool hasRange: modelData.end - modelData.start > 3600
                    opacity: modelData.end <= Weather.now ? 0.35 : 0.8

                    Glyph {
                        id: rangeIcon
                        x: (interval.width - width) / 2
                        height: 22
                        text: modelData.hour.icon
                        color: Theme.fg
                        fontSize: Theme.popupGlyphSize
                    }
                    Rectangle {
                        x: 2
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: Math.max(0, rangeIcon.x - x - 4)
                        height: 1
                        visible: interval.hasRange
                        color: Theme.label2
                    }
                    Rectangle {
                        x: rangeIcon.x + rangeIcon.width + 4
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: Math.max(0, parent.width - x - 2)
                        height: 1
                        visible: interval.hasRange
                        color: Theme.label2
                    }
                    Rectangle {
                        x: 2
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: 1
                        height: 5
                        visible: interval.hasRange
                        color: Theme.label2
                    }
                    Rectangle {
                        x: interval.width - 3
                        anchors.verticalCenter: rangeIcon.verticalCenter
                        width: 1
                        height: 5
                        visible: interval.hasRange
                        color: Theme.label2
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
                    readonly property var values: graph.hours.map(hour => hour[series.modelData.key]).filter(value => typeof value === "number" && Number.isFinite(value))
                    readonly property real low: Math.min(modelData.minimum, values.length ? Math.floor(Math.min(...values) / modelData.step) * modelData.step : modelData.minimum)
                    readonly property real high: Math.max(modelData.maximum, values.length ? Math.ceil(Math.max(...values) / modelData.step) * modelData.step : modelData.maximum)
                    readonly property var ticks: Array.from({length: Math.round((high - low) / modelData.step) + 1}, (_, index) => high - index * modelData.step)

                    // Emphasize uncomfortable temperatures, likely rain, and strong wind.
                    function isSevere(value: var): bool {
                        if (typeof value !== "number" || !Number.isFinite(value))
                            return false;
                        if (modelData.key === "rain")
                            return value >= 70;
                        if (modelData.key === "wind")
                            return value >= 40;
                        return value <= 5 || value >= 35;
                    }

                    PopupText {
                        id: seriesTitle
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
                            x: 20
                            width: 28
                            y: plot.y + (series.high - modelData) / (series.high - series.low) * (plot.height - 4) - height / 2 + 2
                            text: Math.round(modelData)
                            horizontalAlignment: Text.AlignRight
                            color: Theme.label2
                            font.pixelSize: Theme.footnoteSize
                        }
                    }

                    Canvas {
                        id: plot
                        x: graph.plotLeft
                        y: (series.height - height) / 2
                        width: graph.plotWidth
                        height: (series.high - series.low) * series.modelData.pixels + 4
                        readonly property var hours: graph.hours
                        readonly property double now: Weather.now
                        readonly property color seriesColor: series.modelData.color
                        readonly property color futureColor: Qt.rgba(seriesColor.r, seriesColor.g, seriesColor.b, 0.8)
                        readonly property color pastColor: Qt.rgba(seriesColor.r * 0.65, seriesColor.g * 0.65, seriesColor.b * 0.65, 0.4)
                        readonly property real passedX: graph.end > graph.start ? Math.max(0, Math.min(width, 2 + (now - graph.start) / (graph.end - graph.start) * (width - 4))) : now > graph.start ? width : 0
                        readonly property real low: series.low
                        readonly property real high: series.high
                        readonly property color gridColor: Qt.rgba(Theme.stroke.r, Theme.stroke.g, Theme.stroke.b, Theme.stroke.a * 0.45)
                        readonly property real pointerX: plotHover.point.position.x
                        readonly property var hoveredHour: graph.hoveredHour
                        readonly property var hoveredValue: hoveredHour ? hoveredHour[series.modelData.key] : null
                        readonly property real hoverY: typeof hoveredValue === "number" && Number.isFinite(hoveredValue) ? 2 + (high - hoveredValue) / (high - low) * (height - 4) : height / 2
                        readonly property real hoverX: hoveredHour && graph.end > graph.start ? 2 + (hoveredHour.at - graph.start) / (graph.end - graph.start) * (width - 4) : width / 2
                        // Everything onPaint reads, so any change repaints once.
                        readonly property var paintInputs: [hours, now, low, high, width, height, pastColor, futureColor, gridColor]
                        onPaintInputsChanged: requestPaint()

                        HoverHandler {
                            id: plotHover
                            onHoveredChanged: {
                                if (hovered)
                                    graph.hoveredPlot = plot;
                                else if (graph.hoveredPlot === plot)
                                    graph.hoveredPlot = null;
                            }
                        }

                        Rectangle {
                            x: plot.hoverX - width / 2
                            y: plot.hoverY - height / 2
                            width: 6
                            height: 6
                            radius: 3
                            color: series.modelData.color
                            visible: graph.hoveredHour !== null && typeof plot.hoveredValue === "number" && Number.isFinite(plot.hoveredValue)
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
                                ctx.moveTo(2, y);
                                ctx.lineTo(width - 2, y);
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
                                    const x = graph.end > graph.start ? 2 + (hour.at - graph.start) / (graph.end - graph.start) * (width - 4) : width / 2;
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

    Rectangle {
        x: graph.hoveredPlot ? Math.round(graph.hoveredPlot.x + graph.hoveredPlot.hoverX) : 0
        y: plots.y + 2
        width: 1
        height: Math.max(0, plots.height - 4)
        visible: graph.hoveredHour !== null
        color: Theme.stroke
        opacity: 0.7
    }

    Rectangle {
        x: graph.plotLeft + graph.nowX
        y: plots.y + 2
        width: 1
        height: Math.max(0, plots.height - 4)
        visible: graph.showsNow
        color: Theme.label2
        opacity: 0.5
    }
}
