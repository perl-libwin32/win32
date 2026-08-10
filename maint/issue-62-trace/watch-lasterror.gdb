# Hardware watchpoint on the TEB's LastErrorValue (TEB+0x68 on x64),
# armed at the first list-context SetLastError in w32_HttpGetFile.
# Every later write prints a backtrace naming the code that changed it.
set pagination off
set confirm off
# Win32.dll is loaded at runtime by DynaLoader, so the breakpoint must
# stay pending until then.
set breakpoint pending on

# Win32.xs:2018 is the XSRETURN(2) in the G_ARRAY branch, one line after
# SetLastError(error); the first hit is bar's call (foo takes G_SCALAR).
break Win32.xs:2018
run

python
import re
out = gdb.execute("info w32 thread-information-block", to_string=True)
m = re.search(r"0x[0-9a-fA-F]+", out)
if not m:
    gdb.write("cannot find TEB address in:\n" + out + "\n")
    gdb.execute("quit 2")
gdb.execute("set $lasterr = (unsigned int *)(" + m.group(0) + " + 0x68)")
end
printf "TEB LastErrorValue at %p, value now: %u\n", $lasterr, *$lasterr

watch -l *$lasterr
commands
  silent
  printf "\n=== LastErrorValue -> %u ===\n", *$lasterr
  bt 12
  continue
end

commands 1
  silent
  printf "\n--- list-context SetLastError site reached again ---\n"
  continue
end

continue
