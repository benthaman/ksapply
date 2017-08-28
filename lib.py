#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import os
import pygit2
import signal
import sys

import lib_tag


def check_series():
    if open("series").readline().strip() != "# Kernel patches configuration file":
        print("Error: series file does not look like series.conf",
              file=sys.stderr)
        return False
    else:
        return True


def firstword(value):
    return value.split(None, 1)[0]


def split_series(series):
    before = []
    inside = []
    after = []

    current = before
    for line in series:
        line = line.strip()
        if not line:
            continue

        if current == before and line in ("# sorted patches",
                                          "# Sorted Network Patches",):
            current = inside
        elif current == inside and line in ("# Wireless Networking",
                                            "# out-of-tree patches",):
            current = after

        if line.startswith(("#", "-", "+",)):
            continue

        current.append(firstword(line))

    if current != after:
        raise Exception("Sorted subseries not found.")

    return (before, inside, after,)


# https://stackoverflow.com/a/952952
flatten = lambda l: [item for sublist in l for item in sublist]


def cat_series(series):
    return flatten(split_series(series))


def repo_path():
    if "GIT_DIR" in os.environ:
        search_path = os.environ["GIT_DIR"]
    elif "LINUX_GIT" in os.environ:
        search_path = os.environ["LINUX_GIT"]
    else:
        print("Error: \"LINUX_GIT\" environment variable not set.",
              file=sys.stderr)
        sys.exit(1)
    return pygit2.discover_repository(search_path)


# http://stackoverflow.com/questions/1158076/implement-touch-using-python
def touch(fname, times=None):
    with open(fname, 'a'):
        os.utime(fname, times)


def find_commit_in_series(commit, series):
    for patch in cat_series(series):
        path = os.path.join("patches", patch)
        f = open(path)
        if commit in [firstword(v) for v in lib_tag.tag_get(f, "Git-commit")]:
            f.seek(0)
            return f
