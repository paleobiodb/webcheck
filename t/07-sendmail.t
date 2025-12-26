# 
# Check that notify, report, and check modes work properly with disk space checks.

use strict;

use feature 'say';

use Test::More tests => 6;

subtest 'setup' => sub {
    
    # Remove all symlinks, log files, and state files used by the files in this
    # test, in case they are left over from a previous aborted test run.
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


subtest 'check test' => sub {
    
    my $result = `script/webcheck --check --test --file=t/test.yml test1 2>&1`;
    
    my $check = $result =~ /^Performing check 'test1'/;
    
    print STDERR $result unless $check;
    
    ok($check, 'check + test mode');
    
    $check = $result =~ /^Check OK/m;
    
    ok($check, 'check OK');
    
    my $result2 = `script/webcheck -ctf t/test.yml test1 2>&1`;
    
    is($result2, $result, 'bundled option syntax');
};


subtest 'no recipients' => sub {
    
    my $result = `script/webcheck -ctf t/test.yml --sendmail test1 2>&1`;
    
    my $check = $result =~ /^ERROR: you must set the environment/m;
    
    print STDERR $result unless $check;
    
    ok($check, 'no recipients produces error');
};


subtest 'with recipients' => sub {
    
    $ENV{RECIPIENTS} = 'test.email@myservice.com';
    
    my $result = `script/webcheck -tf t/test.yml --sendmail test1 2>&1`;
    
    my $check1 = $result =~ /^Output would be sent/m;
    
    my $check2 = $result =~ /^To: test.email\@myservice.com/m;
    
    my $check3 = $result =~ /^From: wc\@myservice.com/m;
    
    print STDERR $result unless $check1 && $check2 && $check3;
    
    ok($check1, 'output redirect');
    ok($check2, 'to address');
    ok($check3, 'from address');
    
    say STDERR "*** If you want to test webcheck with sendmail for real, run t/sendmail_test.pl"
	if $check1 && $check2 && $check3;
};


subtest 'with -f' => sub {

    $ENV{RECIPIENTS} = 'test.email@myservice.com';
    
    my $result = `script/webcheck -tf t/test2.yml --sendmail test1 2>&1`;
    
    my $check1 = $result =~ /^Output.*-f wc\@myservice.com/m;

    my $check2 = $result =~ /^To: test.email\@myservice.com/m;
    
    my $check3 = $result !~ /^From:/m;

    print STDERR $result unless $check1 && $check2 && $check3;

    ok($check1, 'envelope from');
    ok($check2, 'to address');
    ok($check3, 'no from header');
};


subtest 'cleanup' => sub {
    
    &unlink_testfiles;
    ok(1, "placeholder");
};


sub unlink_testfiles {
    
    unlink 'logs/webcheck.log', 'logs/test1_state.txt';

}
