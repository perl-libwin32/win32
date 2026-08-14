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
gdb.write("info w32 thread-information-block:\n" + out + "\n")
# Parse the labeled TEB base address; bare-hex heuristics matched the
# thread id once and current_seh's zeros another time.
m = re.search(r"linear_address_tib\s+is\s+(0x[0-9a-fA-F]+)", out)
if not m:
    gdb.write("cannot find TEB address above\n")
    gdb.execute("quit 2")
gdb.execute("set $lasterr = (unsigned int *)(" + m.group(1) + " + 0x68)")
end
printf "TEB LastErrorValue at %p, value now: %u\n", $lasterr, *$lasterr

watch -l *$lasterr
commands
  silent
  printf "\n=== LastErrorValue -> %u ===\n", *$lasterr
  bt 12
  continue
end

# Entry breakpoints unwind cleanly past the sigfe trampoline, naming the
# true callers the watchpoint backtraces elide. Active only during bar's
# window; breakpoint 5 disables them when the window closes.
break free
commands
  silent
  printf "\n*** free() entered ***\n"
  bt 6
  continue
end

break pthread_getspecific
commands
  silent
  printf "\n*** pthread_getspecific entered ***\n"
  info args
  bt 8
  continue
end

break w32_GetLastError
commands
  silent
  printf "\n--- window closed (Win32::GetLastError read) ---\n"
  disable 3
  disable 4
  disable 5
  continue
end

commands 1
  silent
  printf "\n--- list-context SetLastError site reached again ---\n"
  continue
end

continue
