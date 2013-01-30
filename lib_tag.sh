# countkeys <key>
countkeys () {
	local key=$1

	case "${key,,*}" in
	"cherry picked from commit")
		grep -iF "(cherry picked from commit " | wc -l
		;;
	*)
		grep -i "^$key: " | wc -l
		;;
	esac
}

# tag_position <key>
tag_position () {
	local key=$1

	local header=$(cat)
	local nb=$(countkeys "$key" <<< "$header")
	if [ $nb -gt 1 ]; then
		echo "Error: key \"$key\" present more than once." > /dev/stderr
		exit 1
	fi

	awk '
		tolower($1) ~ /'"${key,,*}"':/ {
			print NR
			exit
		}
	' <<< "$header"
}

# tag_get [options] <key>
# Options:
#    -l, --last           Do not error out if a tag is present more than once,
#                         return the last occurance
tag_get () {
	local temp=$(getopt -o l --long last -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	local opt_last

	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		exit 1
	fi

	eval set -- "$temp"

	while true ; do
		case "$1" in
			-l|--last)
						opt_last=1
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

	local key=$1

	local header=$(cat)
	local nb=$(countkeys "$key" <<< "$header")
	if [ $nb -gt 1 -a -z "$opt_last" ]; then
		echo "Error: key \"$key\" present more than once." > /dev/stderr
		exit 1
	fi

	case "${key,,*}" in
	subject)
		awk --assign nb="$nb" '
			BEGIN {
				insubject = 0
			}

			tolower($1) ~ /subject:/ {
				nb--
				if (nb > 0) {
					next
				}
				insubject = 1
				split($0, array, FS, seps)
				result = substr($0, 1 + length(seps[0]) + length(array[1]) + length(seps[1]))
				next
			}

			insubject && /^[ \t]/ {
				sub("[ \t]", " ")
				result = result $0
				next
			}

			insubject {
				print result
				exit
			}
		' <<< "$header"
		;;
	*)
		awk --assign nb="$nb" '
			tolower($1) ~ /'"${key,,*}"':/ {
				nb--
				if (nb > 0) {
					next
				}
				split($0, array, FS, seps)
				print substr($0, 1 + length(seps[0]) + length(array[1]) + length(seps[1]))
				exit
			}
		' <<< "$header"
		;;
	esac
}

# tag_extract [options] <key>
# Options:
#    -l, --last           Do not error out if a tag is present more than once,
#                         extract the last occurance
tag_extract () {
	local temp=$(getopt -o l --long last -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	local opt_last

	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		exit 1
	fi

	eval set -- "$temp"

	while true ; do
		case "$1" in
			-l|--last)
						opt_last=1
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

	local key=$1

	local header=$(cat)
	local nb=$(countkeys "$key" <<< "$header")
	if [ $nb -gt 1 -a -z "$opt_last" ]; then
		echo "Error: key \"$key\" present more than once." > /dev/stderr
		exit 1
	fi

	case "${key,,*}" in
	subject)
		awk --assign nb="$nb" '
			BEGIN {
				insubject = 0
			}

			tolower($1) ~ /subject:/ {
				nb--
				if (nb == 0) {
					insubject = 1
					next
				}
			}

			insubject && /^ / {
				next
			}

			insubject {
				insubject = 0
			}

			{
				print
			}
		' <<< "$header"
		;;
	*)
		awk --assign nb="$nb" '
			tolower($1) ~ /'"${key,,*}"':/ {
				nb--
				if (nb == 0) {
					next
				}
			}

			{
				print
			}
		' <<< "$header"
		;;
	esac
}

# tag_add [options] <key> <value>
# Options:
#    -l, --last           Do not error out if a tag is already present, add it
#                         after the last occurance
tag_add () {
	local temp=$(getopt -o l --long last -n "${BASH_SOURCE[0]}:${FUNCNAME[0]}()" -- "$@")
	local opt_last

	if [ $? != 0 ]; then
		echo "Error: getopt error" >&2
		exit 1
	fi

	eval set -- "$temp"

	while true ; do
		case "$1" in
			-l|--last)
						opt_last=1
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

	local key=$1
	local value=$2

	case "${key,,*}" in
	from)
		local header=$(cat)
		local nb=$(countkeys "$key" <<< "$header")
		if [ $nb -gt 0 -a -z "$opt_last" ]; then
			echo "Error: key \"$key\" already present." > /dev/stderr
			exit 1
		fi

		awk --assign key="$key" --assign value="$value" --assign nb="$nb" '
			BEGIN {
				inserted = 0
			}

			NR == 1 && /^From [0-9a-f]+/ {
				print
				next
			}

			nb == 0 && !inserted {
				print key ": " value
				print
				inserted = 1
				next
			}

			tolower($1) ~ /'"${key,,*}"':/ {
				nb--
			}

			{
				print
			}
		' <<< "$header"
		;;
	date | subject)
		local header=$(cat)
		local nb=$(countkeys "$key" <<< "$header")
		if [ $nb -gt 0 ]; then
			echo "Error: key \"$key\" already present." > /dev/stderr
			exit 1
		fi

		local -A prevkey=(["date"]="from" ["subject"]="date")

		nb=$(countkeys "${prevkey[${key,,*}]}" <<< "$header")

		awk --assign key="$key" --assign value="$value" --assign nb="$nb" '
			{
				print
			}

			tolower($1) ~ /'"${prevkey[${key,,*}]}"':/ {
				nb--
				if (nb == 0) {
					print key ": " value
				}
			}
		' <<< "$header"
		;;
	patch-mainline | git-repo | git-commit | references)
		local header=$(cat)
		local nb=$(countkeys "$key" <<< "$header")
		if [ $nb -gt 0 -a -z "$opt_last" ]; then
			echo "Error: key \"$key\" already present." > /dev/stderr
			exit 1
		fi

		awk '
			BEGIN {
				added = 0
				keys["Patch-mainline:"] = 1
				keys["Git-repo:"] = 2
				keys["Git-commit:"] = 3
				keys["References:"] = 4
			}

			function keycmp(key1, key2) {
				return keys[key1] - keys[key2]
			}
			
			$1 in keys && !added {
				if (keycmp("'"$key"':", $1) < 0) {
					print "'"$key"': '"$value"'"
					print
					added = 1
					next
				}
			}

			/^$/ && !added {
				print "'"$key"': '"$value"'"
				print
				added = 1
				next
			}

			{
				print
			}
		' <<< "$header"
		;;
	acked-by | signed-off-by | "cherry picked from commit")
		local line
		local header=$(cat)

		if [ "${key,,*}" = "cherry picked from commit" ]; then
			local nb=$(countkeys "$key" <<< "$header")
			if [ $nb -gt 0 ]; then
				echo "Error: key \"$key\" already present." > /dev/stderr
				exit 1
			fi

			line="(cherry picked from commit $value)"
		else
			line="$key: $value"
		fi

		awk --assign line="$line" '
			BEGIN {
				attributions_seen = 0
				added = 0
			}

			$1 ~ /Signed-off-by:/ {
				attributions_seen = 1
			}

			attributions_seen && !added && /^$/ || /^---$/ {
				print line
				print
				added = 1
				next
			}

			{
				print
			}

			END {
				if (!added) {
					print line
				}
			}

		' <<< "$header"
		;;
	*)
		echo "Error: I don't know where to add a tag of type \"$key\"." > /dev/stderr
		exit 1
	esac
}

# tag_get_attribution_names
tag_get_attribution_names () {
	awk '
		$1 ~ /Signed-off-by:/ || $1 ~ /Acked-by:/ {
			split($0, array, FS, seps)
			print substr($0, 1 + length(seps[0]) + length(array[1]) + length(seps[1]))
		}
	'
}

# tag_get_attribution_block
tag_get_attribution_block () {
	awk '
		BEGIN {
			inattributions = 0
		}

		$1 ~ /Signed-off-by:/ || $1 ~ /Acked-by:/ || $1 ~ /Tested-by:/ || $1 ~ /Reported-by:/ || tolower($1) ~ /cc:/ {
			inattributions = 1
		}

		inattributions && (/^$/ || /^---$/) {
			inattributions = 0
		}

		inattributions {
			print
		}
	'
}

# tag_replace_attribution_block <new content>
tag_replace_attribution_block () {
	local content=$1

	awk --assign content="$content" '
		BEGIN {
			inattributions = 0
			added = 0
		}

		$1 ~ /Signed-off-by:/ || $1 ~ /Acked-by:/ || $1 ~ /Tested-by:/ || $1 ~ /Reported-by:/ || tolower($1) ~ /cc:/ {
			inattributions = 1
		}

		inattributions && (/^$/ || /^---$/) {
			inattributions = 0
			print content
			added = 1
		}

		! inattributions {
			print
		}

		END { 
			if (!added) {
				print content
			}
		}
	'
}
