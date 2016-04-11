#!/bin/bash

progname=$(basename "$0")
usage () {
	echo "Usage: $progname"
	echo ""
	echo "Read git hash from stdin and check if there is a missing patch"
	echo ""
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

tempfile=$(mktemp)
cleanup() {
	rm $tempfile
	exit 1
}
trap cleanup 0

has_gitoverview=$(! which git-overview >/dev/null 2>&1; echo $?)
while read line; do
	selected_commit=$(echo -n "$line" | awk '{print $1}' | xargs git rev-parse --short=7 )
	if [ "$has_gitoverview" -eq 1 ]; then
		git overview $selected_commit
	else
		git show --abbrev=7 --pretty='%h %s' $selected_commit | head -n 1
	fi
	git log --oneline --abbrev=7 --no-merges --pretty='	%h %s' --grep="$selected_commit" $selected_commit..
done >>$tempfile

missing_patches=$(cat $tempfile | sed -n '/^\t/p' | awk '{print $1}')
for mhash in ${missing_patches[@]}; do
	if grep -q "^$mhash" $tempfile; then
		sed -i "{ /^\t$mhash/d }" $tempfile
	fi
done
cat $tempfile
