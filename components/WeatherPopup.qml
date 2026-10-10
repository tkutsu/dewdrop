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
    onDayChanged: Qt.callLater(reel.syncDay)
    onChoosingChanged: Qt.callLater(reel.syncDay)

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

    // Now: the temperature, and beside it the sky with the next six hours.
    Row {
        x: 6
        width: root.bodyWidth - 12
        visible: !root.choosing && Weather.days.length > 0
        spacing: 14

        PopupText {
            id: current
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.measure(Weather.thisHour?.[Weather.feelsLike ? "feelsLike" : "temperature"], "°")
            font.pixelSize: Theme.figureTextSize
        }

        Column {
            width: parent.width - current.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Glyph {
                height: 24
                text: Weather.thisHour?.icon ?? Weather.icon
                color: Weather.tint(text)
                fontSize: Theme.iconSize
            }
            PopupText {
                width: parent.width
                text: `Next 6 hours: ${Weather.nextSixHours}`
                color: Theme.label2
                wrapMode: Text.WordWrap
            }
        }
    }

    Item {
        id: reel
        width: root.bodyWidth
        visible: !root.choosing && root.hours.length > 0
        clip: true
        height: outgoing.implicitHeight
        property var displayedDay: null
        property var incomingDay: null
        property int direction: 1
        property real progress: 0
        readonly property var scaleHours: outgoing.plotHours.concat(incoming.plotHours)

        // Keep the old forecast intact until its replacement has slid into place.
        function syncDay(): void {
            const day = root.day;
            if (!reel.visible || !reel.displayedDay?.hours.length || !day?.hours.length) {
                slide.stop();
                reel.displayedDay = day;
                reel.incomingDay = null;
                reel.progress = 0;
                return;
            }
            // Rapid clicks settle at the latest selection after the current roll.
            if (slide.running)
                return;
            if (day.date === reel.displayedDay.date) {
                reel.displayedDay = day;
                return;
            }
            reel.direction = day.date > reel.displayedDay.date ? 1 : -1;
            reel.incomingDay = day;
            reel.progress = 0;
            slide.start();
        }

        Component.onCompleted: Qt.callLater(reel.syncDay)

        // Accumulate wheel notches across the graphs, keeping forecast bounds.
        // Also the graphs' place in the accessibility tree: an area to hover
        // for the hour under the pointer and to scroll through the days.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            property real acc: 0

            function step(days: int): void {
                const index = Math.max(0, Math.min(Weather.days.length - 1, root.selected + days));
                root.picked = Weather.days[index].date;
            }

            Accessible.role: Accessible.Chart
            Accessible.name: "Forecast graphs"
            Accessible.onScrollUpAction: step(-1)
            Accessible.onScrollDownAction: step(1)

            onWheel: function (wheel) {
                acc -= wheel.angleDelta.y;
                const steps = Math.trunc(acc / 120);
                if (!steps)
                    return;
                acc -= steps * 120;
                const index = Math.max(0, Math.min(Weather.days.length - 1, root.selected + steps));
                root.picked = Weather.days[index].date;
            }
        }

        WeatherGraph {
            id: outgoing
            contentOffset: -reel.direction * outgoing.plotWidth * reel.progress
            width: reel.width
            hours: reel.displayedDay?.hours ?? []
            scaleHours: reel.scaleHours
            feelsLike: Weather.feelsLike
            readoutSource: incoming.hoveredHour !== null ? incoming : outgoing
        }

        WeatherGraph {
            id: incoming
            contentOffset: reel.direction * incoming.plotWidth * (1 - reel.progress)
            width: reel.width
            visible: reel.incomingDay !== null
            hours: reel.incomingDay?.hours ?? []
            scaleHours: reel.scaleHours
            showAxes: false
            showReadout: false
            feelsLike: Weather.feelsLike
            cursor: outgoing.cursor
            enabled: false
        }

        NumberAnimation {
            id: slide
            target: reel
            property: "progress"
            from: 0
            to: 1
            duration: Theme.foldMs
            easing.type: Easing.InOutCubic
            onFinished: {
                reel.displayedDay = reel.incomingDay;
                reel.incomingDay = null;
                reel.progress = 0;
                Qt.callLater(reel.syncDay);
            }
        }
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
                    Accessible.name: "Weather location"
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
                    Keys.onReturnPressed: if (Weather.locations.length) {
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
                    name: place.modelData.label
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
                    name: "Forecast for " + daily.modelData.date
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
                        color: Weather.tint(daily.modelData.icon)
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
        // With no forecast at all, the panel above already says this.
        visible: !root.choosing && Weather.days.length > 0 && (Weather.trouble !== "" || Weather.loading)
        font.pixelSize: Theme.footnoteSize
        color: Weather.trouble ? Theme.warn : Theme.label2
        wrapMode: Text.WordWrap
        text: Weather.trouble ? `${Weather.trouble} Showing the last forecast.` : "Updating forecast..."
    }

    Item {
        width: root.bodyWidth
        height: Math.max(attribution.implicitHeight, updated.implicitHeight)

        PopupText {
            id: attribution
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: `<a href="https://open-meteo.com/" style="color: ${Theme.label2}">Open-Meteo</a>`
            textFormat: Text.RichText
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
            onLinkActivated: link => {
                OpenPopup.dismiss();
                Qt.openUrlExternally(link);
            }
        }
        PopupText {
            id: updated
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: Weather.updatedAt > 0
            text: `Updated ${Qt.formatDateTime(new Date(Weather.updatedAt * 1000),
                Qt.formatDate(new Date(Weather.updatedAt * 1000), "yyyy-MM-dd") === Qt.formatDate(new Date(Weather.now * 1000), "yyyy-MM-dd") ? "HH:mm" : "d MMM HH:mm")}`
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
            font.italic: true
        }
    }
}
