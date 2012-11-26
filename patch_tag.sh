#!/bin/bash

# countkeys <key>
countkeys () {
	local key=$1
	grep -i "^$key: " | wc -l
}

# tag_get <key>
tag_get () {
	local key=$1

	local header=$(cat)
	local nb=$(countkeys "$key" <<< "$header")
	if [ $nb -gt 1 ]; then
		echo "Error: key \"$key\" present more than once." > /dev/stderr
		exit 1
	fi

	awk '
		tolower($1) ~ /'"${key,,*}"':/ {
			split($0, array, FS, seps)
			print substr($0, 1 + length(seps[0]) + length(array[1]) + length(seps[1]))
			exit
		}
	' <<< "$header"
}

# tag_extract <key>
tag_extract () {
	local key=$1

	local header=$(cat)
	local nb=$(countkeys "$key" <<< "$header")
	if [ $nb -gt 1 ]; then
		echo "Error: key \"$key\" present more than once." > /dev/stderr
		exit 1
	fi

	awk '
		tolower($1) ~ /'"${key,,*}"':/ {
			next
		}

		{
			print
		}
	' <<< "$header"
}

# tag_add <key> <value>
tag_add () {
	local key=$1
	local value=$2

	case "${key,,*}" in
	git-commit | patch-mainline | references)
		local header=$(cat)
		local nb=$(countkeys "$key" <<< "$header")
		if [ $nb -gt 0 ]; then
			echo "Error: key \"$key\" already present." > /dev/stderr
			exit 1
		fi

		awk '
			BEGIN {
				added = 0
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
	acked-by | signed-off-by)
		awk '
			BEGIN {
				attributions_seen = 0
				added = 0
			}

			$1 ~ /Signed-off-by:/ || $1 ~ /Acked-by:/ {
				attributions_seen = 1
			}

			attributions_seen && !added && (/^$/ || /^---$/) {
				print "'"$key"': '"$value"'"
				print
				added = 1
				next
			}

			{
				print
			}

			END {
				if (!added) {
					print "'"$key"': '"$value"'"
				}
			}

		'
		;;
	*)
		echo "Error: I don't know where to add a tag of type \"$key\"." > /dev/stderr
		exit 1
	esac
}

# tag_get_attributions
tag_get_attributions () {
	awk '
		$1 ~ /Signed-off-by:/ || $1 ~ /Acked-by:/ {
			split($0, array, FS, seps)
			print substr($0, 1 + length(seps[0]) + length(array[1]) + length(seps[1]))
		}
	'
}
