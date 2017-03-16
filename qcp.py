#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import argparse
import os
import os.path
import pygit2
import shutil
import subprocess
import sys
import tempfile

import lib
import lib_tag


def doit(references, tmpdir, dstdir, ref, poi=[]):
    assert len(poi) == 0 # todo
    args = ("git", "format-patch", "--output-directory", tmpdir, "--notes",
            "--max-count=1", "--subject-prefix=", "--no-numbered", ref,)
    src = subprocess.check_output(args, preexec_fn=lib.restore_signals).strip()
    # remove number prefix
    name = os.path.basename(src)[5:]
    dst = os.path.join(dstdir, name)
    path = os.path.join("patches", dst)
    action = "import"
    if os.path.exists(path):
        if lib_tag.tag_get(path, "Git-commit")[0] == ref:
            top = subprocess.check_output(
                ("quilt", "top",), preexec_fn=lib.restore_signals).strip()
            if top == path:
                action = "squash"
            else:
                # todo: check if it's in the series at all or some stray file
                print("Error: ref \"%s\" already present in patch \"%s\" not here in the series."
                      % (ref, dst,), file=sys.stderr)
                return 1
        name = "%s-%s.patch" % (name[:-6], ref[:8],)
        dst = os.path.join(dstdir, name)

    libdir = os.path.dirname(sys.argv[0])
    subprocess.check_call((os.path.join(libdir, "clean_header.sh"),
                           "--commit=%s" % ref, "--reference=%s" % references,
                           src,), preexec_fn=lib.restore_signals)
    subprocess.check_call(("quilt", "import", "-P", dst, src,),
                          preexec_fn=lib.restore_signals)

    if action == "squash":
        print("Warning: patch \"%s\" should be squashed." % (dst,), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate a patch from a git commit and import it into quilt.")
    parser.add_argument("-r", "--references", required=True,
                        help="bsc# or FATE# number used to tag the patch file.")
    parser.add_argument("-d", "--destination", required=True,
                        help="Destination \"patches.xxx\" directory.")
    parser.add_argument("refspec", help="Upstream commit id to import.")
    parser.add_argument("poi", help="Limit patch to specified paths.",
                        nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if not lib.check_series():
        sys.exit(1)

    if "GIT_DIR" in os.environ:
        search_path = os.environ["GIT_DIR"]
    elif "LINUX_GIT" in os.environ:
        search_path = os.environ["LINUX_GIT"]
    else:
        print("Error: \"LINUX_GIT\" environment variable not set.", file=sys.stderr)
        sys.exit(1)
    repo_path = pygit2.discover_repository(search_path)
    if "GIT_DIR" not in os.environ:
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)
    ref = str(repo.revparse_single(args.refspec).id)

    tmpdir = tempfile.mkdtemp(prefix="qcp.")

    try:
        result = doit(args.references, tmpdir, args.destination, ref, args.poi)
    finally:
        shutil.rmtree(tmpdir)
    sys.exit(result)
