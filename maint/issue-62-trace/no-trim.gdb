# Control run: disable dlmalloc heap trimming before any HttpGetFile
# call, then let bug.p print its own results. If bar reports 12006 here,
# the clobber goes through dlfree's sys_trim -> sbrk -> VirtualFree path.
set pagination off
set confirm off
# Win32.dll is loaded at runtime by DynaLoader, so the breakpoint must
# stay pending until then.
set breakpoint pending on
break w32_HttpGetFile
run

# dlmalloc mallopt parameter -1 is M_TRIM_THRESHOLD; INT_MAX disables trim.
print (int) mallopt (-1, 2147483647)
delete
continue
