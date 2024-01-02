# 
# Check that notify, report, and check modes work properly with test1 and test2.

use strict;

use Test::More tests => 6;

subtest 'invalid options' => sub {
    
    my $result = `script/webcheck --foobar 2>&1`;
    
    my $check = $result =~ /^ERROR: unrecognized option '--foobar'/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'unrecognized option');
    
    $result = `script/webcheck -check test 2>&1`;
    
    $check = $result =~ /^ERROR: unrecognized option '-check'/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'unrecognized option 2');
};


subtest 'missing file value' => sub {
    
    my $result = `script/webcheck --file 2>&1`;
    
    my $check = $result =~ /^ERROR: you must specify a configuration file name/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'missing --file value');
    
    $result = `script/webcheck --file= test 2>&1`;
    
    $check = $result =~ /^ERROR: you must specify a configuration file name/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'missing --file= value');
    
    $result = `script/webcheck -f 2>&1`;
    
    $check = $result =~ /^ERROR: you must specify a configuration file name/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'missing -f value');
};


subtest 'check and notify' => sub {
    
    my $result = `script/webcheck -cnf t/test.yml test 2>&1`;
    
    my $check = $result =~ /^ERROR: you may not specify --check and --notify together/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'check + notify 1');
    
    $result = `script/webcheck --check --notify --file=t/test.yml test 2>&1`;
    
    $check = $result =~ /^ERROR: you may not specify --check and --notify together/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'check + notify 2');
};


subtest 'check and report' => sub {
    
    my $result = `script/webcheck -rcf t/test.yml test 2>&1`;
    
    my $check = $result =~ /^ERROR: you may not specify --check and --report together/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'check + report 1');
    
    $result = `script/webcheck --report --file=t/test.yml --check test 2>&1`;
    
    $check = $result =~ /^ERROR: you may not specify --check and --report together/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'check + report 2');
};


subtest 'configuration file errors' => sub {
    
    my $result = `script/webcheck -f t/foobar.yml test 2>&1`;
    
    my $check = $result =~ /^ERROR: could not read t\/foobar.yml/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'nonexistent file');
    
    $result = `script/webcheck -f t/badconfig.yml test 2>&1`;
    
    my $check1 = $result =~ /^WARNING: invalid key 'check' in t\/badconfig.yml/mi;
    
    my $check2 = $result =~ /^ERROR: you must have 'checks' as a top-level key/mi;
    
    print STDERR $result unless $check1 && $check2;
    
    ok($check1, 'invalid key warning');
    ok($check2, 'require checks warning');
};


subtest 'misspelled check' => sub {
    
    my $result = `script/webcheck -f t/test.yml bad 2>&1`;
    
    my $check = $result =~ /^ERROR: could not find 'bad' in t\/test.yml/i;
    
    print STDERR $result unless $check;
    
    ok($check, 'misspelled check');
};

