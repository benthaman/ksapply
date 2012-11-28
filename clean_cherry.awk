#!/usr/bin/awk -f

/\(cherry picked from commit [0-9a-f]+\)/ {
	sub("\\(cherry picked from commit [0-9a-f]+\\)", "")
	if (length() > 0)
		print
	next
}

{
	print
}
