#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
todo: have special stuff in git-sort to directly call it as python code to
reduce the printing/parsing and to do an insert that 1) checks/assumes the
sub-series is ordered 2) tells where to insert.
"""

from __future__ import print_function

import argparse
import os
import os.path
import pygit2
import subprocess
import sys

import lib
import lib_tag


def cat_subseries():
    inside = False
    for line in open("series"):
        line = line.strip()
        if inside:
            if line == "# Wireless Networking":
                return

            if line and not line[0] in ("#", "-", "+",):
                yield line
        elif line == "# SLE12-SP3 network driver updates":
            inside = True
            continue


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Print the quilt push or pop command required to reach the "
        "position where the specified commit should be imported.")
    parser.add_argument("refspec", help="Upstream commit id.")
    args = parser.parse_args()

    if not lib.check_series():
        sys.exit(1)

    if "GIT_DIR" in os.environ:
        search_path = os.environ["GIT_DIR"]
    elif "LINUX_GIT" in os.environ:
        search_path = os.environ["LINUX_GIT"]
    else:
        print("Error: \"LINUX_GIT\" environment variable not set.",
              file=sys.stderr)
        sys.exit(1)
    repo_path = pygit2.discover_repository(search_path)
    if "GIT_DIR" not in os.environ:
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)
    ref = str(repo.revparse_single(args.refspec).id)

    # remove "patches/" prefix
    top = subprocess.check_output(("quilt", "top",),
                                  preexec_fn=lib.restore_signals).strip()[8:]

    series = list(cat_subseries())
    if top not in series:
        print("Error: top patch \"%s\" not in sub-series" % (top,),
              file=sys.stderr)
        sys.exit(1)

    # shortcut if we're already at the right position
    if ref in [lib.firstword(v) for v in
        lib_tag.tag_get(os.path.join("patches", top), "Git-commit")]:
        sys.exit(2)

    sp = subprocess.Popen(("git", "sort",), stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=os.environ, preexec_fn=lib.restore_signals)
    for p in series:
        if p == top:
            current = " current"
        else:
            current = ""
        print("%s%s" % (
            lib.firstword(
                lib_tag.tag_get(os.path.join("patches", p), "Git-commit")[0]),
            current,), file=sp.stdin)
    print("%s insert" % (ref,), file=sp.stdin)
    sp.stdin.close()
    series = sp.stdout.readlines()
    sp.wait()
    if sp.returncode != 0:
        print("Error: git sort exited with an error", file=sys.stderr)
        print("".join(series), file=sys.stderr)
        sys.exit(1)

    current = None
    insert = None
    for num in range(len(series)):
        line = series[num]
        if line.endswith("insert\n"):
            insert = num
            if current is not None:
                break
        elif line.endswith("current\n"):
            current = num
            if insert is not None:
                break

    if insert < current:
        print("pop %d" % (current - insert,))
    elif insert == current + 1:
        sys.exit(2)
    else:
        print("push %d" % (insert - (current + 1),))
