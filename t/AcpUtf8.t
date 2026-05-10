use strict;
use warnings;
use Test::More;
use Encode ();
use Win32;

# Functions that wrap *A Windows APIs (or convert wide strings via
# CP_ACP) return ACP-encoded bytes. When GetACP() == CP_UTF8 (set via
# "Use Unicode UTF-8 for worldwide language support" or an app
# manifest), those bytes are valid UTF-8 and the SV must carry the
# SvUTF8 flag — otherwise concatenation with a Unicode string upgrades
# each byte as Latin-1 and produces mojibake.
#
# Each test below asserts the flag matches GetACP(). The byte content
# depends on system locale (a German runner returns German strings, an
# English one returns English), but the flag invariant is universal.

my $acp = Win32::GetACP();
my $expect_flag = $acp == 65001;

diag(sprintf "Win32::GetACP() = %d (%s ACP); expecting SvUTF8 flag %s",
     $acp, $expect_flag ? 'UTF-8' : 'legacy',
     $expect_flag ? 'ON' : 'OFF');

sub flag_matches {
    my ($label, $val) = @_;
    SKIP: {
        skip "$label returned undef", 1 unless defined $val;
        my $flagged = utf8::is_utf8($val);
        my $ok = is(!!$flagged, !!$expect_flag,
                    "$label: SvUTF8 matches GetACP() == 65001");
        unless ($ok) {
            my $bytes = $flagged ? Encode::encode_utf8($val) : $val;
            diag(sprintf "  value: bytes=%d hex=%s repr=%s",
                 length($bytes), unpack("H*", $bytes), $val);
        }
    }
}

flag_matches("Win32::NodeName",          Win32::NodeName());
flag_matches("Win32::DomainName",        Win32::DomainName());
flag_matches("Win32::FsType",            scalar Win32::FsType());
flag_matches("Win32::LoginName",         Win32::LoginName());
flag_matches("Win32::FormatMessage(2)",  Win32::FormatMessage(2));

# S-1-1-0 = Everyone (well-known SID, present on every Windows host).
# IdentifierAuthority is 6 big-endian bytes; SubAuthority is little-endian.
my $sid_everyone = pack("CC", 1, 1)             # Revision, SubAuthorityCount
                 . "\x00\x00\x00\x00\x00\x01"   # IdentifierAuthority = 1
                 . pack("V", 0);                # SubAuthority[0] = 0

my ($acct, $dom, $type);
SKIP: {
    skip "LookupAccountSID(Everyone) failed: $^E", 2
        unless Win32::LookupAccountSID("", $sid_everyone, $acct, $dom, $type);
    flag_matches("LookupAccountSID(Everyone) name",   $acct);
    flag_matches("LookupAccountSID(Everyone) domain", $dom);
}

done_testing;
