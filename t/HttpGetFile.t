use strict;
use warnings;
use Test;
use Win32;
use Digest::SHA;

my $tmpfile = "http-download-test-$$.tgz";
END { 1 while unlink $tmpfile; }

unless (defined &Win32::HttpGetFile) {
    print "1..0 # Skip: gcc before 4.8 does not have winhttp library\n";
    exit;
}

# We may not always have an internet connection, so don't
# attempt remote connections unless the user has done
#   set PERL_WIN32_INTERNET_OK=1
plan tests => $ENV{PERL_WIN32_INTERNET_OK} ? 6 : 4;

# On Cygwin the test_harness will invoke additional Win32 APIs that
# will reset the Win32::GetLastError() value, so capture it immediately.
my $LastError;
sub HttpGetFile {
    my $ok = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    return $ok;
}

ok(HttpGetFile('nonesuch://example.com', 'NUL:'), "", "'nonesuch://' is not a real protocol");
ok($LastError, '12006', "correct error code for unrecognized protocol");
ok(HttpGetFile('http://!#@!&@$', 'NUL:'), "", "invalid URL");
ok($LastError, '12005', "correct error code for invalid URL");

if ($ENV{PERL_WIN32_INTERNET_OK}) {
    # The digest for version 0.57 should obviously stay the same even after new versions are released
    ok(Win32::HttpGetFile('https://cpan.metacpan.org/authors/id/J/JD/JDB/Win32-0.57.tar.gz', $tmpfile),
       '1',
       "successfully downloaded a tarball");

    my $sha = Digest::SHA->new('sha1');
    $sha->addfile($tmpfile, 'b');
    ok($sha->hexdigest,
       '44a6d7d1607d7267b0dbcacbb745cec204f1c1a4',
       "downloaded tarball has correct digest");
}