#!/usr/bin/env python3
"""Fail on obvious duplicate one-property-per-line assignments within the same QML block.
This is intentionally conservative and supplements Qt's own QML checks.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "qml")
assignment = re.compile(r'^([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\s*:')
errors = []

for file in root.rglob("*.qml"):
    stack = [dict()]
    for line_no, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        match = assignment.match(stripped)
        if match:
            key = match.group(1)
            previous = stack[-1].get(key)
            if previous is not None:
                errors.append(f"{file}:{line_no}: property '{key}' already set at line {previous}")
            else:
                stack[-1][key] = line_no
        # This guard intentionally tracks brace scopes. It is not a full QML parser.
        in_string = None
        escaped = False
        for ch in line:
            if escaped:
                escaped = False
                continue
            if ch == '\\':
                escaped = True
                continue
            if in_string:
                if ch == in_string:
                    in_string = None
                continue
            if ch in ('"', "'"):
                in_string = ch
            elif ch == '{':
                stack.append({})
            elif ch == '}' and len(stack) > 1:
                stack.pop()

if errors:
    print("QML duplicate property check failed:", file=sys.stderr)
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("QML duplicate property check passed")
