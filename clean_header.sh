#!/bin/bash -e

progname=$(basename "$0")
libdir=$(readlink -f "$(dirname $0)")
opt_commit=
opt_ref=
edit=

export GIT_DIR=$LINUX_GIT/.git

. "$libdir"/patch_tag.sh

usage () {
	echo "Usage: $progname [options] [patch file]"
	echo ""
	echo "Options:"
	printf "\t-c, --commit=<sha1>    Upstream commit id used to tag the patch file.\n"
	printf "\t-r, --reference=<bnc>  bnc or fate number used to tag the patch file.\n"
	printf "\t-h, --help             Print this help\n"
	echo ""
}

# var_override <var name> <value> <source name>
var_override () {
	name=$1
	value=$2
	src=$3
	if [ -n "$value" ]; then
		name_src=${name}_src
		if [ -z "${!name}" ]; then
			eval "$name=\"$value\""
			eval "$name_src=\"$src\""
		elif [ "$value" != "${!name}" ]; then
			echo "Warning: $src ($value) and ${!name_src} (${!name}) differ. Using $src." > /dev/stderr
			eval "$name=\"$value\""
			eval "$name_src=\"$src\""
		fi
	fi
}

# expand_git_ref
expand_git_ref () {
	while read commit; do
		if [ -n "$commit" ]; then
			hash=$(git log -n1 --pretty=format:%H "$commit")
			echo $hash
		fi
	done
}


TEMP=$(getopt -o c:r:h --long commit:,reference:,help -n "$progname" -- "$@")

if [ $? != 0 ]; then
	echo "Error: getopt error" >&2
	exit 1
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
        case "$1" in
                -c|commit)
					opt_commit=$2
					shift
					;;
                -r|reference)
					opt_ref=$2
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

if [ -n "$1" ]; then
	exec 0<"$1"
	shift
fi

if [ -n "$1" ]; then
	echo "Error: too many arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

# * Remove "From" line with tag, since it points to a local commit from
#   kernel.git that I created
# * Remove "Conflicts" section
header=$(awk -f "$libdir"/patch_header.awk | awk -f "$libdir"/clean_from.awk | awk -f "$libdir"/clean_conflicts.awk)

# * Look for "cherry picked" info and replace it with the appropriate tags
cherry=$(sed -nre 's/.*\(cherry picked from commit ([0-9a-f]+)\).*/\1/p' <<< "$header" | expand_git_ref)
if [ -n "$cherry" ]; then
	header=$(awk -f "$libdir/clean_cherry.awk" <<< "$header")
fi

git_commit=$(tag_get git-commit <<< "$header" | expand_git_ref)
header=$(tag_extract git-commit <<< "$header")

opt_commit=$(expand_git_ref <<< "$opt_commit")

# command line > Git-commit > cherry
var_override commit "$cherry" "cherry picked commit"
var_override commit "$git_commit" "Git-commit"
var_override commit "$opt_commit" "command line commit"

patch_mainline=$(tag_get patch-mainline <<< "$header")
header=$(tag_extract patch-mainline <<< "$header")

if [ -z "$commit" ]; then
	echo "Warning: Upstream commit id unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(tag_add Git-commit "<fill me in>" <<< "$header")
	edit=1
else
	header=$(tag_add Git-commit "$commit" <<< "$header")

	if [ ! -d "$LINUX_GIT" ]; then
		echo "Warning: kernel git tree not found at \"$LINUX_GIT\" (check the LINUX_GIT environment variable)" > /dev/stderr
	else
		git_describe=$(git describe --contains --match "v*" $commit)
		if [ -z "$git_describe" ]; then
			git_describe=$(git describe --contains $commit)
		fi
		git_describe=${git_describe%%[~^]*}
	fi
fi

# git describe > Patch-mainline
var_override origin "$patch_mainline" "Patch-mainline"
var_override origin "$git_describe" "git describe output"

if [ -z "$origin" ]; then
	echo "Warning: Mainline status unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(tag_add Patch-mainline "<fill me in>" <<< "$header")
	edit=1
else
	header=$(tag_add Patch-mainline "$origin" <<< "$header")
fi

# * Make sure "References" tag is there
references=$(tag_get references <<< "$header")
header=$(tag_extract references <<< "$header")

# command line > References
var_override ref "$references" "References"
var_override ref "$opt_ref" "command line reference"

if [ -z "$ref" ]; then
	echo "Warning: Reference information unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(tag_add References "<fill me in>" <<< "$header")
	edit=1
else
	header=$(tag_add References "$ref" <<< "$header")
fi

# * Add attribution tag
name=$(git config --get user.name)
email=$(git config --get user.email)

if [ -z "$name" -o -z "$email" ]; then
	echo "Warning: user signature incomplete ($name <$email>), you will have to edit the patch header manually. Check the LINUX_GIT environment variable and the git configuration." > /dev/stderr
	name=${name:-Name}
	email=${email:-user@example.com}
	edit=1
fi
signature="$name <$email>"
if ! tag_get_attributions <<< "$header" | grep -q "$signature"; then
	header=$(tag_add Acked-by "$signature" <<< "$header")
fi

# TODO: if edit: ...

cat <<< "$header"
