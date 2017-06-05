#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
When we want to backport a specific commit at its right position in the sorted
sub-series, it is most efficient to use sequence_patch.sh to expand the tree up
to the patch just before where the new commit will be added. The current script
prints out which patch that is. Use in conjunction with sequence-patch.sh.
"""

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
        description="Print the name of the patch over which the specified "
        "commit should be imported.")
    parser.add_argument("refspec", help="Upstream commit id.")
    args = parser.parse_args()

    repo_path = lib.repo_path()
    if "GIT_DIR" not in os.environ:
        # this is for the `git log` call in git_sort.py
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)
    ref = str(repo.revparse_single(args.refspec).id)

    # tagged[commit] = patch file name of the last patch which implements commit
    tagged = {}
    last = None
    series = lib.split_series(open("series.conf"))
    for patch in series[1]:
        try:
            h = lib.firstword(lib_tag.tag_get(open(patch), "Git-commit")[0])
        except IndexError:
            print("Error: No Git-commit tag found in %s" % (patch,),
                  file=sys.stderr)
            sys.exit(1)

        if h in tagged and last != h:
            print("Error: sub-series is not sorted.", file=sys.stderr)
            sys.exit(1)
        tagged[h] = patch
        last = h

    result = None
    if ref in tagged:
        result = tagged[ref]
    else:
        tagged[ref] = "# commit"
        # else case continued after the sort

    sorted_patches = [commit for
                      head, commit in git_sort.git_sort(repo, tagged)]

    # else continued
    if result is None:
        ref_pos = sorted_patches.index("# commit")
        if ref_pos > 0:
            result = sorted_patches[ref_pos - 1]
        else:
            # should be inserted first in sub-series, get last patch name before
            # sub-series
            result = series[0][-1]
        del sorted_patches[ref_pos]

    if sorted_patches != series[1]:
        print("Error: sub-series is not sorted.", file=sys.stderr)
        sys.exit(1)

    print(result)
