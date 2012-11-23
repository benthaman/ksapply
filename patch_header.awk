#!/usr/bin/awk

# from quilt's patchfns

/^(---|\*\*\*|Index:)[ \t][^ \t]|^diff -/ {
	exit
}

{
	print
}

