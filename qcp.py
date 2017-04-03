#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import print_function

import argparse
import os
import os.path
import pygit2
import shutil
import StringIO
import subprocess
import sys
import tempfile

import lib
import lib_tag


def format_import(references, tmpdir, dstdir, ref, poi=[]):
    assert len(poi) == 0 # todo
    args = ("git", "format-patch", "--output-directory", tmpdir, "--notes",
            "--max-count=1", "--subject-prefix=", "--no-numbered", ref,)
    src = subprocess.check_output(args, preexec_fn=lib.restore_signals).strip()
    # remove number prefix
    name = os.path.basename(src)[5:]
    dst = os.path.join(dstdir, name)
    if os.path.exists(os.path.join("patches", dst)):
        name = "%s-%s.patch" % (name[:-6], ref[:8],)
        dst = os.path.join(dstdir, name)

    libdir = os.path.dirname(sys.argv[0])
    subprocess.check_call((os.path.join(libdir, "clean_header.sh"),
                           "--commit=%s" % ref, "--reference=%s" % references,
                           src,), preexec_fn=lib.restore_signals)
    subprocess.check_call(("quilt", "import", "-P", dst, src,),
                          preexec_fn=lib.restore_signals)
    # This will remind the user to run refresh_patch.sh
    lib.touch(".pc/%s~refresh" % (dst,))

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate a patch from a git commit and import it into quilt.")
    parser.add_argument("-r", "--references",
                        help="bsc# or FATE# number used to tag the patch file.")
    parser.add_argument("-d", "--destination",
                        help="Destination \"patches.xxx\" directory.")
    parser.add_argument("-f", "--followup", action="store_true",
                        help="Reuse references and destination from the patch "
                        "containing the commit specified in the first "
                        "\"Fixes\" tag in the commit log of the commit to "
                        "import.")
    parser.add_argument("refspec", help="Upstream commit id to import.")
    parser.add_argument("poi", help="Limit patch to specified paths.",
                        nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if not (args.references and args.destination or args.followup):
        print("Error: you must specify --references and --destination or "
              "--followup.", file=sys.stderr)
        sys.exit(1)

    if (args.references or args.destination) and args.followup:
        print("Warning: --followup overrides information from --references and "
              "--destination.", file=sys.stderr)

    if not lib.check_series():
        sys.exit(1)

    repo_path = lib.repo_path()
    if "GIT_DIR" not in os.environ:
        os.environ["GIT_DIR"] = repo_path
    repo = pygit2.Repository(repo_path)
    commit = repo.revparse_single(args.refspec)

    if args.followup:
        fixes = lib.firstword(lib_tag.tag_get(StringIO.StringIO(commit.message),
                                              "Fixes")[0])
        fixes = str(repo.revparse_single(fixes).id)
        f = lib.find_commit_in_series(fixes)
        # remove "patches/" prefix
        patch = f.name[8:]
        destination = os.path.dirname(patch)
        references = " ".join(lib_tag.tag_get(f, "References"))
        print("Info: using references \"%s\" from patch \"%s\" which contains "
              "commit %s." % (references, patch, fixes[:12]), file=sys.stderr)
    else:
        destination = args.destination
        references = args.references

    tmpdir = tempfile.mkdtemp(prefix="qcp.")
    try:
        result = format_import(references, tmpdir, destination, str(commit.id),
                               args.poi)
    finally:
        shutil.rmtree(tmpdir)
    sys.exit(result)
