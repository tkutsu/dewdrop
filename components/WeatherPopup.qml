import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// Seven days stay beside the hourly detail, so hovering never moves a row.
Popup {
    id: root

    readonly property int bodyWidth: 548
    readonly property int panelHeight: 280
    property bool choosing: !Weather.location
    property int selected: 0
    readonly property var day: Weather.days[root.selected] ?? null
    acceptsKeyboard: root.choosing
    spacing: 6

    Component.onDestruction: Weather.query = ""
    Connections {
        target: Weather
        function onLocationChanged(): void { root.selected = 0; }
    }

    PopupHeader {
        width: root.bodyWidth
        title: Weather.location?.label ?? "Weather"

        PopupButton {
            framed: true
            label: root.choosing && Weather.location ? "cancel" : "change location"
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
            visible: !root.choosing && Weather.days.length > 0
            spacing: 12

            Column {
                width: 226
                spacing: 2

                PopupText {
                    width: parent.width
                    height: 22
                    text: "Next seven days"
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
                }

                Repeater {
                    model: Weather.days
                    delegate: PopupRow {
                        id: daily
                        required property var modelData
                        required property int index
                        width: 226
                        height: 33
                        onHoveredChanged: if (hovered) root.selected = daily.index
                        onTapped: root.selected = daily.index

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.selectionRadius
                            color: Theme.selection
                            visible: root.selected === daily.index
                        }
                        PopupText {
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: daily.modelData.weekday
                            font.pixelSize: Theme.captionSize
                        }
                        Glyph {
                            x: 47
                            height: parent.height
                            text: daily.modelData.icon
                            fontSize: Theme.popupGlyphSize
                        }
                        PopupText {
                            x: 76
                            width: 84
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: `${Weather.measure(daily.modelData.high, "°")} / ${Weather.measure(daily.modelData.low, "°")}`
                            font.pixelSize: Theme.captionSize
                        }
                        PopupText {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.measure(daily.modelData.rain, "%")
                            color: Theme.label2
                            font.pixelSize: Theme.footnoteSize
                        }
                    }
                }

                PopupText {
                    text: "High / low °C   Rain chance %"
                    color: Theme.label2
                    font.pixelSize: Theme.footnoteSize
                }
            }

            Rectangle {
                width: 1
                height: root.panelHeight
                color: Theme.stroke
            }

            Column {
                width: 297
                spacing: 4

                PopupText {
                    width: parent.width
                    height: 22
                    text: root.day?.label ?? "Hourly forecast"
                    font.pixelSize: Theme.captionSize
                }
                Row {
                    spacing: 0
                    Repeater {
                        model: [{label: "Time", width: 48}, {label: "", width: 26}, {label: "°C", width: 65}, {label: "Rain %", width: 67}, {label: "km/h", width: 70}]
                        delegate: PopupText {
                            required property var modelData
                            width: modelData.width
                            text: modelData.label
                            horizontalAlignment: Text.AlignRight
                            color: Theme.label2
                            font.pixelSize: Theme.footnoteSize
                        }
                    }
                }

                Flickable {
                    id: hourly
                    width: parent.width
                    height: 226
                    clip: true
                    contentWidth: width
                    contentHeight: hourRows.height
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    Connections {
                        target: root
                        function onSelectedChanged(): void { hourly.contentY = 0; }
                    }
                    Column {
                        id: hourRows
                        width: parent.width
                        Repeater {
                            model: root.day?.hours ?? []
                            delegate: PopupRow {
                                id: hour
                                required property var modelData
                                width: hourly.width
                                height: 27
                                opacity: hour.modelData.at + 3600 < Weather.now ? 0.45 : 1

                                Row {
                                    height: parent.height
                                    PopupText {
                                        width: 48
                                        height: parent.height
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: hour.modelData.time
                                        font.pixelSize: Theme.captionSize
                                    }
                                    Item {
                                        width: 26
                                        height: parent.height
                                        Glyph {
                                            anchors.centerIn: parent
                                            height: parent.height
                                            text: hour.modelData.icon
                                            fontSize: Theme.popupGlyphSize
                                        }
                                    }
                                    Repeater {
                                        model: [{value: hour.modelData.temperature, width: 65}, {value: hour.modelData.rain, width: 67}, {value: hour.modelData.wind, width: 70}]
                                        delegate: PopupText {
                                            required property var modelData
                                            width: modelData.width
                                            height: hour.height
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                            text: Weather.measure(modelData.value, "")
                                            font.pixelSize: Theme.captionSize
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 2
                        radius: 1
                        height: hourly.height * Math.min(1, hourly.height / Math.max(1, hourly.contentHeight))
                        y: hourly.contentY / Math.max(1, hourly.contentHeight) * hourly.height
                        color: Theme.label2
                        visible: hourly.contentHeight > hourly.height
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
        height: 30
        font.pixelSize: Theme.footnoteSize
        color: Weather.stale || Weather.trouble ? Theme.warn : Theme.label2
        wrapMode: Text.WordWrap
        text: Weather.trouble ? `${Weather.trouble}${Weather.days.length ? " Showing the last forecast." : ""}` : Weather.loading ? "Updating forecast..." : Weather.updatedAt ? `${Weather.stale ? "Last forecast" : "Updated"} ${Qt.formatDateTime(new Date(Weather.updatedAt * 1000), "HH:mm")} - times in ${Weather.timezone}` : "Choose a city to get started."
    }

    PopupText {
        width: root.bodyWidth
        text: `Weather by <a href="https://open-meteo.com/"><font color="${Theme.label2}">Open-Meteo</font></a> - locations by GeoNames`
        textFormat: Text.RichText
        linkColor: Theme.label2
        color: Theme.label2
        font.pixelSize: Theme.footnoteSize
        onLinkActivated: link => Qt.openUrlExternally(link)
    }
}
