use strict;
use warnings;

use Test;
use Win32;

plan tests => 4;

ok(ref(Win32::GetProcessPrivileges) eq 'HASH');
ok(ref(Win32::GetProcessPrivileges(Win32::GetCurrentProcessId())) eq 'HASH');

# All Windows PIDs are divisible by 4. It's an undocumented implementation
# detail, but it means it's extremely unlikely that the PID below is valid.
ok(!Win32::GetProcessPrivileges(3423237));

my $whoami = `whoami /priv 2>&1`;
my $skip = ($? == -1 || $? >> 8) ? '"whoami" command is missing' : 0;

skip($skip, sub{
    my $privs = Win32::GetProcessPrivileges();

    while ($whoami =~ /^(Se\w+)/mg) {
        return 0 unless exists $privs->{$1};
    }

    return 1;
});
