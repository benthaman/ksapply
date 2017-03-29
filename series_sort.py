#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import argparse
import os
import pygit2
import sys

import lib
import lib_tag

from git_helpers import git_sort


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Sort series.conf lines according to the upstream order of "
        "commits that the patches backport.")
    parser.add_argument("-p", "--prefix", metavar="DIR",
                        help="Search for patches in this directory.")
    args = parser.parse_args()

    repo_path = lib.repo_path()
    if "GIT_DIR" not in os.environ:
        # this is for the `git log` call in git_sort.py
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)

    # out-of-tree
    oot = []
    # Queued in subsystem maintainer repository
    subsys = []
    tagged = {}
    for line in sys.stdin.readlines():
        name = line.strip()
        if not name or name.startswith(("#", "-", "+",)):
            continue
        name = lib.firstword(name)
        if args.prefix is not None:
            name = os.path.join(args.prefix, name)

        if not os.path.exists(name):
            print("Error: could not find patch \"%s\"" % (name,),
                  file=sys.stderr)
            sys.exit(1)

        gc_tags = lib_tag.tag_get(name, "Git-commit")
        if not gc_tags:
            oot.append(line)
            continue
        try:
            h = lib.firstword(gc_tags[0])
            commit = repo.revparse_single(h)
        except KeyError:
            r_tags = lib_tag.tag_get(name, "Git-repo")
            if not r_tags:
                print("Error: commit \"%s\" not found in repository and no "
                      "alternate repository specified. Patch \"%s\" is not "
                      "understood." % (h, name,), file=sys.stderr)
                sys.exit(1)
            subsys.append(line)

        h = str(commit.id)
        if h in tagged:
            tagged[h].append(line)
        else:
            tagged[h] = [line]

    for line_list in git_sort.git_sort(repo, tagged):
        for line in line_list:
            print(line, end="")

    if len(tagged) != 0:
        print("Error: the following entries were not found upstream:", file=sys.stderr)
        for line_list in lines.values():
            for line in line_list:
                print(line, end="")
        sys.exit(1)

    if subsys:
        print("\n\t# Queued in subsystem maintainer repository")
        for line in subsys:
            print(line, end="")

    if oot:
        print("\n\t# Out-of-tree patches")
        for line in oot:
            print(line, end="")
