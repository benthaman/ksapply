#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
Depends on orderedset, may be install via pip/pip2
    pip install orderedset

Depends on `merge` from rcs

Add a section like this to git config:

[mergetool "git-sort"]
	cmd = /<path>/merge_tool.py $LOCAL $BASE $REMOTE $MERGED
	trustExitCode = true

Then call
git mergetool --tool=git-sort series.conf

"""

from __future__ import print_function

from orderedset import OrderedSet
import os.path
import shutil
import subprocess
import sys

import lib
import series_sort


libdir = os.path.dirname(os.path.abspath(__file__))


def split_series2(series):
    before = []
    patches = []
    after = []

    current = before
    for line in open(series):
        if current == before:
            before.append(line)

            if line.strip() in ("# sorted patches",
                        "# Sorted Network Patches",):
                current = patches
        elif current == patches:
            patch = line.strip()
            if patch and not patch.startswith(("#", "-", "+",)):
                patches.append(lib.firstword(patch))
                after = []
            else:
                after.append(line)

            if line.strip() == "# Wireless Networking":
                current = after
        elif current == after:
            after.append(line)

    if len(after) == 0:
        print("Error: sorted section not found in %s" % (series,))
        sys.exit(1)

    return (before, OrderedSet(patches), after,)


def splice(lines, patches, output):
    f = open(output, mode="w")
    f.writelines(lines[0])
    f.write(patches)
    f.writelines(lines[2])


if __name__ == "__main__":
    (local_path, base_path, remote_path, merged_path,) = sys.argv[1:5]

    base = split_series2(base_path)
    remote = split_series2(remote_path)

    added = remote[1] - base[1]
    removed = base[1] - remote[1]

    local = split_series2(local_path)

    added_nb = len(added)
    removed_nb = len(removed)
    if added_nb or removed_nb:
        print("%d commits added, %d commits removed from base to remote" %
              (added_nb, removed_nb,))
    dup_add_nb = len(local[1] & added)
    dup_rem_nb = len(removed) - len(local[1] & removed)
    if dup_add_nb:
        print("Warning: %d commits added in remote and already present in "
              "local, ignoring" % (dup_add_nb,))
    if dup_rem_nb:
        print("Warning: %d commits removed in remote but not present in local, "
              "ignoring" % (dup_rem_nb,))

    sp = subprocess.Popen(os.path.join(libdir, "series_sort.py"),
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    output = sp.communicate("".join(["\t%s\n" % (patch,) for patch in
                                     local[1] - removed | added]))
    if sp.returncode:
        print("Error: series_sort failed.")
        print(output[1])
        sys.exit(1)

    # If there were no conflicts outside of the sorted section, then it would be
    # sufficient to splice the sorted result into local
    splice(local, output[0], merged_path)

    # ... but we don't know, so splice them all and call `merge` so that the
    # lines outside the sorted section get conflict markers if needed
    splice(base, output[0], base_path)
    splice(remote, output[0], remote_path)

    retval = subprocess.call(["merge", merged_path, base_path, remote_path])
    if retval != 0:
        name = "%s.merged%d" % (merged_path, os.getpid(),)
        print("Warning: conflicts outside of sorted section, leaving merged "
              "result in %s" % (name,))
        shutil.copy(merged_path, name)
        sys.exit(1)
