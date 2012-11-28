#!/usr/bin/awk -f

NR==1 && /^From [0-9a-f]+/ {
	next
}

{
	print
}
