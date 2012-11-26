#!/bin/bash -e

progname=$(basename "$0")
libdir=$(dirname "$(readlink -f "$0")")
opt_commit=
opt_ref=
filename=
edit=

export GIT_DIR=$LINUX_GIT/.git
: ${EDITOR:=${VISUAL:=vi}}

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
	local name=$1
	local value=$2
	local src=$3

	if [ -n "$value" ]; then
		local name_src=${name}src
		if [ -z "${!name}" ]; then
			eval "$name=\"$value\""
			eval "$name_src=\"$src\""
		elif [ "$value" != "${!name}" ]; then
			echo "Warning: $src (\"$value\") and ${!name_src} (\"${!name}\") differ. Using $src." > /dev/stderr
			eval "$name=\"$value\""
			eval "$name_src=\"$src\""
		fi
	fi
}

# expand_git_ref
expand_git_ref () {
	local commit

	while read commit; do
		if [ -n "$commit" ]; then
			local hash=$(git log -n1 --pretty=format:%H "$commit")
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
	filename=$1
	patch=$(cat $1; echo -n ---)
	shift
else
	patch=$(cat; echo -n ---)
fi

if [ -n "$1" ]; then
	echo "Error: too many arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

body=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_body.awk; echo -n "---")
# * Remove "From" line with tag, since it points to a local commit from
#   kernel.git that I created
# * Remove "Conflicts" section
header=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_header.awk | awk -f "$libdir"/clean_from.awk | awk -f "$libdir"/clean_conflicts.awk; echo -n "---")

# * Look for "cherry picked" info and replace it with the appropriate tags
cherry=$(echo -n "$header" | sed -nre 's/.*\(cherry picked from commit ([0-9a-f]+)\).*/\1/p' | expand_git_ref)
if [ -n "$cherry" ]; then
	header=$(echo -n "$header" | awk -f "$libdir/clean_cherry.awk")
fi

git_commit=$(echo -n "$header" | tag_get git-commit | expand_git_ref)
header=$(echo -n "$header" | tag_extract git-commit)

opt_commit=$(echo -n "$opt_commit" | expand_git_ref)

# command line > Git-commit > cherry
var_override commit "$cherry" "cherry picked commit"
var_override commit "$git_commit" "Git-commit"
var_override commit "$opt_commit" "command line commit"

patch_mainline=$(echo -n "$header" | tag_get patch-mainline)
header=$(echo -n "$header" | tag_extract patch-mainline)

if [ -z "$commit" -a -t 0 ]; then
	echo "Upstream commit id unknown for patch \"$(echo -n "$header" | tag_get subject)\", enter it now?"
	read -p "(<refspec>/empty cancels): " prompt_commit
	prompt_commit=$(echo "$prompt_commit" | expand_git_ref)
	var_override commit "$prompt_commit" "prompted commit"
fi

if [ -z "$commit" ]; then
	echo "Warning: Upstream commit id unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(echo -n "$header" | tag_add Git-commit "(fill me in)")
	edit=1
else
	header=$(echo -n "$header" | tag_add Git-commit "$commit")

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
	header=$(echo -n "$header" | tag_add Patch-mainline "(fill me in)")
	edit=1
else
	header=$(echo -n "$header" | tag_add Patch-mainline "$origin")
fi

# * Make sure "References" tag is there
references=$(echo -n "$header" | tag_get references)
header=$(echo -n "$header" | tag_extract references)

# command line > References
var_override ref "$references" "References"
var_override ref "$opt_ref" "command line reference"

if [ -z "$ref" ]; then
	echo "Warning: Reference information unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(echo -n "$header" | tag_add References "(fill me in)")
	edit=1
else
	header=$(echo -n "$header" | tag_add References "$ref")
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
if ! echo -n "$header" | tag_get_attributions | grep -q "$signature"; then
	header=$(echo -n "$header" | tag_add Acked-by "$signature")
fi

if [ -n "$edit" ]; then
	if [ ! -t 0 ]; then
		echo "Warning: input is not from a terminal, cannot edit header now." > /dev/stderr
	else
		tmpfile=
		trap '[ -n "$tmpfile" -a -f "$tmpfile" ] && rm "$tmpfile"' EXIT
		tmpfile=$(mktemp --tmpdir clean_header.XXXXXXXXXX)
		echo -n "${header%---}" > "$tmpfile"
		$EDITOR "$tmpfile"
		header=$(cat "$tmpfile"; echo -n "---")
		rm "$tmpfile"
		trap - EXIT
	fi
fi

if [ -n "$filename" ]; then
	exec 1>"$filename"
fi
echo -n "${header%---}"
echo -n "${body%---}"
