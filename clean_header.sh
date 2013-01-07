#!/bin/bash -e

progname=$(basename "$0")
libdir=$(dirname "$(readlink -f "$0")")
opt_commit=
opt_ref=
filename=
edit=

export GIT_DIR=$LINUX_GIT/.git
: ${EDITOR:=${VISUAL:=vi}}

. "$libdir"/lib_from.sh
. "$libdir"/lib_tag.sh
. "$libdir"/lib.sh

usage () {
	echo "Usage: $progname [options] [patch file]"
	echo ""
	echo "Options:"
	printf "\t-c, --commit=<refspec>  Upstream commit id used to tag the patch file.\n"
	printf "\t-r, --reference=<bnc>   bnc or fate number used to tag the patch file.\n"
	printf "\t-h, --help              Print this help\n"
	echo ""
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
                -c|--commit)
					opt_commit=$2
					shift
					;;
                -r|--reference)
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

# bash strips trailing newlines in variables, protect them with "---"
if [ -n "$1" ]; then
	filename=$1
	patch=$(cat $1 && echo -n ---)
	shift
else
	patch=$(cat && echo -n ---)
fi

if [ -n "$1" ]; then
	echo "Error: too many arguments" > /dev/stderr
	usage > /dev/stderr
	exit 1
fi

if [ ! -d "$LINUX_GIT" ] || ! git log -n1 > /dev/null; then
	echo "Warning: kernel git tree not found at \"$LINUX_GIT\" (check the LINUX_GIT environment variable)" > /dev/stderr
	exit 1
fi

if echo -n "${patch%---}" | grep -q $'\r'; then
	patch=$(echo -n "${patch%---}" | sed -e 's/\r//g' && echo -n "---")
fi

body=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_body.awk && echo -n "---")
# * Remove "From" line with tag, since it points to a local commit from
#   kernel.git that I created
# * Remove "Conflicts" section
header=$(echo -n "${patch%---}" | awk -f "$libdir"/patch_header.awk | from_extract | awk -f "$libdir"/clean_conflicts.awk && echo -n "---")


# Git-commit:

cherry=$(echo "$header" | sed -nre 's/.*\(cherry picked from commit ([0-9a-f]+)\).*/\1/p' | expand_git_ref)
if [ -n "$cherry" ]; then
	header=$(echo -n "$header" | awk -f "$libdir/clean_cherry.awk")
fi

git_commit=$(echo "$header" | tag_get git-commit | expand_git_ref)
header=$(echo -n "$header" | tag_extract git-commit)

opt_commit=$(echo "$opt_commit" | expand_git_ref)

# command line > Git-commit > cherry
var_override commit "$cherry" "cherry picked commit"
var_override commit "$git_commit" "Git-commit"
var_override commit "$opt_commit" "command line commit"

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
	commit_str=$commit
	if [ -n "${body%---}" ]; then
		cl_orig=$(git show --no-renames $commit | diffstat -lp1 | wc -l)
		echo -n "${body%---}" > /tmp/output
		cl_patch=$(echo -n "${body%---}" | diffstat -lp1 | wc -l)
		if [ $cl_orig -ne $cl_patch ]; then
			commit_str+=" (partial)"
		fi
	fi
	header=$(echo -n "$header" | tag_add Git-commit "$commit_str")

	git_describe=$(git describe --contains --match "v*" $commit 2>/dev/null || true)
	git_describe=${git_describe%%[~^]*}
	if [ -z "$git_describe" ]; then
		git_describe="Queued in subsystem maintainer repository"
		branch=$(git describe --contains --all $commit)
		branch=${branch%%[~^]*}
		remote=$(git config --get branch.$branch.remote)
		describe_url=$(git config --get remote.$remote.url)
	fi
fi


# Patch-mainline:

patch_mainline=$(echo -n "$header" | tag_get patch-mainline)
header=$(echo -n "$header" | tag_extract patch-mainline)

# Sometimes the tag does not include -rcX, I prefer to have it
# var_override can take care of it, but it will generate a warning
if echo "x$git_describe" | grep -q "x$patch_mainline"; then
	patch_mainline=$git_describe
fi

# git describe > Patch-mainline
var_override ml_status "$patch_mainline" "Patch-mainline"
var_override ml_status "$git_describe" "git describe result"

if [ -z "$ml_status" ]; then
	echo "Warning: Mainline status unknown, you will have to edit the patch header manually." > /dev/stderr
	header=$(echo -n "$header" | tag_add Patch-mainline "(fill me in)")
	edit=1
else
	header=$(echo -n "$header" | tag_add Patch-mainline "$ml_status")
fi


# Git-repo:

git_repo=$(echo -n "$header" | tag_get git-repo)
header=$(echo -n "$header" | tag_extract git-repo)

# git config > Git-repo
var_override remote_url "$git_repo" "Git-repo"
var_override --allow-empty remote_url "$describe_url" "git describe and remote configuration"

if [ -n "$remote_url" ]; then
	header=$(echo -n "$header" | tag_add Git-repo "$remote_url")
fi


# References:

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


if [ -n "$commit" ]; then

	# Clean subject

	patch_subject=$(echo -n "$header" | tag_get subject | remove_subject_annotation)
	header=$(echo -n "$header" | tag_extract subject)
	original_header=$(git format-patch --stdout -p $commit^..$commit | awk -f "$libdir"/patch_header.awk && echo -n ---)
	original_subject=$(echo -n "$original_header" | tag_get subject | remove_subject_annotation)

	# git format-patch > Subject
	var_override subject "$patch_subject" "patch file subject"
	var_override subject "$original_subject" "git format-patch subject"

	header=$(echo -n "$header" | tag_add Subject "$subject")


	# Clean attributions

	patch_attributions=$(echo -n "$header" | tag_get_attribution_block)
	original_attributions=$(echo -n "$original_header" | tag_get_attribution_block)
	count=$(comm -23 <(echo "$original_attributions" | sort) <(echo "$patch_attributions" | sort) | wc -l)
	if [ $count -gt 0 ]; then
		echo "Warning: $count attribution lines missing from the patch file. Adding them." > /dev/stderr
		new_block=$original_attributions$'\n'
		new_block+=$patch_attributions
		new_block=$(echo "$new_block" | uniq_nosort)
		header=$(echo -n "$header" | tag_replace_attribution_block "$new_block")
	fi
fi


# Acked-by:

name=$(git config --get user.name)
email=$(git config --get user.email)

if [ -z "$name" -o -z "$email" ]; then
	name_str=${name:-(empty name)}
	email_str=${email:-(empty email)}
	echo "Warning: user signature incomplete ($name_str <$email_str>), you will have to edit the patch header manually. Check the LINUX_GIT environment variable and the git configuration." > /dev/stderr
	name=${name:-Name}
	email=${email:-user@example.com}
	edit=1
fi
signature="$name <$email>"
if ! echo -n "$header" | tag_get_attribution_names | grep -q "$signature"; then
	header=$(echo -n "${header%---}" | tag_add Acked-by "$signature" && echo -n ---)
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
		header=$(cat "$tmpfile" && echo -n "---")
		rm "$tmpfile"
		trap - EXIT
	fi
fi

if [ -n "$filename" ]; then
	exec 1>"$filename"
fi
echo -n "${header%---}"
echo -n "${body%---}"
