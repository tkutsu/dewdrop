#!/usr/bin/env python3
"""Replay mouse and Wayland touchpad-labelled wheels through the popup handlers."""

import os
from pathlib import Path
import re

os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_QUICK_BACKEND"] = "software"

from PySide6.QtCore import QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QInputDevice, QPointingDevice, QWheelEvent
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]


def handlers(path):
    """Use the production handlers, including their device filtering and callbacks."""
    source = (ROOT / path).read_text()
    found = []
    for match in re.finditer(r"WheelHandler\s*\{", source):
        depth = 1
        end = match.end()
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        found.append(source[match.start():end])
    return found


def main():
    app = QGuiApplication.instance() or QGuiApplication([])
    engine = QQmlEngine()
    pad = QPointingDevice("Wayland wheel", 2, QInputDevice.DeviceType.TouchPad,
                          QPointingDevice.PointerType.Finger,
                          QInputDevice.Capability.Position | QInputDevice.Capability.PixelScroll, 1, 0)
    calendar = handlers("src/components/Calendar.qml")
    weather = handlers("src/components/WeatherPopup.qml")
    assert len(calendar) == 2 and len(weather) == 1
    failures = []
    for name, handler in zip(("calendar title", "calendar grid", "weather days"), calendar + weather):
        component = QQmlComponent(engine)
        component.setData(('''import QtQuick
import QtQuick.Window
Window {
    id: root
    visible: true; width: 200; height: 100
    property int changes: 0
    readonly property date selectedDate: new Date(2026, 9, 14)
    function step(months) { changes += months; }
    function select(day) { changes += day.getDate() - selectedDate.getDate(); }
    QtObject {
        id: forecastScroll
        function scroll(delta) { root.changes -= delta / 120; }
    }
    Item {
        anchors.fill: parent
        ''' + handler + '''
        Text { anchors.fill: parent; text: "Day or month"; TapHandler {} }
    }
}''').encode(), QUrl.fromLocalFile(str(ROOT / "tests/date-scroll-fixture.qml")))
        window = component.create()
        assert isinstance(window, QQuickWindow), [error.toString() for error in component.errors()]
        QTest.qWait(30)
        for device in (QPointingDevice.primaryPointingDevice(), pad):
            window.setProperty("changes", 0)
            for delta, expected in ((-120, 1), (120, 0)):
                event = QWheelEvent(QPointF(100, 50), QPointF(100, 50), QPoint(0, delta // 8),
                                    QPoint(0, delta), Qt.MouseButton.NoButton,
                                    Qt.KeyboardModifier.NoModifier, Qt.ScrollPhase.NoScrollPhase,
                                    False, Qt.MouseEventSource.MouseEventNotSynthesized, device)
                app.sendEvent(window, event)
                actual = window.property("changes")
                if actual != expected:
                    failures.append(f"{name}, {device.type().name}, delta {delta}: expected {expected}, got {actual}")
                    break
            else:
                print(f"PASS: {name} scrolls both ways with {device.type().name}")
        window.close()
        window.deleteLater()
        app.processEvents()
    assert not failures, "\n" + "\n".join(failures)


if __name__ == "__main__":
    main()
