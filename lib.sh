# var_override [options] <var name> <value> <source name>
# Options:
#    -a, --allow-empty    Allow an empty "value" to override the value of "var"
var_override () {
	local temp=$(getopt -o a --long allow-empty -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	local opt_empty

	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		exit 1
	fi

	eval set -- "$temp"

	while true ; do
		case "$1" in
			-a|--allow-empty)
						opt_empty=1
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

	local name=$1
	local value=$2
	local src=$3

	if [ -n "$value" -o "$opt_empty" ]; then
		local name_src=_${name}src
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

# expand_git_ref [options]
# Options:
#    -q, --quiet          Do not error out if a refspec is not found, just print an empty line
expand_git_ref () {
	local temp=$(getopt -o q --long quiet -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	local opt_quiet

	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		exit 1
	fi

	eval set -- "$temp"

	while true ; do
		case "$1" in
			-q|--quiet)
						opt_quiet=1
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

	local commit

	while read commit; do
		if [ -n "$commit" ]; then
			# take the first word only, which will discard cruft
			# like "(partial)"
			commit=$(echo "$commit" | awk '{print $1}')
			if [ -z "$opt_quiet" ]; then
				local hash=$(git log -n1 --pretty=format:%H "$commit")
			else
				local hash=$(git log -n1 --pretty=format:%H "$commit" 2>/dev/null || true)
			fi
			echo $hash
		fi
	done
}
