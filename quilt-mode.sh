_libdir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

alias q=quilt

qfmake () {
	local targets i

	for i in "$@" $(quilt files | sed -n -e 's/.c$/.o/p'); do
		targets+=("$i")
	done

	if [ ${#targets[@]} -gt 0 ]; then
		make "${targets[@]}"
	fi
}

qgoto () {
	if command=$("$_libdir"/qgoto.py "$@"); then
		quilt $command
	fi
}

unset _references _destination
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
