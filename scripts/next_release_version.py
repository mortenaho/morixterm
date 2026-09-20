#!/usr/bin/env python3
"""Print the next MoriXterm major release tag from repository tags."""

import re
import subprocess


def next_release_tag(tags: list[str]) -> str:
    versions = []
    for tag in tags:
        match = re.fullmatch(r"v([1-9][0-9]*)", tag)
        if match:
            versions.append(int(match.group(1)))
    return f"v{max([2, *versions]) + 1}"


if __name__ == "__main__":
    existing_tags = subprocess.check_output(["git", "tag", "--list"], text=True).splitlines()
    print(next_release_tag(existing_tags))
