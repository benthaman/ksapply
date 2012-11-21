#!/usr/bin/awk

NR==1 && /^From [0-9a-f]+/ {
	next
}

{
	print
}
