# 
# Check that the webcheck script executes without error, and can properly read
# its configuration file.

use strict;

use Test::More tests => 3;

# Test that webcheck compiles and executes without error. If that does not
# happen, bail out because none of the other tests will be able to run.

my $result = `script/webcheck --file=t/test.yml 2>&1 test`;

my $check = $result =~ /^Check OK/;

unless ( $check )
{
    print STDERR $result;
}

ok($check, 'webcheck executes successfully') ||
    BAIL_OUT("webcheck does not execute successfully");

# Test the default configuration file name, which is webcheck.yml in the current
# directory. This also tests that all checks are run by default in the order specified.

$result = `cd t; ../script/webcheck 2>&1`;

$check = $result eq <<END_CHECK;
Check OK test1, test2, test4, test3
OK test1
OK test2
OK test4
OK test3
END_CHECK

unless ( $check )
{
    print STDERR $result;
};

ok($check, 'default configuration file');

# Test that a missing configuration file produces an appropriate error message.

$result = `script/webcheck -f t/missing.yml 2>&1 test`;

like($result, qr/^Error: could not read/i, 'missing configuration file');

