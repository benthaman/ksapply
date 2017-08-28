#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
Script to sort series.conf lines according to the upstream order of commits that
the patches backport.

This script reads series.conf lines from stdin and outputs its result to stdout.

A convenient way to use series_sort.py to filter a subset of lines
within series.conf when using the vim text editor is to visually
select the lines and filter them through the script:
    shift-v
    j j j j [...] # or ctrl-d or /pattern<enter>
    :'<,'>! ~/<path>/series_sort.py
"""

from __future__ import print_function

import argparse
import collections
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
    # tagged as "Queued in subsystem maintainer repository" and that commit is
    # not found in the repository. This is probably because that remote is not
    # indexed by git-sort.
    # subsys[repo] = series.conf entry
    subsys = collections.defaultdict(list)
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
        except ValueError:
            print("Error: Git-commit tag \"%s\" in patch \"%s\" is not a valid revision." %
                  (h, name,), file=sys.stderr)
            sys.exit(1)
        except KeyError:
            f.seek(0)
            r_tags = lib_tag.tag_get(f, "Git-repo")
            if not r_tags:
                print("Error: commit \"%s\" not found and no Git-repo "
                      "specified. Either the repository at \"%s\" is outdated "
                      "or patch \"%s\" is tagged improperly." % (
                          h, repo_path, name,), file=sys.stderr)
                sys.exit(1)
            elif len(r_tags) > 1:
                print("Error: multiple Git-repo tags found. Patch \"%s\" is "
                      "tagged improperly." % (name,), file=sys.stderr)
                sys.exit(1)
            subsys[r_tags[0]].append(line)
        else:
            h = str(commit.id)
            if h in tagged:
                tagged[h].append(line)
            else:
                tagged[h] = [line]

    last_head = None
    for head, line_list in git_sort.git_sort(repo, tagged):
        if last_head is None:
            last_head = head
        elif head != last_head:
            print("\n\t# %s" % (head,))
            last_head = head

        for line in line_list:
            print(line, end="")


    if len(tagged) != 0:
        # commits that were found in the repository but that are not indexed by
        # git-sort.
        print("\n\t# unsorted patches")
        for line_list in tagged.values():
            for line in line_list:
                print(line, end="")

    for r_tag in sorted(subsys):
        print("\n\t# Queued in %s" % (r_tag,))
        for line in subsys[r_tag]:
            print(line, end="")

    if oot:
        print("\n\t# out-of-tree patches")
        for line in oot:
            print(line, end="")
