#!/bin/bash -e

progname=$(basename "$0")
libdir=$(dirname "$(readlink -f "$0")")
prefix=
number="[[:digit:]]+-"
opt_commit=
opt_ref=

usage () {
	echo "Usage: $progname [options] <dst \"patches.xxx\" dir>"
	echo ""
	echo "Options:"
	printf "\t-p, --prefix=<prefix>       Add a prefix to the patch file name.\n"
	printf "\t-n, --number                Keep the number prefix in the patch file name.\n"
	printf "\t-h, --help                  Print this help\n"
	echo "Options passed to clean_header.sh:"
	printf "\t-c, --commit=<refspec>      Upstream commit id used to tag the patch file.\n"
	printf "\t-r, --reference=<bsc>       bsc or fate number used to tag the patch file.\n"
	printf "\t-R, --soft-reference=<bsc>  bsc or fate number used to tag the patch file if no other reference is found.\n"
	echo ""
}

tempfiles=
clean_tempfiles () {
	local file

	echo "$tempfiles" | while read -r file; do
		if [ -n "$file" -a -f "$file" ]; then
			rm "$file"
		fi
	done
}
trap 'clean_tempfiles' EXIT


result=$(getopt -o p:nc:r:R:h --long prefix:,number,commit:,reference:,soft-reference:,help -n "$progname" -- "$@")

if [ $? != 0 ]; then
	echo "Error: getopt error" >&2
	exit 1
fi

eval set -- "$result"

while true ; do
        case "$1" in
                -p|--prefix)
					prefix="${2%-}-"
					shift
					;;
                -n|--number)
					number=
					;;
                -c|--commit)
					opt_commit=$2
					shift
					;;
                -r|--reference)
					opt_ref=$2
					shift
					;;
                -R|--soft-reference)
					opt_soft=$2
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

if patch_file=$(QUILT_PATCHES_PREFIX=1 quilt next); then
	patch_orig=$(mktemp --tmpdir ksapply-patch_orig.XXXXXXXXXX)
	tempfiles+=$patch_orig$'\n'
	cat "$patch_file" > "$patch_orig"
	if quilt push; then
		:
	else
		exit $?
	fi

	./refresh_patch.sh
	patch_new=$(mktemp --tmpdir ksapply-patch_new.XXXXXXXXXX)
	tempfiles+=$patch_new$'\n'
	cat "$patch_file" > "$patch_new"
	if ! "$libdir"/clean_header.sh -c "$opt_commit" -r "$opt_ref" -R "$opt_soft" "$patch_new"; then
		quilt pop
		cat "$patch_orig" > "$patch_file"
		exit 1
	fi
	cat "$patch_new" | awk -f "$libdir"/patch_header.awk | quilt header -r

	newname=$(quilt top | sed -r "s/^(patches\/)?($number)?/$prefix/")
	if ! quilt rename "$patch_dir/$newname"; then
		quilt pop
		cat "$patch_orig" > "$patch_file"
		exit 1
	fi
else
	exit $?
fi
