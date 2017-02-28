#!/bin/bash

progname=$(basename "$0")
libdir=$(dirname "$(readlink -f "$0")")

. "$libdir"/lib.sh
. "$libdir"/lib_tag.sh

# _expand_series [prefix]
_expand_series () {
	local prefix

	if [ -d "$1" ]; then
		prefix=$(readlink -f "$1")
	elif [ "$1" ]; then
		echo "Error: not a directory \"$1\"" > /dev/stderr
		return 1
	fi

	while read; do
		local entry
		read entry <<< "$REPLY"
		if [ -z "$entry" ]; then
			continue
		fi

		local file
		if [ "$prefix" ]; then
			file="$prefix/$entry"
		else
			file=$entry
		fi

		if [ -r "$file" ]; then
			local ref

			if ! ref=$(cat "$file" | tag_get git-commit); then
				return 1
			fi

			if ref=$(echo "$ref" | expand_git_ref); then
				echo "$ref $REPLY"
			else
				return 1
			fi
		elif echo "$entry" | grep -q "^[^#]"; then
			echo "Error: cannot read \"$file\"" > /dev/stderr
			return 1
		fi
	done
}

usage () {
	echo "Usage: $progname [options]"
	echo ""
	echo "Options:"
	echo "    -p, --prefix=<dir>  Search for patches in this directory"
	echo "    -h, --help          Print this help"
	echo ""
}

result=$(getopt -o p:h --long prefix:,help -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
if [ $? != 0 ]; then
	echo "Error: getopt error" >&2
	exit 1
fi

eval set -- "$result"

while true ; do
	case "$1" in
		-p|--prefix)
			opt_prefix=$2
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

if [ ! -d "$LINUX_GIT" ] || ! GIT_DIR=$LINUX_GIT/.git git log -n1 > /dev/null; then
	echo "Error: kernel git tree not found at \"$LINUX_GIT\" (check the LINUX_GIT environment variable)" > /dev/stderr
	exit 1
fi
export GIT_DIR=$LINUX_GIT/.git 

_expand_series "$opt_prefix" | git sort | awk '
	{
		print substr($0, 42)
	}
'
