#!/usr/bin/env python3
"""Replay Wayland mouse deltas and touchpad events through the scroll helper."""

import os
from pathlib import Path
import shutil
import tempfile

os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_QUICK_BACKEND"] = "software"

from PySide6.QtCore import QObject, QMetaObject, QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QInputDevice, QPointingDevice, QWheelEvent
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem, QQuickWindow
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]


def main():
    app = QGuiApplication.instance() or QGuiApplication([])
    with tempfile.TemporaryDirectory(prefix="qs-scroll-input-") as folder:
        target = Path(folder)
        module = target / "qs"
        module.mkdir()
        (module / "qmldir").write_text("module qs\nsingleton Theme 1.0 Theme.qml\nSmoothScroll 1.0 SmoothScroll.qml\n")
        (module / "Theme.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool reduceMotion: false }")
        shutil.copy2(ROOT / "components/SmoothScroll.qml", module)
        engine = QQmlEngine()
        engine.addImportPath(str(target))
        component = QQmlComponent(engine)
        component.setData(b'''import QtQuick
import QtQuick.Window
import qs
Window {
    width: 300; height: 200; visible: true
    Flickable {
        id: list
        objectName: "list"
        anchors.fill: parent; contentHeight: 1000
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { objectName: "smoother"; view: list; animation.objectName: "glide" }
    }
}''', QUrl.fromLocalFile(str(target / "fixture.qml")))
        window = component.create()
        assert isinstance(window, QQuickWindow), [e.toString() for e in component.errors()]
        view = window.findChild(QQuickItem, "list")
        smoother = window.findChild(QQuickItem, "smoother")
        glide = window.findChild(QObject, "glide")
        QTest.qWait(50)
        pad = QPointingDevice("fixture touchpad", 2, QInputDevice.DeviceType.TouchPad,
                              QPointingDevice.PointerType.Finger,
                              QInputDevice.Capability.Position | QInputDevice.Capability.PixelScroll, 1, 0)

        def wheel(pixel, angle=-120, phase=Qt.ScrollPhase.NoScrollPhase, device=None):
            QMetaObject.invokeMethod(view, "cancelFlick")
            view.setProperty("contentY", 0.0)
            if phase != Qt.ScrollPhase.NoScrollPhase:
                begin = QWheelEvent(QPointF(150, 100), QPointF(150, 100), QPoint(), QPoint(),
                                    Qt.MouseButton.NoButton, Qt.KeyboardModifier.NoModifier,
                                    Qt.ScrollPhase.ScrollBegin, False,
                                    Qt.MouseEventSource.MouseEventNotSynthesized,
                                    device or QPointingDevice.primaryPointingDevice())
                app.sendEvent(window, begin)
            event = QWheelEvent(QPointF(150, 100), QPointF(150, 100), QPoint(0, pixel),
                                QPoint(0, angle), Qt.MouseButton.NoButton, Qt.KeyboardModifier.NoModifier,
                                phase, False, Qt.MouseEventSource.MouseEventNotSynthesized,
                                device or QPointingDevice.primaryPointingDevice())
            app.sendEvent(window, event)
            return view.property("contentY")

        for pixel, device in ((0, None), (-15, None), (-15, pad)):
            immediate = wheel(pixel, device=device)
            assert abs(immediate) < 1, f"Mouse wheel jumps immediately with pixel delta {pixel}: {immediate}"
            QTest.qWait(80)
            partial = view.property("contentY")
            assert 0 < partial < 120, f"Mouse wheel did not ease across frames: {partial}"
            QTest.qWait(400)
            assert abs(view.property("contentY") - 120) < 1, f"Mouse wheel lost its travel: {view.property('contentY')}"
            print(f"PASS: mouse wheel eases with pixel delta {pixel}, touchpad label {device is not None}")

        for angle, device, phase in ((0, pad, Qt.ScrollPhase.NoScrollPhase),
                                    (-120, None, Qt.ScrollPhase.ScrollUpdate)):
            smoother.setProperty("enabled", False)
            native_immediate = wheel(-15, angle=angle, phase=phase, device=device)
            QTest.qWait(400)
            native_rest = view.property("contentY")
            smoother.setProperty("enabled", True)
            immediate = wheel(-15, angle=angle, phase=phase, device=device)
            assert not glide.property("running"), "Native gesture incorrectly started wheel easing"
            assert abs(immediate - native_immediate) < 1, "Native input response changed"
            QTest.qWait(400)
            assert abs(view.property("contentY") - native_rest) < 1, "Native input travel changed"
            print(f"PASS: native gesture with device {device is not None}, phase {phase.name}")

        window.close()
        window.deleteLater()
        app.processEvents()


if __name__ == "__main__":
    main()
