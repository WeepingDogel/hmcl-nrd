#!/usr/bin/env python3
import re
import sys

TARGETS = {
    "583e004d718102ae4489aa3f64bcde0c0161d000",
    "8827fd06d8ea8bcd899e54f76004f63a447e2601",
}

# `rebase -i` writes the commit SHA abbreviated (core.abbrev; defaults to
# auto, typically 7-12 chars depending on repo size) rather than a fixed
# 40-char SHA-1. Match a hex token of any reasonable length and resolve it
# against the full target SHAs by prefix, instead of assuming 40 chars.
LINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<cmd>pick|p)\s+(?P<sha>[0-9a-f]{7,40})(?P<rest>\s.*)?$"
)


def main():
    if len(sys.argv) != 2:
        print("Usage: drop_commits.py <rebase-todo-file>", file=sys.stderr)
        return 2

    todo_file = sys.argv[1]

    # newline="" disables universal-newline translation. The todo is written
    # by git with \n endings, but a couple of historical commit subjects
    # contain a literal \r byte mid-line; translating it would split and
    # corrupt those unrelated lines.
    with open(todo_file, encoding="utf-8", newline="") as f:
        lines = f.readlines()

    found = set()
    result = []

    for line in lines:
        newline = "\n" if line.endswith("\n") else ""
        content = line[: len(line) - len(newline)]

        m = LINE_RE.match(content)
        if not m:
            result.append(line)
            continue

        sha = m.group("sha")
        rest = m.group("rest") or ""
        matched = [t for t in TARGETS if t.startswith(sha)]
        if matched:
            found.update(matched)
            line = f"{m.group('indent')}drop {sha}{rest}{newline}"

        result.append(line)

    missing = TARGETS - found
    if missing:
        print(
            "ERROR: target commits not found in rebase todo:",
            file=sys.stderr,
        )
        for commit in sorted(missing):
            print(f"  {commit}", file=sys.stderr)
        return 1

    with open(todo_file, "w", encoding="utf-8", newline="") as f:
        f.writelines(result)

    print("Commits marked for removal:")
    for commit in sorted(found):
        print(f"  {commit}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
