#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import argparse
import os
import os.path
import pygit2
import subprocess
import sys

import lib
import lib_tag

from git_helpers import git_sort


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Print the quilt push or pop command required to reach the "
        "position where the specified commit should be imported.")
    parser.add_argument("rev", help="Upstream commit id.")
    args = parser.parse_args()

    if not lib.check_series():
        sys.exit(1)

    repo_path = lib.repo_path()
    if "GIT_DIR" not in os.environ:
        # this is for the `git log` call in git_sort.py
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)
    try:
        commit = str(repo.revparse_single(args.rev).id)
    except ValueError:
        print("Error: \"%s\" is not a valid revision." % (args.rev,),
              file=sys.stderr)
        sys.exit(1)
    except KeyError:
        print("Error: revision \"%s\" not found in \"%s\"." % (
            args.rev, repo_path), file=sys.stderr)
        sys.exit(1)

    # remove "patches/" prefix
    top = subprocess.check_output(("quilt", "top",)).strip()[8:]

    # tagged[commit] = index
    # index is the number of patches applied in the subseries to get to the
    # last patch which implements commit
    tagged = {}
    index = 1
    last = None
    current = None

    series = lib.split_series(open("series"))
    for patch in series[1]:
        h = lib.firstword(lib_tag.tag_get(open(os.path.join("patches", patch)),
                                          "Git-commit")[0])
        if h in tagged and last != h:
            print("Error: subseries is not sorted.", file=sys.stderr)
            sys.exit(1)
        tagged[h] = index
        if patch == top:
            current = index
        last = h
        index += 1

    delta = 0
    # top is outside the subseries
    if current is None:
        delta += len(series[0]) - 1 - lib.flatten(series).index(top)
        current = 0

    insert = None
    if commit in tagged:
        insert = tagged[commit]
    else:
        tagged[commit] = index
        # else case continued after the sort

    sorted_indexes = [0]
    sorted_indexes.extend([commit for
                           head, commit in git_sort.git_sort(repo, tagged)])

    if index in tagged.values():
        print("Error: requested revision \"%s\" could not be sorted. Please "
              "make sure it is part of the commits indexed by git-sort." %
              args.rev, file=sys.stderr)
        sys.exit(1)

    # else continued
    if insert is None:
        commit_pos = sorted_indexes.index(index)
        insert = sorted_indexes[commit_pos - 1]
        del sorted_indexes[commit_pos]

    if sorted(sorted_indexes) != sorted_indexes:
        print("Error: subseries is not sorted.", file=sys.stderr)
        sys.exit(1)

    delta += insert - current
    if delta > 0:
        print("push %d" % (delta,))
    elif delta < 0:
        print("pop %d" % (-1 * delta,))
