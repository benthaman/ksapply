#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import os
import pygit2
import signal
import sys

import lib_tag


# http://stackoverflow.com/questions/22077881/yes-reporting-error-with-subprocess-communicate
def restore_signals(): # from http://hg.python.org/cpython/rev/768722b2ae0a/
    signals = ('SIGPIPE', 'SIGXFZ', 'SIGXFSZ')
    for sig in signals:
        if hasattr(signal, sig):
            signal.signal(getattr(signal, sig), signal.SIG_DFL)


def check_series():
    if open("series").readline().strip() != "# Kernel patches configuration file":
        print("Error: series file does not look like series.conf",
              file=sys.stderr)
        return False
    else:
        return True


def firstword(value):
    return value.split(None, 1)[0]


# Beware that this returns an iterator, not a list
def cat_series(series):
    for line in series:
        line = line.strip()
        if not line:
            continue
        if line.startswith(("#", "-", "+",)):
            continue
        yield firstword(line)


# Beware that this returns an iterator, not a list
def cat_subseries(series):
    inside = False
    for line in series:
        line = line.strip()
        if inside:
            if line == "# Wireless Networking":
                return

            if line and not line[0] in ("#", "-", "+",):
                yield line
        elif line == "# SLE12-SP3 network driver updates":
            inside = True
            continue


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


def find_commit_in_series(ref, series):
    for patch in cat_series(series):
        path = os.path.join("patches", patch)
        f = open(path)
        if ref in [firstword(v) for v in lib_tag.tag_get(f, "Git-commit")]:
            f.seek(0)
            return f
