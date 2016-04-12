#!/bin/bash

progname=$(basename "$0")
usage () {
	echo "Usage: $progname"
	echo ""
	echo "Read git hash from stdin and check if there is a missing patch"
	echo ""
	echo "Options:"
	printf "\t-h                      Print this help\n"
}

while getopts ":h" opt; do
	case $opt in
		h)
		  usage
		  exit 0
		  ;;
		?)
		  echo "Invalid option: -$OPTARG" >&2
		  exit 1
		  ;;
	esac
done

indent="    "
declare -a known
tac | while read line; do
	commit=$(git rev-parse --short=7 $(echo "$line" | awk '{print $1}'))
	git log --no-merges --pretty="$indent%h %s" --grep="$commit" $commit.. | \
		grep -vf <(echo -n "${known[@]}" | \
		awk 'BEGIN {RS=" "} {print "^'"$indent"'" $1}')
	known+=("$commit")
	echo "$line"
done | tac
