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

$check = $result =~ /^Check OK[\n\r]+OK test1[\n\r]+OK test2[\n\r]+OK test4[\n\r]+OK test3[\n\r]+$/s;

unless ( $check )
{
    print STDERR $result;
};

ok($check, 'default configuration file');

# Test that a missing configuration file produces an appropriate error message.

$result = `script/webcheck -f t/missing.yml 2>&1 test`;

like($result, qr/^Error: could not read/i, 'missing configuration file');

