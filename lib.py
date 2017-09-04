#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import collections
import os
import pygit2
import signal
import sys

import lib_tag

from git_helpers import git_sort


class KSException(BaseException):
    pass


class KSError(KSException):
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


class KSNotFound(KSException):
    pass


def split_series(series):
    before = []
    inside = []
    after = []

    whitespace = []
    comments = []

    current = before
    for line in series:
        l = line.strip()

        if l == "":
            if comments:
                current.extend(comments)
                comments = []
            whitespace.append(line)
            continue
        elif l.startswith("#"):
            if whitespace:
                current.extend(whitespace)
                whitespace = []
            comments.append(line)

            if current == before and l in ("# sorted patches",
                                           "# Sorted Network Patches",):
                current = inside
            elif current == inside and l in ("# Wireless Networking",):
                current = after
        else:
            if comments:
                current.extend(comments)
                comments = []
            if whitespace:
                current.extend(whitespace)
                whitespace = []
            current.append(line)

    if current == before:
        raise KSNotFound("Sorted subseries not found.")

    current.extend(comments)
    current.extend(whitespace)

    return (before, inside, after,)


def filter_patches(line):
    line = line.strip()

    if line == "" or line.startswith(("#", "-", "+",)):
        return False
    else:
        return True


def series_header(series):
    header = []

    for line in series:
        if not filter_patches(line):
            header.append(line)
            continue
        else:
            break

    return header


def series_footer(series):
    return series_header(reversed(series))


def filter_sorted(series):
    """
    Return upstream patch names from the sorted section
    """
    result = []

    for line in series:
        line = line.strip()
        if line == "# out-of-tree patches":
            break

        if line == "" or line.startswith(("#", "-", "+",)):
            continue

        result.append(line)

    return result


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
    for patch in [firstword(l) for l in series if filter_patches(l)]:
        path = os.path.join("patches", patch)
        f = open(path)
        if commit in [firstword(t) for t in lib_tag.tag_get(f, "Git-commit")]:
            return f


# https://stackoverflow.com/a/952952
flatten = lambda l: [item for sublist in l for item in sublist]


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
        raise KSError("\"%s\" is not a valid revision." % (rev,))
    except KeyError:
        raise KSError("Revision \"%s\" not found in \"%s\"." % (
            rev, git_dir,))

    # tagged[commit] = patch file name of the last patch which implements commit
    tagged = {}
    last = None

    before, inside, after = split_series(series)
    patches = [firstword(l) for l in flatten([before, inside, after]) if
               filter_patches(l)]
    before = [firstword(l) for l in before if filter_patches(l)]
    inside = filter_sorted(inside)
    for patch in inside:
        try:
            h = firstword(lib_tag.tag_get(open(patch), "Git-commit")[0])
        except IndexError:
            raise KSError("No Git-commit tag found in %s." % (patch,))

        if h in tagged and last != h:
            raise KSError("Subseries is not sorted.")
        tagged[h] = patch
        last = h

    if top is None:
        top_index = 0
    else:
        top_index = patches.index(top) + 1

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
        raise KSError(
            "Requested revision \"%s\" could not be sorted. Please make sure "
            "it is part of the commits indexed by git-sort." % (rev,))

    # else continued
    if name is None:
        commit_pos = sorted_patches.index("# new commit")
        if commit_pos == 0:
            # should be inserted first in subseries, get last patch name before
            # subseries
            name = before[-1]
        else:
            name = sorted_patches[commit_pos - 1]
        del sorted_patches[commit_pos]

    if sorted_patches != inside:
        raise KSError("Subseries is not sorted.")

    return (name, patches.index(name) + 1 - top_index,)


def series_sort(repo, series):
    """
    series is the sorted subsection only
    """
    result = []
    # out-of-tree
    oot = []
    # tagged as "Queued in subsystem maintainer repository" and that commit is
    # not found in the repository. This is probably because that remote is not
    # indexed by git-sort.
    # subsys[repo][] = series.conf entry
    subsys = collections.defaultdict(list)
    # tagged[commit][] = series.conf entry
    tagged = collections.defaultdict(list)
    for line in [l for l in series if filter_patches(l)]:
        patch = firstword(line)
        if not patch:
            continue

        if not os.path.exists(patch):
            raise KSError("Could not find patch \"%s\"" % (patch,))

        f = open(patch)
        commit_tags = lib_tag.tag_get(f, "Git-commit")
        if not commit_tags:
            oot.append(line)
            continue
        try:
            rev = firstword(commit_tags[0])
            commit = repo.revparse_single(rev)
        except ValueError:
            raise KSError("Git-commit tag \"%s\" in patch \"%s\" is not a valid revision." %
                              (rev, patch,))
        except KeyError:
            repo_tags = lib_tag.tag_get(f, "Git-repo")
            if not repo_tags:
                raise KSError(
                    "Commit \"%s\" not found and no Git-repo specified. "
                    "Either the repository at \"%s\" is outdated or patch \"%s\" is tagged improperly." % (
                        rev, repo_path, patch,))
            elif len(repo_tags) > 1:
                raise KSError("Multiple Git-repo tags found."
                                  "Patch \"%s\" is tagged improperly." %
                                  (patch,))
            subsys[repo_tags[0]].append(line)
        else:
            commit = str(commit.id)
            tagged[commit].append(line)

    last_head = None
    for head, line_list in git_sort.git_sort(repo, tagged):
        if last_head is None:
            last_head = head
        elif head != last_head:
            result.extend(["\n", "\t# %s\n" % (head,)])
            last_head = head

        result.extend(line_list)

    if len(tagged) != 0:
        # commits that were found in the repository but that are not indexed by
        # git-sort.
        result.extend(["\n", "\t# unsorted patches\n"])
        result.extend(lib.flatten(tagged.values()))

    for r_tag in sorted(subsys):
        result.extend(["\n", "\t# Queued in %s\n" % (r_tag,)])
        result.extend(subsys[r_tag])

    if oot:
        result.extend(["\n", "\t# out-of-tree patches\n"])
        result.extend(oot)

    return result
