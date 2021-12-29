use strict;
use warnings;
use Test;
use Win32;
use Digest::SHA;
use POSIX qw(locale_h);
setlocale(LC_ALL, "C"); # to make error messages predictable

my $tmpfile = "http-download-test-$$.tgz";
END { 1 while unlink $tmpfile; }

unless (defined &Win32::HttpGetFile) {
    print "1..0 # Skip: gcc before 4.8 does not have winhttp library\n";
    exit;
}

# We may not always have an internet connection, so don't
# attempt remote connections unless the user has done
#   set PERL_WIN32_INTERNET_OK=1
plan tests => $ENV{PERL_WIN32_INTERNET_OK} ? 12 : 7;

# On Cygwin the test_harness will invoke additional Win32 APIs that
# will reset the Win32::GetLastError() value, so capture it immediately.
my $LastError;
sub HttpGetFile {
    my $ok = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    return $ok;
}

sub HttpGetFileList {
    my ($ok, $message) = Win32::HttpGetFile(@_);
    $LastError = Win32::GetLastError();
    return ($ok, $message);
}

ok(HttpGetFile('nonesuch://example.com', 'NUL:'), "", "'nonesuch://' is not a real protocol");
ok($LastError, '12006', "correct error code for unrecognized protocol");
ok(HttpGetFile('http://!#@!&@$', 'NUL:'), "", "invalid URL");
ok($LastError, '12005', "correct error code for invalid URL");

my ($ok, $message) = HttpGetFileList('nonesuch://example.com', 'NUL:');
ok($ok, "", "'nonesuch://' is not a real protocol");
ok($message, "The URL does not use a recognized protocol\r\n", "correct bad protocol message");
ok($LastError, '12006', "correct error code for unrecognized protocol with list context return");

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

    my ($ok, $message) = HttpGetFileList('https://cpan.metacpan.org/authors/id/Z/ZZ/ZILCH/nonesuch.tar.gz', 'NUL:');
    ok($ok, '', 'Download of nonexistent file from real site should fail with 404');
    ok($message, 'Not Found', 'Should get text of 404 message');

    # Since all GitHub downloads use redirects, we can test that they work.
    ok(Win32::HttpGetFile('https://github.com/perl-libwin32/win32/archive/refs/tags/v0.57.zip', $tmpfile),
       '1',
       "successfully downloaded a zipball via redirect");
}
