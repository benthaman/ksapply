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
    if os.path.exists(path):
        if lib.firstword(lib_tag.tag_get(path, "Git-commit")[0]) == ref:
            top = subprocess.check_output(
                ("quilt", "top",), preexec_fn=lib.restore_signals).strip()
            if top != path:
                # Todo: check if it's in the series at all or some stray file
                # Possibly this error could be removed if we want to revert the
                # stable version of a fix and then import the original version,
                # of have the option to bypass the error with --force
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

    repo_path = lib.repo_path()
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
