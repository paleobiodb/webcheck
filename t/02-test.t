# 
# Check that notify, report, and check modes work properly with test1 and test2.

use strict;

use Test::More tests => 8;

subtest 'setup' => sub {
    
    my $check;
    
    # Ensure (if possible) that 'logs' is a writable directory. Remove all of
    # the log and state files used in this test, in case they are left over from
    # a previous aborted test.
    
    unless ( -d 'logs' )
    {
	unlink 'logs';
	$check = mkdir 'logs';
	ok($check, 'create logs directory') ||
	    BAIL_OUT("could not create subdirectory 'logs': $!");
    }
    
    elsif ( -w 'logs' && -x 'logs' )
    {
	ok(1, "logs directory is accessible");
	
	&unlink_testfiles;
    }
    
    else
    {
	$check = chmod 0775, 'logs';
	ok($check, 'chmod logs directory') ||
	    BAIL_OUT("could not chmod subdirectory 'logs': $!");
    }
};


subtest 'notify 1' => sub {
    
    my $result = `script/webcheck -f t/test.yml --notify test 2>&1`;
    
    my $check = $result eq <<END_CHECK;
Notify OK test A, test B
OK test A
OK test B
END_CHECK
    
    print STDERR $result unless $check;
    
    ok($check, 'notify executed successfully');
};


subtest 'log file' => sub {
    
    ok(-e 'logs/webcheck.log', 'log file created') || return;
    
    my $result = `cat logs/webcheck.log`;
    
    like($result, qr/\d\d:\d\d.*OK test A$/m, 'found test A in log');
    like($result, qr/\d\d:\d\d.*OK test B$/m, 'found test B in log');
    
    my @lines = split /[\n\r]+/, $result;
    
    is(scalar(@lines), 2, 'log file line count');
};


subtest 'state files' => sub {
    
    ok(-e 'logs/test1_state.txt', 'test1 state file created') || return;
    ok(-e 'logs/test2_state.txt', 'test2 state file created');
    
    my $result = `cat logs/test1_state.txt`;
    
    like($result, qr/^OK.*test A$/, 'state file A content');
    
    $result = `cat logs/test2_state.txt`;
    
    like($result, qr/^OK.*test B$/, 'state file B content');
};


subtest 'notify 2' => sub {
    
    my $result = `script/webcheck -nf t/test.yml test 2>&1`;
    
    my $check = $result eq <<END_CHECK;
Notify ERR test B
ERR 1 test B
END_CHECK
    
    print STDERR $result unless $check;
    
    ok($check, 'second notify produced ERR');
};


subtest 'notify 3 + report' => sub {
    
    my $result = `script/webcheck -nf t/test.yml test 2>&1`;
    
    is($result, '', 'third notify empty message');
    
    $result = `script/webcheck -rf t/test.yml test 2>&1`;
    
    my $check = $result eq <<END_CHECK;
Report ERR test B; OK test A
OK test A
ERR 3 test B
END_CHECK
    
    print STDERR $result unless $check;
    
    ok($check, 'first report output');
    
    $result = `script/webcheck -f t/test.yml --report test 2>&1`;
    
    $check = $result eq <<END_CHECK;
Report ERR test B; OK test A
OK test A
ERR 3 test B
END_CHECK
    
    print STDERR $result unless $check;
    
    ok($check, 'second report output');
};


subtest 'check + notify 4' => sub {
    
    my $result = `script/webcheck -f t/test.yml test 2>&1`;
    
    my $check = $result eq <<END_CHECK;
Check ERR test B; OK test A
OK test A
ERR 3 test B
END_CHECK
    
    print STDERR $result unless $check;
    
    ok($check, 'check output');
    
    my $result2 = `script/webcheck -cf t/test.yml test 2>&1`;
    
    is($result2, $result, 'check from -c option');
    
    my $result3 = `script/webcheck --check -f t/test.yml test 2>&1`;
    
    is($result3, $result, 'check from --check option');
    
    $result = `script/webcheck -f t/test.yml --notify test 2>&1`;
    
    is($result, '', 'fourth notify empty message');
};


subtest 'cleanup' => sub {
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


sub unlink_testfiles {
    
    unlink('logs/webcheck.log', 'logs/test1_state.txt', 'logs/test2_state.txt');

}
