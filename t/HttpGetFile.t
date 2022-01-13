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

# We can only verify specific error messages with a known locale.
my $english_locale = (Win32::FormatMessage(1) eq "Incorrect function.\r\n");

# We may not always have an internet connection, so don't
# attempt remote connections unless the user has done
#   set PERL_WIN32_INTERNET_OK=1
plan tests => $ENV{PERL_WIN32_INTERNET_OK} ? 20 : 7;

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
if ($english_locale) {
    ok($message, "The URL does not use a recognized protocol\r\n", "correct bad protocol message");
}
else {
    skip("Cannot verify error on non-English locale setting");
}
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
    ok($LastError - 1e9, '404', 'Correct 404 HTTP status for not found');
    if ($english_locale) {
        ok($message, 'Not Found', 'Should get text of 404 message');
    }
    else {
        skip("Cannot verify error on non-English locale setting");
    }
    # Since all GitHub downloads use redirects, we can test that they work.
    1 while unlink $tmpfile;
    ok(Win32::HttpGetFile('https://github.com/perl-libwin32/win32/archive/refs/tags/v0.57.zip', $tmpfile),
       '1',
       "successfully downloaded a zipball via redirect");

    $sha = Digest::SHA->new('sha1');
    $sha->addfile($tmpfile, 'b');
    ok($sha->hexdigest,
       '9d282e2292e67fb2e25422dfb190474e30a38de3',
       "downloaded GitHub zip archive has correct digest");

    ok(HttpGetFile('https://self-signed.badssl.com/index.html', 'NUL:'),
       '',
       'Cannot download from site with self-signed cert without ignoring cert errors');
    ok($LastError, '12175', "correct code for ERROR_WINHTTP_SECURE_FAILURE with self-signed certificate");
    ok(HttpGetFile('https://self-signed.badssl.com/index.html', 'NUL:', 1),
       '1',
       'Can download from site with self-signed cert using ignore cert errors parameter');

    ok(HttpGetFile('https://expired.badssl.com/index.html', 'NUL:'),
       '',
       'Cannot download from site with expired cert without ignoring cert errors');
    ok($LastError, '12175', "correct code for ERROR_WINHTTP_SECURE_FAILURE with expired certificate");
    ok(HttpGetFile('https://expired.badssl.com/index.html', 'NUL:', 1),
       '1',
       'Can download from site with expired cert using ignore cert errors parameter');
}
