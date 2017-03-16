#!/usr/bin/python
# -*- coding: utf-8 -*-

"""
cache the git-commit tag from patches based on name and mtime
"""

import os.path


def tag_get(patch, tag):
    result = []
    for line in open(patch):
        if line.startswith("%s: " % (tag,)):
            result.append(line.split()[1])
        elif line.startswith(("---", "***", "Index:", "diff -",)):
            break
    return result

