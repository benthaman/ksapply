#!/bin/bash -e

progname=$(basename "$0")
libdir=$(dirname "$(readlink -f "$0")")
filename=

. "$libdir"/lib.sh
. "$libdir"/lib_tag.sh

usage () {
	echo "Usage: $progname [options] <patch file>"
	echo ""
	echo "Options:"
	printf "\t-h, --help              Print this help\n"
	echo ""
}


TEMP=$(getopt -o h --long help -n "$progname" -- "$@")

if [ $? != 0 ]; then
	echo "Error: getopt error" >&2
	exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
        case "$1" in
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

# bash strips trailing newlines in variables, protect them with "---"
filename=$1
patch=$(cat $1 && echo -n ---)
shift

if [ -n "$1" ]; then
	echo "Error: too many arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

body=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_body.awk && echo -n "---")
header=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_header.awk && echo -n "---")

subject=$(echo "$header" | tag_get subject)
patch_num=$(echo "$subject" | get_patch_num)
if [ "$patch_num" ]; then
	patch_num="$(printf %04d $patch_num)-"
fi

new_name="$patch_num$(echo "$subject" | remove_subject_annotation | format_sanitized_subject).patch"

mv "$filename" "$new_name"