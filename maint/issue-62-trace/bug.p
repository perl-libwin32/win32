# sisyphus's reducer from
# https://github.com/perl-libwin32/win32/issues/62#issuecomment-5229995195
use strict;
use warnings;
use Win32;

my @args = ('nonesuch://example.com', 'NUL:');
my $LastError;

foo(@args);
bar(@args);
baz(@args);

sub foo {
    my $ok = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    print "foo last error: $LastError\n";
}

sub bar {
    my($ok) = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    print "bar last error: $LastError\n";
}

sub baz {
    my ($ok, $message) = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    print "baz last error: $LastError\n";
}
