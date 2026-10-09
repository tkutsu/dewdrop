#!/usr/bin/env python3
"""Dump AT-SPI roles, actions and extents; optionally press a named target."""

import argparse
import json

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


def walk(node, depth=0):
    yield node, depth
    for i in range(node.get_child_count()):
        child = node.get_child_at_index(i)
        if child:
            yield from walk(child, depth + 1)


def describe(node, depth):
    row = {
        "depth": depth,
        "pid": node.get_process_id(),
        "role": node.get_role_name(),
        "name": node.get_name(),
        "states": [s.value_nick for s in node.get_state_set().get_states()],
        "attributes": node.get_attributes(),
    }
    component = node.get_component_iface()
    if component:
        row["extents"] = {}
        for kind in (Atspi.CoordType.SCREEN, Atspi.CoordType.WINDOW, Atspi.CoordType.PARENT):
            rect = component.get_extents(kind)
            row["extents"][kind.value_nick] = [rect.x, rect.y, rect.width, rect.height]
    action = node.get_action_iface()
    if action:
        row["actions"] = [action.get_action_name(i) for i in range(action.get_n_actions())]
    value = node.get_value_iface()
    if value:
        row["value"] = {
            "current": value.get_current_value(),
            "minimum": value.get_minimum_value(),
            "maximum": value.get_maximum_value(),
            "step": value.get_minimum_increment(),
        }
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, help="Only inspect this process")
    parser.add_argument("--press", help="Invoke action 0 on one visible named target")
    args = parser.parse_args()
    if args.press and args.pid is None:
        parser.error("--press requires --pid")

    desktop = Atspi.get_desktop(0)
    roots = [desktop.get_child_at_index(i) for i in range(desktop.get_child_count())]
    matches = []
    inspected = False
    for app in roots:
        if app is None or args.pid is not None and app.get_process_id() != args.pid:
            continue
        inspected = True
        for node, depth in walk(app):
            row = describe(node, depth)
            print(json.dumps(row, ensure_ascii=False))
            if args.press and row["name"] == args.press and "showing" in row["states"]:
                matches.append(node)
    if args.pid is not None and not inspected:
        parser.exit(1, "Process is absent from the accessibility tree\n")
    if args.press:
        if len(matches) != 1:
            parser.exit(1, f"Expected one visible target, found {len(matches)}\n")
        action = matches[0].get_action_iface()
        if action is None or not action.do_action(0):
            parser.exit(1, "Action 0 failed\n")
        print(json.dumps({"pressed": args.press}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
