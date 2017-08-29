#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import os
import pygit2
import signal
import sys

import lib_tag

from git_helpers import git_sort


class KSException(BaseException):
    pass


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
        raise KSException("Sorted subseries not found.")

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


def sequence_insert(series, rev, top):
    """
    top is the top applied patch, None if none are applied...

    Returns the name of the new top patch and how many must be applied/popped.

    Caller must chdir to where the entries in series can be found
    """
    git_dir = repo_path()
    if "GIT_DIR" not in os.environ:
        # this is for the `git log` call in git_sort.py
        os.environ["GIT_DIR"] = git_dir
    repo = pygit2.Repository(git_dir)
    try:
        commit = str(repo.revparse_single(rev).id)
    except ValueError:
        raise KSException("\"%s\" is not a valid revision." % (rev,))
    except KeyError:
        raise KSException("Revision \"%s\" not found in \"%s\"." % (
            rev, git_dir,))

    # tagged[commit] = patch file name of the last patch which implements commit
    tagged = {}
    last = None

    series = split_series(series)
    for patch in series[1]:
        try:
            h = firstword(lib_tag.tag_get(open(patch), "Git-commit")[0])
        except IndexError:
            raise KSException("No Git-commit tag found in %s." % (patch,))

        if h in tagged and last != h:
            raise KSException("Subseries is not sorted.")
        tagged[h] = patch
        last = h

    if top is None:
        top_index = 0
    else:
        top_index = flatten(series).index(top) + 1

    name = None
    if commit in tagged:
        # calling git_sort in this case may not be mandatory but will be done to
        # validate the current series
        name = tagged[commit]
    else:
        tagged[commit] = "# new commit"
        # else case continued after the sort

    sorted_patches = [patch for
                      head, patch in git_sort.git_sort(repo, tagged)]

    if commit in tagged.keys():
        raise KSException(
            "Requested revision \"%s\" could not be sorted. Please make sure "
            "it is part of the commits indexed by git-sort." % (rev,))

    # else continued
    if name is None:
        commit_pos = sorted_patches.index("# new commit")
        if commit_pos == 0:
            # should be inserted first in subseries, get last patch name before
            # subseries
            name = series[0][-1]
        else:
            name = sorted_patches[commit_pos - 1]
        del sorted_patches[commit_pos]

    if sorted_patches != series[1]:
        raise KSException("Subseries is not sorted.")

    return (name, flatten(series).index(name) + 1 - top_index,)
