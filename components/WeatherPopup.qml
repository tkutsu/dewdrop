import QtQuick
import qs
import qs.services

// A short outlook leads into a week of deliberately selected hourly forecasts.
Popup {
    id: root

    readonly property int bodyWidth: 548
    readonly property int panelHeight: root.choosing ? 280 : Weather.days.length ? 82 : 100
    property bool choosing: !Weather.location
    property string picked: ""
    readonly property string todayDate: Weather.today?.date ?? ""
    onTodayDateChanged: if (root.todayDate) root.picked = ""
    readonly property int selected: Math.max(0, root.picked ? Weather.days.findIndex(day => day.date === root.picked) : Weather.days.indexOf(Weather.today))
    readonly property var day: Weather.days[root.selected] ?? null
    readonly property var hours: root.day?.hours ?? []
    acceptsKeyboard: root.choosing
    spacing: 8

    // Each measurement keeps its own scale, sharing the selected day's time axis.
    component WeatherGraph: Item {
        id: graph

        property var hours: []
        property bool feelsLike: false
        readonly property string temperatureKey: graph.feelsLike ? "feelsLike" : "temperature"
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
        readonly property var currentHour: graph.hours.find(hour => hour.at <= Weather.now && Weather.now < hour.at + 3600) ?? null
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

                Row {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 8
                    visible: graph.selectedHour !== null

                    PopupText {
                        width: parent.width - 100 - 80 - 160 - 3 * parent.spacing
                        text: graph.selectedHour ? `${graph.hoveredHour ? graph.selectedHour.time : "Now"}  ${graph.selectedHour.description}` : ""
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                    PopupText {
                        width: 100
                        text: `${Weather.measure(graph.selectedHour?.[graph.temperatureKey], "°C")}${graph.feelsLike ? " feels like" : ""}`
                        color: "#f2b36e"
                        font.pixelSize: Theme.captionSize
                    }
                    PopupText {
                        width: 80
                        text: `Rain ${Weather.measure(graph.selectedHour?.rain, "%")}`
                        color: "#86b8f0"
                        font.pixelSize: Theme.captionSize
                    }
                    PopupText {
                        width: 160
                        text: [Weather.windLabel(graph.selectedHour?.wind).toLowerCase(), graph.selectedHour?.wind >= 1 ? Weather.windBearing(graph.selectedHour?.windDirection) : "", Weather.measure(graph.selectedHour?.wind, " km/h")].filter(part => part !== "").join(" ")
                        color: "#b4cfa0"
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                }
            }

            Column {
                id: plots
                width: graph.width
                spacing: graph.spacing

                Repeater {
                    model: [
                        {key: graph.temperatureKey, label: graph.feelsLike ? "Feels like · °C" : "Temperature · °C", color: "#f2b36e", minimum: 10, maximum: 30, step: 5, pixels: 3.2},
                        {key: "rain", label: "Rain chance · %", color: "#86b8f0", minimum: 0, maximum: 100, step: 25, pixels: 0.6},
                        {key: "wind", label: "Wind · km/h", color: "#b4cfa0", minimum: 0, maximum: 40, step: 10, pixels: 1.5}
                    ]
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
                            onHoursChanged: requestPaint()
                            onNowChanged: requestPaint()
                            onPastColorChanged: requestPaint()
                            onFutureColorChanged: requestPaint()
                            onLowChanged: requestPaint()
                            onHighChanged: requestPaint()
                            onGridColorChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

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

    Component.onDestruction: Weather.query = ""
    Connections {
        target: Weather
        function onLocationChanged(): void { root.picked = ""; }
    }

    PopupHeader {
        width: root.bodyWidth
        title: Weather.location?.label ?? "Weather"

        PopupButton {
            framed: true
            lit: Weather.feelsLike
            label: "feels like"
            onTapped: Weather.feelsLike = !Weather.feelsLike
        }
        PopupButton {
            framed: true
            label: root.choosing && Weather.location ? "cancel" : "change"
            onTapped: {
                if (root.choosing && Weather.location) {
                    root.choosing = false;
                    Weather.query = "";
                } else {
                    root.choosing = true;
                    search.forceActiveFocus();
                }
            }
        }
        PopupButton {
            framed: true
            label: Weather.waitingForForecast ? "waiting..." : Weather.loading ? "loading..." : "refresh"
            live: !!Weather.location && !Weather.loading && !Weather.waitingForForecast
            onTapped: Weather.refresh(true)
        }
    }

    PopupText {
        x: 6
        width: root.bodyWidth - 12
        visible: !root.choosing && Weather.days.length > 0
        text: `Next 6 hours:\n${Weather.stale ? "Last forecast: " : ""}${Weather.summary}`
        color: Theme.label2
        wrapMode: Text.WordWrap
    }

    WeatherGraph {
        width: root.bodyWidth
        visible: !root.choosing && root.hours.length > 0
        hours: root.hours
        feelsLike: Weather.feelsLike
    }

    Item {
        width: root.bodyWidth
        height: root.panelHeight

        Column {
            width: parent.width
            visible: root.choosing
            spacing: 8

            Rectangle {
                width: parent.width
                height: 32
                radius: Theme.selectionRadius
                color: Theme.selection
                border.width: Theme.pillBorder
                border.color: search.activeFocus ? Theme.fg : Theme.stroke

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.fg
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.captionSize
                    selectByMouse: true
                    clip: true
                    text: Weather.query
                    onTextEdited: Weather.query = text
                    Keys.onEscapePressed: {
                        if (Weather.location) {
                            root.choosing = false;
                            Weather.query = "";
                        } else {
                            OpenPopup.dismiss();
                        }
                    }
                    Keys.onReturnPressed: if (Weather.locations.length === 1) {
                        Weather.choose(Weather.locations[0]);
                        root.choosing = false;
                    }
                }
                PopupText {
                    anchors.fill: search
                    visible: search.text === ""
                    text: "Search city or postal code"
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
                }
            }

            PopupText {
                width: parent.width
                text: Weather.rateLimited ? "Location search is paused until the weather cooldown ends." : Weather.searching ? "Searching..." : Weather.searchTrouble || (Weather.query.trim().length < 2 ? "Type at least two characters, then choose a location." : "Choose a location below.")
                color: Weather.rateLimited || Weather.searchTrouble ? Theme.warn : Theme.label2
                font.pixelSize: Theme.captionSize
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Weather.locations
                delegate: PopupRow {
                    id: place
                    required property var modelData
                    width: root.bodyWidth
                    height: 32
                    onTapped: {
                        Weather.choose(place.modelData);
                        root.choosing = false;
                    }
                    PopupText {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: place.modelData.label
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Row {
            id: week
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.choosing && Weather.days.length > 0
            spacing: 4

            Repeater {
                model: Weather.days
                delegate: PopupRow {
                    id: daily
                    required property var modelData
                    required property int index
                    width: Math.floor((root.bodyWidth - week.spacing * (Weather.days.length - 1)) / Math.max(1, Weather.days.length))
                    height: root.panelHeight
                    onTapped: root.picked = daily.modelData.date

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.selectionRadius
                        color: daily.hovered ? Theme.selectionStrong : Theme.selection
                        visible: root.selected === daily.index
                    }
                    PopupText {
                        y: 5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: Weather.dayLabel(daily.modelData)
                        font.pixelSize: Theme.captionSize
                    }
                    Glyph {
                        y: 22
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 20
                        text: daily.modelData.icon
                        fontSize: Theme.popupGlyphSize
                    }
                    PopupText {
                        y: 46
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: `${Weather.measure(daily.modelData.high, "°")} / ${Weather.measure(daily.modelData.low, "°")}`
                        font.pixelSize: Theme.captionSize
                    }
                    PopupText {
                        y: 64
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: `Rain ${Weather.measure(daily.modelData.rain, "%")}`
                        color: Theme.label2
                        font.pixelSize: Theme.footnoteSize
                    }
                }
            }
        }

        PopupText {
            anchors.centerIn: parent
            width: parent.width - 24
            visible: !root.choosing && Weather.days.length === 0
            text: Weather.loading ? "Loading the forecast..." : Weather.trouble || "Choose a location to see its forecast."
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Weather.trouble ? Theme.warn : Theme.label2
        }
    }

    PopupText {
        width: root.bodyWidth
        visible: !root.choosing && (Weather.trouble !== "" || Weather.loading)
        font.pixelSize: Theme.footnoteSize
        color: Weather.stale || Weather.trouble ? Theme.warn : Theme.label2
        wrapMode: Text.WordWrap
        text: Weather.trouble ? `${Weather.trouble}${Weather.days.length ? " Showing the last forecast." : ""}` : "Updating forecast..."
    }

    Item {
        width: root.bodyWidth
        height: Math.max(attribution.implicitHeight, updated.implicitHeight)

        PopupText {
            id: attribution
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: `<a href="https://open-meteo.com/"><font color="${Theme.label2}">Open-Meteo</font></a>`
            textFormat: Text.RichText
            linkColor: Theme.label2
            font.pixelSize: Theme.footnoteSize
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
        PopupText {
            id: updated
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: Weather.updatedAt > 0
            text: `Updated ${Qt.formatDateTime(new Date(Weather.updatedAt * 1000), "HH:mm")}`
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
            font.italic: true
        }
    }
}
