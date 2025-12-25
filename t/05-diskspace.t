# 
# Check that notify, report, and check modes work properly with disk space checks.

use strict;

use Test::More tests => 12;

subtest 'setup' => sub {
    
    my $check;
    
    # Remove all symlinks, log files, and state files used by the files in this
    # test, in case they are left over from a previous aborted test run.
    
    &unlink_testfiles;
    
    # Symlink dftest.data to point to a good result.
    
    $check = symlink 't/dftest.good', 'dftest.data';
    
    ok($check, 'create symlink to test data') ||
	BAIL_OUT("could not create necessary symlink");
};


subtest 'notify ok' => sub {
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Notify OK diskspace[\n\r]+OK diskspace[\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify reported OK');
    
    $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    is($result, '', 'second notify was empty');
};


subtest 'log file' => sub {
    
    ok(-e 'logs/webcheck.log', 'log file created') || return;
    
    my $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK diskspace$/m, 'found OK recorded in log');
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 1, 'log file records one notification');
};


subtest 'state file' => sub {
    
    ok(-e 'logs/dftest_state.txt', 'dftest state file created') || return;
    
    my $result = `cat logs/dftest_state.txt`;
    
    like($result, qr/ ^ OK [|] \d+ [|] [|] diskspace $ /xs,
	 'state file content');
};


subtest 'notify warn' => sub {
    
    unlink 'dftest.data';
    symlink 't/dftest.warn', 'dftest.data';
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Notify WARN diskspace[\n\r]+WARN \ds diskspace[\n\r]+[*] \/var 90 [*][\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify produced WARN 90');
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK diskspace$/m, 'found OK remaining in log');
    
    like($result, qr/\d\d:\d\d.*WARN \ds diskspace$/m, 'found WARN recorded in log');
    
    like($result, qr/\d\d:\d\d.*\/var 90$/m, 'found /var recorded in log');
    
    $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    is($result, '', 'second notify produces empty');
};


subtest 'notify more' => sub {
    
    unlink 'dftest.data';
    symlink 't/dftest.more', 'dftest.data';
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Notify WARN diskspace[\n\r]+WARN \ds diskspace[\n\r]+[*] \/var 97 [*][\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify produced WARN 97');
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*\/var 90$/m, 'found /var 90 remaining in log');
    
    like($result, qr/\d\d:\d\d.*\/var 97$/m, 'found /var 97 recorded in log');
    
    $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    is($result, '', 'additional notify produces empty');
};


subtest 'notify most' => sub {
    
    unlink 'dftest.data';
    symlink 't/dftest.most', 'dftest.data';
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Notify WARN diskspace[\n\r]+WARN \ds diskspace[\n\r]+[*] \/var 98 [*][\n\r]+[*] \/home 95 [*][\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify produced WARN 98 95');
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*\/var 97$/m, 'found /var 90 remaining in log');
    
    like($result, qr/\d\d:\d\d.*\/var 98 - \/home 95$/m, 'found /var 98 - /home 95 recorded in log');
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 7, 'count log lines');
};


subtest 'notify decrease' => sub {

    unlink 'dftest.data';
    symlink 't/dftest.more', 'dftest.data';
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    is($result, '', 'notify produced empty output');
};


subtest 'check' => sub {
    
    unlink 'dftest.data';
    symlink 't/dftest.most', 'dftest.data';
    
    my $result = `script/webcheck -f t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Check WARN diskspace[\n\r]+WARN \ds diskspace[\n\r]+\/ 82[\n\r]+[*] \/var 98 [*][\n\r]+[*] \/home 95 [*][\n\r]+\/boot 25[\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'check produced WARN 98 95');
    
    $result = `cat logs/webcheck.log`;
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 7, 'check did not add to log');
};


subtest 'report' => sub {
    
    my $result = `script/webcheck -rf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Report WARN diskspace[\n\r]+WARN \ds diskspace[\n\r]+\/ 82[\n\r]+[*] \/var 98 [*][\n\r]+[*] \/home 95 [*][\n\r]+\/boot 25[\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'report produced WARN 98 95');
    
    $result = `cat logs/webcheck.log`;
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 9, 'report added to log');
};


subtest 'notify full' => sub {
    
    unlink 'dftest.data';
    symlink 't/dftest.full', 'dftest.data';
    
    my $result = `script/webcheck -nf t/test.yml dftest 2>&1`;
    
    my $check = $result =~ /^Notify FULL diskspace[\n\r]+FULL \ds diskspace[\n\r]+[*] \/var 98 [*][\n\r]+[*]{3} \/home 100 [*]{3}[\n\r]+$/;
    
    print STDERR $result unless $check;
    
    ok($check, 'notify produced FULL 98 100');
};


subtest 'cleanup' => sub {
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


sub unlink_testfiles {
    
    unlink('logs/webcheck.log', 'logs/dftest_state.txt', 'dftest.data');

}
