import QtQuick
import qs.src.core
import qs.src.services

// The saved weather city also supplies Auto Night Mode's sunrise and sunset times.
Column {
    id: root

    property bool choosing: !Weather.location
    spacing: 8
    Component.onDestruction: Weather.query = ""

    Row {
        width: parent.width
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        spacing: 12

        PopupText {
            width: parent.width - parent.leftPadding - parent.rightPadding - parent.spacing - change.width
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.location?.label ?? "No location selected"
            elide: Text.ElideRight
        }

        PopupButton {
            id: change
            framed: true
            glyph: root.choosing && Weather.location ? "" : Theme.glyph.location
            label: root.choosing && Weather.location ? "Cancel" : "Change Location"
            onTapped: {
                root.choosing = !root.choosing;
                Weather.query = "";
                if (root.choosing)
                    search.forceActiveFocus();
            }
        }
    }

    Column {
        width: parent.width
        visible: root.choosing
        spacing: 8

        Rectangle {
            x: Theme.popupInset
            width: parent.width - Theme.popupInset * 2
            height: 30
            radius: Theme.selectionRadius
            color: Theme.well
            border.width: Theme.pillBorder
            border.color: search.activeFocus ? Theme.outline : "transparent"

            TextInput {
                id: search
                Accessible.name: "Weather location"
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectionColor: Theme.textSelection
                selectedTextColor: Theme.fg
                cursorDelegate: TextCaret { textInput: search }
                font.family: Theme.bodyFont
                font.pixelSize: Theme.captionSize
                selectByMouse: true
                clip: true
                text: Weather.query
                onTextEdited: Weather.query = text
                Keys.onEscapePressed: function(event) {
                    event.accepted = root.choosing;
                    root.choosing = false;
                    Weather.query = "";
                }
                Keys.onReturnPressed: if (Weather.locations.length) {
                    Weather.choose(Weather.locations[0]);
                    root.choosing = false;
                }
                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: "Search city or postal code"
                    color: Theme.label3
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        PopupNote {
            width: parent.width
            text: Weather.searching ? "Searching…" : Weather.searchTrouble
                || (Weather.query.trim().length < 2 ? "Type at least two characters, then choose a location." : "Choose a location below.")
            warn: !!Weather.searchTrouble
        }

        Repeater {
            model: Weather.locations
            delegate: PopupRow {
                id: place
                required property var modelData
                name: place.modelData.label
                width: root.width
                height: 32
                onTapped: {
                    Weather.choose(place.modelData);
                    root.choosing = false;
                }
                PopupText {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.popupInset
                    anchors.rightMargin: Theme.popupInset
                    verticalAlignment: Text.AlignVCenter
                    text: place.modelData.label
                    font.pixelSize: Theme.captionSize
                    elide: Text.ElideRight
                }
            }
        }
    }
}
