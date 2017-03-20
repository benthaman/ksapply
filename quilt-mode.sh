_libdir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_libdir"/lib.sh

alias q=quilt

_switcheroo () {
	if [ -r series ] &&
		head -n1 series | grep -qv "^# Kernel patches configuration file$" &&
		[ -r patches/series.conf ] &&
		head -n1 patches/series.conf | grep -q "^# Kernel patches configuration file$"; then
		ln -sf patches/series.conf series
	fi
}
_switcheroo


qfmake () {
	local targets i

	for i in "$@" $(quilt files | sed -n -e 's/.c$/.o/p'); do
		targets+=("$i")
	done

	if [ ${#targets[@]} -gt 0 ]; then
		make "${targets[@]}"
	fi
}


qf1 () {
	cat $(quilt top)
}


qgoto () {
	if command=$("$_libdir"/qgoto.py "$@"); then
		quilt $command
	fi
}


qdupcheck () {
	"$_libdir"/qdupcheck.py "$@"
}


#unset _references _destination
qcp () {
	# capture and save some options
	local r_set d_set
	local args
	while [ "$1" ] ; do
		case "$1" in
			-r|--references)
				_references=$2
				args+=($1 "$2")
				r_set=1
				shift
				;;
			-d|--destination)
				_destination=$2
				args+=($1 "$2")
				d_set=1
				shift
				;;
			*)
				args+=($1)
				shift
				;;
		esac
		shift
	done

	if [ -z "$r_set" -a "$_references" ]; then
		args=(-r "$_references" "${args[@]}")
	fi

	if [ -z "$d_set" -a "$_destination" ]; then
		args=(-d "$_destination" "${args[@]}")
	fi

	"$_libdir"/qcp.py "${args[@]}"
}


# Save -r and -d for later use by qcp
_saveopts () {
	local result=$(getopt -o hr:d: --long help,references:,destination: -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		return 1
	fi

	eval set -- "$result"

	while true ; do
		case "$1" in
			-h|--help)
				echo "Usage: ${FUNCNAME[1]} [options]"
				echo ""
				echo "Options:"
				echo "    -r, --references <value>    bsc# or FATE# number used to tag the patch file."
				echo "    -d, --destination <dir>     Destination \"patches.xxx\" directory."
				echo "    -h, --help                  Print this help"
				return 1
				;;
			-r|--references)
				_references=$2
				shift
				;;
			-d|--destination)
				_destination=$2
				shift
				;;
			--)
				shift
				break
				;;
			*)
				echo "Error: could not parse arguments" >&2
				return 1
				;;
		esac
		shift
	done
}


#unset series
qadd () {
	if [ $BASH_SUBSHELL -gt 0 ]; then
		echo "Error: it looks like this function is being run in a subshell. It will not be effective because its purpose is to set an environment variable. You could run it like this instead: \`${FUNCNAME[0]} <<< \$(<cmd>)\`." > /dev/stderr
		return 1
	fi

	if [ ! -d "$LINUX_GIT" ] || ! GIT_DIR="$LINUX_GIT"/.git git log -n1 > /dev/null; then
		echo "Error: kernel git tree not found at \"$LINUX_GIT\" (check the LINUX_GIT environment variable)" > /dev/stderr
		return 1
	fi

	if ! _saveopts "$@"; then
		return
	fi

	local _series=$(grep .)

	mapfile -t series <<< $(
		(
			[ ${#series[@]} -gt 0 ] && printf "%s\n" "${series[@]}"
			[ -n "$_series" ] && echo "$_series"
		) | GIT_DIR="$LINUX_GIT"/.git git sort
	)
}


qedit () {
	if [ ! -d "$LINUX_GIT" ] || ! GIT_DIR="$LINUX_GIT"/.git git log -n1 > /dev/null; then
		echo "Error: kernel git tree not found at \"$LINUX_GIT\" (check the LINUX_GIT environment variable)" > /dev/stderr
		return 1
	fi

	if [ "${tmpfile+set}" = "set" ]; then
		local _tmpfile=$tmpfile
	fi

	trap '[ -n "$tmpfile" -a -f "$tmpfile" ] && rm "$tmpfile"' EXIT
	tmpfile=$(mktemp --tmpdir qedit.XXXXXXXXXX)
	[ ${#series[@]} -gt 0 ] && printf "%s\n" "${series[@]}" > "$tmpfile"

	${EDITOR:-${VISUAL:-vi}} "$tmpfile"

	mapfile -t series <<< $(grep . "$tmpfile" | GIT_DIR="$LINUX_GIT"/.git git sort)

	if [ -z "${series[0]}" ]; then
		unset series[0]
	fi

	rm "$tmpfile"
	if [ "${_tmpfile+set}" = "set" ]; then
		tmpfile=$_tmpfile
	else
		unset tmpfile
	fi
	trap - EXIT
}


qcat () {
	[ ${#series[@]} -gt 0 ] && printf "%s\n" "${series[@]}"
}


qnext () {
	[ ${#series[@]} -gt 0 ] && echo "${series[0]}" |
		sed -re 's/^[[:space:]]+//'
}


qskip () {
	if [ ${#series[@]} -gt 0 ]; then
		local entry=${series[0]}
		series=("${series[@]:1}")
		echo "Skipped: ${entry##[ 	]}"
		if [ ${#series[@]} -gt 0 ]; then
			echo "Next:    ${series[0]##[ 	]}"
		else
			echo "No more entries"
		fi
	else
		return 1
	fi
}


qdoit () {
	local entry=$(qnext | awk '{print $1}')
	while [ "$entry" ]; do
		local command retval
		command=$("$_libdir"/qgoto.py "$entry")
		retval=$?
		if [ $retval -eq 1 ]; then
			echo "Error: qgoto.py exited with an error" > /dev/stderr
			return 1
		fi
		while [ $retval -ne 2 ]; do
			if ! quilt $command; then
				echo "\`quilt $command\` did not complete sucessfully. Please examine the situation." > /dev/stderr
				return 1
			fi

			command=$("$_libdir"/qgoto.py $entry)
			retval=$?
			if [ $retval -eq 1 ]; then
				echo "Error: qgoto.py exited with an error" > /dev/stderr
				return 1
			fi
		done

		if ! qdupcheck $entry; then
			echo "The next commit is already present in the series. Please examine the situation." > /dev/stderr
			return 1
		fi

		if ! qcp $entry; then
			echo "\`qcp $entry\` did not complete sucessfully. Please examine the situation." > /dev/stderr
			return 1
		fi
		series=("${series[@]:1}")

		if ! quilt push; then
			echo "The last commit did not apply successfully. Please examine the situation." > /dev/stderr
			return 1
		fi

		if ! qfmake "$@"; then
			echo "The last applied commit results in a build failure. Please examine the situation." > /dev/stderr
			return 1
		fi

		entry=$(qnext | awk '{print $1}')
	done
}
