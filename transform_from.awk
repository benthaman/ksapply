#!/usr/bin/awk -f

# When patches are cherry-picked, we can use -x to record the original commit
# id. When `format-patch` is used, we can use this script to transform the
# first "From" line into at "Git-commit" tag. That tag is placed after the
# attributions, that's one place where it will be preserved by `git am`.

BEGIN {
	added = 0
}

NR==1 && /^From [0-9a-f]+/ {
	value = $2
	next
}

/^Signed-off-by:|Acked-by:|Reviewed-by:|Tested-by:|Cc:|Reported-by:/ && !added {
	print "Git-commit: " value
	print
	added = 1
	next
}

{
	print
}

END {
	if (!added) {
		print "Git-commit: " value
	}
}
