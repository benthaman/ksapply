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
    # tagged[commit] = series.conf entry
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

        f = open(name)
        gc_tags = lib_tag.tag_get(f, "Git-commit")
        if not gc_tags:
            oot.append(line)
            continue
        try:
            h = lib.firstword(gc_tags[0])
            commit = repo.revparse_single(h)
        except KeyError:
            f.seek(0)
            r_tags = lib_tag.tag_get(f, "Git-repo")
            if not r_tags:
                print("Error: commit \"%s\" not found and no Git-repo "
                      "specified. Either the repository at \"%s\" is outdated "
                      "or patch \"%s\" is tagged improperly." % (
                          h, repo_path, name,), file=sys.stderr)
                sys.exit(1)
            subsys.append(line)

        h = str(commit.id)
        if h in tagged:
            tagged[h].append(line)
        else:
            tagged[h] = [line]

    sorted_tagged = list(git_sort.git_sort(repo, tagged))
    if len(tagged) != 0:
        print("Error: the following patches are tagged with commits that were "
              "not found upstream:", file=sys.stderr)
        for line_list in tagged.values():
            for line in line_list:
                print(line, end="", file=sys.stderr)
        sys.exit(1)

    for line_list in sorted_tagged:
        for line in line_list:
            print(line, end="")

    if subsys:
        print("\n\t# Queued in subsystem maintainer repository")
        for line in subsys:
            print(line, end="")

    if oot:
        print("\n\t# Out-of-tree patches")
        for line in oot:
            print(line, end="")
