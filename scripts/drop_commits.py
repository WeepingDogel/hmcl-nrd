#!/usr/bin/env python3
import re
import sys

TARGETS = {
    "583e004d718102ae4489aa3f64bcde0c0161d000",
    "8827fd06d8ea8bcd899e54f76004f63a447e2601",
}


def main():
    if len(sys.argv) != 2:
        print("Usage: drop_commits.py <rebase-todo-file>", file=sys.stderr)
        return 2

    todo_file = sys.argv[1]

    with open(todo_file, encoding="utf-8") as f:
        lines = f.readlines()

    found = set()
    result = []

    for line in lines:
        match = re.match(
            r"^(\s*)(pick|p)\s+([0-9a-f]{40})(\s+.*)$",
            line,
        )

        if match and match.group(3) in TARGETS:
            commit = match.group(3)
            found.add(commit)
            line = (
                f"{match.group(1)}drop "
                f"{commit}{match.group(4)}"
            )

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

    with open(todo_file, "w", encoding="utf-8") as f:
        f.writelines(result)

    print("Commits marked for removal:")
    for commit in sorted(found):
        print(f"  {commit}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
