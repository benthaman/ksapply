#!/bin/bash -e

progname=$(basename "$0")
libdir=$(readlink -f "$0")
prefix=
number="[[:digit:]]+-"
commit=
ref=

usage () {
	echo "Usage: $progname [option] <dst \"patches.xxx\" dir>"
	echo ""
	echo "Options:"
	printf "\t-p, --prefix=<prefix>  Add a prefix to the patch file name.\n"
	printf "\t-n, --number           Keep the number prefix in the patch file name.\n"
	printf "\t-c, --commit=<sha1>    Upstream commit id used to tag the patch file.\n"
	printf "\t-r, --reference=<bnc>  bnc or fate number used to tag the patch file.\n"
	printf "\t-h, --help             Print this help\n"
	echo ""
}


TEMP=$(getopt -o p:nh --long prefix:,number,commit:,reference:,help -n "$progname" -- "$@")

if [ $? != 0 ]; then
	echo "Error: getopt error" >&2
	exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
        case "$1" in
                -p|prefix)
					prefix=$2
					shift
					;;
                -n|number)
					number=
					;;
                -c|commit)
					commit=$2
					shift
					;;
                -r|reference)
					ref=$2
					shift
					;;
                -h|--help)
					usage
					exit 0
					;;
                --)
					shift
					break
					;;
                *)
					echo "Error: could not parse arguments" >&2
					exit 1
					;;
        esac
	shift
done

if [ -z "$1" ]; then
	echo "Error: too few arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

patch_dir=$1
shift
if [ ! -d patches/"$patch_dir" ]; then
	echo "Error: patch directory \"$patch_dir\" does not exist" > /dev/stderr
	exit 1
fi

if [ -n "$1" ]; then
	echo "Error: too many arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

quilt push
./refresh_patch.sh
#name=$(quilt top | sed -r "s/^patches\/$number/$prefix-/")
#quilt rename "$patch_dir/$name"

header=$(quilt header | awk -f "$libdir/clean_from.awk" | awk -f "$libdir/clean_conflicts.awk")

cherry=$(sed -n 's/(cherry picked from commit \([0-9a-f]+\))/\1/p' <<< "$header")

if [ -n "$cherry" ]; then
	header=$(awk -f "$libdir/clean_cherry.awk" <<< "$header")
	if [ -z "$commit" ]; then
		commit=$cherry
	elif [ "$commit" != "$cherry" ]; then
		echo "Commit ids from the patch file ($cherry) and the command line ($commit) differ. Using the one from the command line." > /dev/stderr
	fi
fi

git-commit=$($libdir/patch-tag.py print git-commit <<< "$header")

if [ -n "$commit" ]; then
	echo "Upstream commit id unknown, you will have to edit the patch header manually" > /dev/stderr
else
	if [ -n "$LINUX_GIT" ]; then
		echo "
fi

quilt header -r <<< "$header"
