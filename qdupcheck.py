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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Check if a commit id is already backported by a patch in "
        "series.conf.")
    parser.add_argument("refspec", help="Upstream commit id.")
    args = parser.parse_args()

    if not lib.check_series():
        sys.exit(1)

    if "GIT_DIR" in os.environ:
        search_path = os.environ["GIT_DIR"]
    elif "LINUX_GIT" in os.environ:
        search_path = os.environ["LINUX_GIT"]
    else:
        print("Error: \"LINUX_GIT\" environment variable not set.",
              file=sys.stderr)
        sys.exit(1)
    repo_path = pygit2.discover_repository(search_path)
    repo = pygit2.Repository(repo_path)
    ref = str(repo.revparse_single(args.refspec).id)

    for p in lib.cat_series():
        path = os.path.join("patches", p)
        if ref in lib_tag.tag_get(path, "Git-commit"):
            references = " ".join(lib_tag.tag_get(path, "References"))
            if references:
                references = " for \"%s\"" % (references,)
            print("Commit %s already present in patch \"%s\"%s." % (
                ref[:12], p, references,))

            top = subprocess.check_output(
                ("quilt", "top",), preexec_fn=lib.restore_signals).strip()
            if top == path:
                print("This is the top patch.")
            sys.exit(1)
