#!/usr/bin/env python3
"""Lightweight guard for edited GDScript files.

Godot is not installed on this machine, so this script only checks two failure
modes that would break the project outright: indentation that starts with
spaces (GDScript files in this repository are tab indented) and unbalanced
brackets outside strings/comments.

    python artifacts/elite-build-20261101/check_gdscript.py
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FILES = [
    "src/content/content_db.gd",
    "src/battle/battle_engine.gd",
    "src/ui/battle_layout.gd",
    "tests/run_tests.gd",
    "tests/suites/test_elite_encounters.gd",
]
PAIRS = {")": "(", "]": "[", "}": "{"}


def strip_code(line):
    result = []
    in_string = None
    escaped = False
    index = 0
    while index < len(line):
        character = line[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == in_string:
                in_string = None
            result.append(" ")
        else:
            if character in "\"'":
                in_string = character
                result.append(" ")
            elif character == "#":
                break
            else:
                result.append(character)
        index += 1
    return "".join(result)


def main():
    issues = []
    for relative in FILES:
        path = ROOT / relative
        with path.open(encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        stack = []
        for number, raw in enumerate(lines, start=1):
            if raw.startswith(" "):
                issues.append("%s:%d indents with spaces" % (relative, number))
            for character in strip_code(raw):
                if character in "([{":
                    stack.append((character, number))
                elif character in ")]}":
                    if not stack or stack[-1][0] != PAIRS[character]:
                        issues.append("%s:%d unbalanced %s" % (relative, number, character))
                        stack = []
                        break
                    stack.pop()
        for character, number in stack:
            issues.append("%s:%d unclosed %s" % (relative, number, character))
    if issues:
        for message in issues:
            print("ISSUE:", message)
        print("RESULT: %d issue(s)" % len(issues))
        return 1
    print("RESULT: indentation and bracket checks passed for %d files" % len(FILES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
