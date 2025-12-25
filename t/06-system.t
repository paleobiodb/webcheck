# 
# Check that notify, report, and check modes work properly with disk space checks.

use strict;

use Test::More tests => 13;

our ($LAST_TIMESTAMP);

subtest 'setup' => sub {
    
    # Remove all symlinks, log files, and state files used by the files in this
    # test, in case they are left over from a previous aborted test run.
    
    &unlink_testfiles;
    
    # Symlink dftest.data to point to a good result.
    
    my $check = symlink 't/systest.good', 'systest.data';
    
    ok($check, 'create symlink to test data') ||
	BAIL_OUT("could not create necessary symlink");
};


subtest 'notify ok' => sub {
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify OK system[\n\r]+OK system[\n\r]+$/;
    
    ok($check, 'notify reported OK') || print STDERR "\n$result";
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'second notify was empty');
};


subtest 'log file' => sub {
    
    ok(-e 'logs/webcheck.log', 'log file created') || return;
    
    my $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK system$/m, 'found OK recorded in log');
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 1, 'log file records one notification');
};


subtest 'state file' => sub {
    
    ok(-e 'logs/systest_state.txt', 'systest state file created') || return;
    
    my $result = `cat logs/systest_state.txt`;
    
    like($result, qr/ ^ OK [|] \d+ [|] [|] system $ /xs, 'state file content');

    (undef, $LAST_TIMESTAMP, undef, undef) = split /[|]/, $result;
};


subtest 'notify warn' => sub {
    
    unlink 'systest.data';
    symlink 't/systest.warn', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify WARN system[\n\r]+WARN \ds system[\n\r]+[*] load 2.1 [*][\n\r]+[*] mem 80 [*][\n\r]+$/;
    
    ok($check, 'notify produced WARN') || print STDERR "\n$result";
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK system$/m, 'found OK remaining in log');
    
    like($result, qr/\d\d:\d\d.*WARN [1-9]s system$/m, 'found WARN recorded in log');
    
    like($result, qr/\d\d:\d\d.*load 2.1.*mem 80$/m, 'found load and mem recorded in log');
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'second notify produces empty');
    
    $result = `script/webcheck -rf t/test.yml systest 2>&1`;
    
    $check = $result =~ /^Report WARN system[\n\r]+WARN \ds system[\n\r]+[*] load 2.1 [*][\n\r]+[*] mem 80 [*][\n\r]+swap 25[\n\r]+procs 255[\n\r]+$/;
    
    ok($check, 'report produced WARN with all stats') || print STDERR "\n$result";
    
    $result = `cat logs/systest_state.txt`;
    
    my ($code, $timestamp, $state) = split /[|]/, $result;
    
    cmp_ok($timestamp, '>', $LAST_TIMESTAMP, 'new timestamp with WARN');

    $LAST_TIMESTAMP = $timestamp;
    
    $result = `cat logs/webcheck.log`;

    like($result, qr/\d\d:\d\d.*REPORT WARN \ds system$/m, 'report added to log');
    
    like($result, qr/\d\d:\d\d.*REPORT load 2.1 - mem 80$/m, 'report added details to log');
};


subtest 'notify higher' => sub {
    
    unlink 'systest.data';
    symlink 't/systest.higher', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify WARN system[\n\r]+WARN \ds system[\n\r]+[*] load 2.5 [*][\n\r]+- mem 70 -[\n\r]+$/;
    
    ok($check, 'notify produced WARN with higher values') || print STDERR "\n$result";
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*load 2.1/m, 'found load 2.1 remaining in log');
    
    like($result, qr/\d\d:\d\d.*load 2.5/m, 'found load 2.5 recorded in log');
    
    $result = `cat logs/systest_state.txt`;
    
    like($result, qr/ ^ WARN [|] \d+ [|]load \s 2.5 \s - \s mem \s 80[|] system $ /xs,
	 'state file contains max reached values');    
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'additional notify produces empty');
    
    $result = `cat logs/systest_state.txt`;
    
    my ($code, $timestamp, $state) = split /[|]/, $result;
    
    cmp_ok($timestamp, '==', $LAST_TIMESTAMP, 'same timestamp with WARN');
    
    $LAST_TIMESTAMP = $timestamp;
};


subtest 'notify lower' => sub {
    
    unlink 'systest.data';
    symlink 't/systest.lower', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'lower values produce no notification');
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*load 2.1/m, 'found load 2.1 remaining in log');
    
    like($result, qr/\d\d:\d\d.*load 2.5/m, 'found load 2.5 recorded in log');
    
    unlike($result, qr/\d\d:\d\d.*load 2.2/m, 'did not find load 2.2 recorded in log');
};


subtest 'notify warn2' => sub {

    unlink 'systest.data';
    symlink 't/systest.warn2', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify WARN system[\n\r]+WARN \ds system[\n\r]+[*] load 2.2 [*][\n\r]+[*] mem 80 [*][\n\r]+[*] swap 60 [*][\n\r]+[*] procs 500 [*][\n\r]+$/;
    
    ok($check, 'notify produced WARN with new values') || print STDERR "\n$result";
    
    $result = `cat logs/systest_state.txt`;
    
    like($result, qr/ ^ WARN [|] \d+ [|]load \s 2.5 \s - \s mem \s 80 \s - \s swap \s 60 \s - \s procs \s 500 [|] system $ /xs,
	 'state file contains max reached values');
    
    $result = `cat logs/systest_state.txt`;
    
    my ($code, $timestamp, $state) = split /[|]/, $result;
    
    cmp_ok($timestamp, '==', $LAST_TIMESTAMP, 'same timestamp with WARN');
    
    $LAST_TIMESTAMP = $timestamp;
};


subtest 'notify critical' => sub {

    unlink 'systest.data';
    symlink 't/systest.critical', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify CRITICAL system[\n\r]+CRITICAL \ds system[\n\r]+[*]{3} load 4 [*]{3}[\n\r]+[-] mem 65 [-][\n\r]+[*]{3} swap 100 [*]{3}[\n\r]+[*]{3} procs 600 [*]{3}[\n\r]+$/;
    
    ok($check, 'notify produced CRITICAL') || print STDERR "\n$result";
    
    $result = `cat logs/systest_state.txt`;
    
    like($result, qr/ ^ CRITICAL [|] \d+ [|]load \s 4 \s - \s mem \s 65 \s - \s swap \s 100 \s - \s procs \s 600 [|] system $ /xs,
	 'state file contains new max values with new state');    
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*load 4 - mem 65/m, 'found load 4 and mem 65 in log');
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'additional notify produces empty');
    
    $result = `cat logs/systest_state.txt`;
    
    my ($code, $timestamp, $state) = split /[|]/, $result;
    
    cmp_ok($timestamp, '>', $LAST_TIMESTAMP, 'new timestamp with CRITICAL');
    
    $LAST_TIMESTAMP = $timestamp;
};


subtest 'notify decreasing' => sub {

    unlink 'systest.data';
    symlink 't/systest.decreasing', 'systest.data';
    
    sleep 1;
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify WARN system[\n\r]+WARN \ds system[\n\r]+[-] load 1.5 [-][\n\r]+[-] mem 60 [-][\n\r]+[-] procs 480 [-][\n\r]+$/;
    
    ok($check, 'notify produced WARN') || print STDERR "\n$result";
    
    $result = `cat logs/systest_state.txt`;
    
    like($result, qr/ ^ WARN [|] \d+ [|]load \s 1.5 \s - \s mem \s 60 \s - \s procs \s 480 [|] system $ /xs,
	 'state file contains new max values with new state');    

    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*load 1.5 - mem 60/m, 'found load 1.5 and mem 60 in log');
    
    my (@lines) = split /[\n\r]+/, $result;
    
    cmp_ok(@lines, '==', 13, 'log had 13 lines');
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'additional notify produces empty');
    
    $result = `cat logs/systest_state.txt`;
    
    my ($code, $timestamp, $state) = split /[|]/, $result;
    
    cmp_ok($timestamp, '>', $LAST_TIMESTAMP, 'new timestamp with WARN');
    
    $LAST_TIMESTAMP = $timestamp;
};


subtest 'check' => sub {
    
    my $result = `script/webcheck -f t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Check WARN system[\n\r]+WARN \ds system[\n\r]+[-] load 1.5 [-][\n\r]+[-] mem 60 [-][\n\r]+swap 20[\n\r]+[-] procs 480 [-][\n\r]+$/;
    
    ok($check, 'check produced WARN') || print STDERR "\n$result";
    
    $result = `cat logs/webcheck.log`;

    my (@lines) = split /[\n\r]+/, $result;

    cmp_ok(@lines, '==', 13, 'check did not add to log');
};


subtest 'notify good again' => sub {

    unlink 'systest.data';
    symlink 't/systest.good', 'systest.data';
    
    my $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    my $check = $result =~ /^Notify OK system[\n\r]+OK \ds system[\n\r]+$/;
    
    ok($check, 'notify produced OK') || print STDERR "\n$result";
    
    $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK \ds system[\n\r]+$/, 'found final OK in log');
    
    $result = `script/webcheck -nf t/test.yml systest 2>&1`;
    
    is($result, '', 'additional notify produces empty');    
};


subtest 'cleanup' => sub {
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


sub unlink_testfiles {
    
    unlink('logs/webcheck.log', 'logs/systest_state.txt', 'systest.data');

}
