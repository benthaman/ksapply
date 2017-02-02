_libdir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_libdir"/lib.sh
. "$_libdir"/lib_tag.sh


# read a list of commits and set it in a "series" environment variable
# bpset [path of interest for cherry-pick...]
bpset () {
	if [ $BASH_SUBSHELL -gt 0 ]; then
		echo "Error: it looks like this function is being run in a subshell. It will not be effective because its purpose is to set an environment variable. You could run it like this instead: \`${FUNCNAME[0]} <<< \$(<cmd>)\`." > /dev/stderr
		return 1
	fi
	paths_of_interest=$(
		for arg in "$@"; do
			echo "$arg"
		done
	)
	local _series
	if _series=$(cat | expand_git_ref); then
		series=$_series
	else
		return 1
	fi
}

# show the first entry in the series
bpnext () {
	if [ -n "$series" ]; then
		git log -n1 --oneline $(echo "$series" | head -n1)
	fi
}
alias bptop=bpnext

bpref () {
	echo "$series" | head -n1
}

bpstat () {
	if [ -n "$series" ]; then
		git log -n1 --stat $(echo "$series" | head -n1)
	fi
}

bpf1 () {
	if [ -n "$series" ]; then
		git f1 $(echo "$series" | head -n1)
	fi
}

bpskip () {
	if [ $BASH_SUBSHELL -gt 0 ]; then
		echo "Error: it looks like this function is being run in a subshell. It will not be effective because its purpose is to set an environment variable." > /dev/stderr
		return 1
	fi
	previous=$(bpref)
	series=$(awk 'NR > 1 {print}' <<< "$series")
}

bpcherry-pick-all () {
	bpskip
	git cherry-pick -x $previous
}
alias bpcp=bpcherry-pick-all

bpaddtag () {
	git log -n1 --pretty=format:%B | tag_add "cherry picked from commit" "$previous" | git commit -q --amend -F -
}

# bpcherry-pick-include <path...>
bpcherry-pick-include () {
	local args=$(
		for arg in "$@"; do
			echo "--include \"$arg\""
		done
		while read path; do
			echo "--include \"$path\""
		done <<< "$paths_of_interest"
	)
	args=$(echo "$args" | xargs -d"\n")

	bpskip
	local patch=$(git format-patch --stdout $previous^..$previous)
	local files=$(echo "$patch" | eval "git apply --numstat $args" | cut -f3)
	if echo "$patch" | eval "git apply --reject $args"; then
		echo "$files" | xargs -d"\n" git add 
		git commit -C $previous
		bpaddtag
	fi
}
alias bpcpi=bpcherry-pick-include

bpreset () {
	git reset --hard
	git ls-files -o --exclude-standard | xargs rm
}
alias bpclean=bpreset

# Check that the patch passed via stdin touches only paths_of_interest
_poicheck () {
	local args=$(
		while read path; do
			echo "--exclude \"$path\""
		done <<< "$paths_of_interest"
	)
	args=$(echo "$args" | xargs -d"\n")

	eval "git apply --numstat $args" | wc -l | grep -q "^0$"
}

_jobsnb=$(($(cat /proc/cpuinfo | grep "^processor\>" | wc -l) * 2))

bpdoit () {
	if [ $# -lt 1 ]; then
		echo "If you want to do it, you must specify build paths!" > /dev/stderr
		echo "Usage: ${FUNCNAME[0]} <build path>..." > /dev/stderr
		return 1
	fi

	while [ $(bpref) ]; do
		if ! git format-patch --stdout $(bpref)^..$(bpref) | _poicheck; then
			echo "The following commit touches paths outside of the paths of interest. Please examine the situation." > /dev/stderr
			bpnext > /dev/stderr
			return 1
		fi

		if ! bpcp; then
			echo "The last commit did not apply successfully. Please examine the situation." > /dev/stderr
			return 1
		fi

		if ! make -j$_jobsnb "$@"; then
			echo "The last applied commit results in a build failure. Please examine the situation." > /dev/stderr
			return 1
		fi
	done
}
