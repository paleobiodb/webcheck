# 
# Check that notify, report, and check modes work properly with url checks.

use strict;

use Test::More tests => 9;

subtest 'setup' => sub {
    
    my $check;
    
    # Remove all symlinks, log files, and state files used by the files in this
    # test, in case they are left over from a previous aborted test run.
    
    &unlink_testfiles;
    
    # Start with urltest.data pointing to a good result.
    
    $check = symlink 't/urltest.good', 'urltest.data';
    
    ok($check, 'create symlink to test data') ||
	BAIL_OUT("could not create necessary symlink");
};


subtest 'notify ok' => sub {
    
    my $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    my $check = $result =~ /^Notify OK test service[\n\r]+OK test service[\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify reported OK');
    
    $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    is($result, '', 'notify result was empty');
};


subtest 'log file' => sub {
    
    ok(-e 'logs/urltest.log', 'log file created') || return;
    
    my $result = `cat logs/urltest.log`;
    
    like($result, qr/\d\d:\d\d.*OK test service$/m, 'found OK recorded in log');
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 2, 'log file records both notifications');
};


subtest 'state file' => sub {
    
    ok(-e 'logs/urltest_state.txt', 'urltest state file created') || return;
    
    my $result = `cat logs/urltest_state.txt`;
    
    like($result, qr/ ^ OK [|] \d+ [|] 0 [|] 200 [|] test \s service $ /xs,
	 'state file content');
};


subtest 'cookie' => sub {

    my $result = `script/webcheck -rf t/test2.yml urltest 2>&1`;

    my $check = $result =~ /^Report OK/;

    print STDERR $result unless $check;
    
    ok($check, 'cookie arguemnt ok');
};


subtest 'notify down' => sub {
    
    # Relink urltest.data to point to a bad result.
    
    unlink 'urltest.data';
    symlink 't/urltest.bad', 'urltest.data';
    
    my $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    my $check = $result =~ /^Notify DOWN test service[\n\r]+DOWN test service [(]504[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify produced DOWN');
    
    $result = `cat logs/urltest.log`;
    
    like($result, qr/\d\d:\d\d.*OK test service$/m, 'found OK remaining in log');
    
    like($result, qr/\d\d:\d\d.*DOWN test service [(]504[)]$/m, 'found DOWN recorded in log');
};


subtest 'followups' => sub {
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    my $check = $result =~ /^Notify DOWN test service[\n\r]+DOWN test service [12]s [(]504[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'followup on second notification');
    
    $result = `script/webcheck -rf t/test.yml urltest 2>&1`;
    
    $check = $result =~ /^Report DOWN test service[\n\r]+DOWN test service [12]s [(]504[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'report produces proper output');
    
    $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    print STDERR $result if $result;
    
    is($result, '', 'third notification produces empty');
    
    $result = `script/webcheck --report -f t/test.yml urltest 2>&1`;
    
    $check = $result =~ /^Report DOWN test service[\n\r]+DOWN test service [12]s [(]504[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'second report produces proper output');
    
    $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    $check = $result =~ /^Notify DOWN test service[\n\r]+DOWN test service [12]s [(]504[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    ok($check, 'fourth notification produces followup');
    
    $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    print STDERR $result if $result;
    
    is($result, '', 'fifth notification produces empty');
};


subtest 'no response' => sub {
    
    # Relink urltest.data again to point to an empty result. This should produce
    # the code NOR for "no response".
    
    unlink 'urltest.data';
    symlink 't/urltest.noresp', 'urltest.data';
    
    my $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    my $check = $result =~ /^Notify DOWN test service[\n\r]+DOWN test service [12]s [(]NOR[)][\n\r]+$/s;
    
    print STDERR $result unless $check;
    
    # This tests two things:
    # 
    # 1. That change of status produces a notification
    # 2. That an empty url_command response produces the code NOR.
    
    ok($check, 'no response notification');
    
    $result = `script/webcheck -nf t/test.yml urltest 2>&1`;
    
    # This tests that a change of status does not reset the followup count.
    
    is($result, '', 'additional notification produces empty');
};


subtest 'cleanup' => sub {
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


sub unlink_testfiles {
    
    unlink('logs/urltest.log', 'logs/urltest_state.txt', 'urltest.data');

}
