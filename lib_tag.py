#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
todo: cache the git-commit tag from patches based on name and mtime
"""

import os.path


def tag_get(patch, tag):
    result = []
    for line in open(patch):
        start = "%s: " % (tag,)
        if line.startswith(start):
            result.append(line[len(start):-1])
        elif line.startswith(("---", "***", "Index:", "diff -",)):
            break
    return result

