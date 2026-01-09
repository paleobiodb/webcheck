#
# Check that bad configuration files generate the proper error messages, and
# that bad arguments generate the proper error messages.

use strict;

use Test::More tests => 7;


subtest 'bad arguments' => sub {

    my $result = `script/webcheck -nf 2>&1`;
    
    like($result, qr/^ERROR: you must specify a configuration file name$/, 'error empty -f');
    
    $result = `script/webcheck --notify --file= 2>&1`;
    
    like($result, qr/^ERROR: you must specify a configuration file name$/, 'error empty --file');

    $result = `script/webcheck --file 2>&1`;

    like($result, qr/^ERROR: you must specify a configuration file name$/, 'error bare --file');
    
    $result = `script/webcheck --foobar 2>&1`;
    
    like($result, qr/^ERROR: unrecognized option '--foobar'$/, 'error bad option');

    $result = `script/webcheck -nxt 2>&1`;
    
    like($result, qr/^ERROR: unrecognized option '-nxt'$/, 'error bad flag');
    
    $result = `script/webcheck -nr 2>&1`;
    
    like($result, qr/^ERROR: you may not specify --notify and --report together$/, 'error nr');
    
    $result = `script/webcheck -nc 2>&1`;
    
    like($result, qr/^ERROR: you may not specify --check and --notify together$/, 'error nc');
    
    $result = `script/webcheck -cr 2>&1`;
    
    like($result, qr/^ERROR: you may not specify --check and --report together$/, 'error cf');
    
    $result = `script/webcheck -f t/test.yml no_check 2>&1`;

    like($result, qr/^ERROR: could not find 'no_check' in t\/test.yml$/, 'nonexistent check');
    
    $result = `script/webcheck -f t/nonexistent.yml 2>&1`;
    
    like($result, qr/^ERROR: could not read t\/nonexistent.yml: /, 'nonexistent config file');
    
    $result = `script/webcheck -sf t/test2.yml all 2>&1`;

    like($result, qr/^ERROR: you must set the environment variable 'RECIPIENTS'$/, 'unset env');
};


subtest 'bad top-level keys' => sub {

    my $result = `script/webcheck -f t/badconfig1.yml all 2>&1`;
    
    my $check = $result =~
	/^ERROR: you must have 'checks' as a top-level key in t\/badconfig1.yml$/m;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'error no checks');
    
    like($result, qr/^WARNING: invalid key 'foo'/m, 'warning foo');
    like($result, qr/^WARNING: invalid key 'biff'/m, 'warning biff');
};


subtest 'bad check no type' => sub {

    my $result = `script/webcheck -f t/badconfig2.yml all 2>&1`;
    
    my $check = $result =~
	/^ERROR: could not determine entry type for 'bad_check' in t\/badconfig2.yml$/m;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'error no entry type');
};


subtest 'bad url' => sub {

    my $result = `script/webcheck -f t/badconfig3.yml bad_url 2>&1`;
    
    my $check = $result =~
	/^ERROR: bad_url: 'foo' does not look like a URL, in t\/badconfig3.yml$/m;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'error bad url');
    
    like($result, qr/^WARNING: bad_url: unrecognized key 'bad_key'$/m, 'error bad key');
};


subtest 'bad df limits' => sub {

    my $result = `script/webcheck -f t/badconfig3.yml bad_df 2>&1`;

    my $check = $result =~ /^ERROR: bad_df: invalid value '150' for 'limit'$/m;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'bad limit');
    
    like($result, qr/^ERROR: bad_df: invalid value 'abc' for 'lower'$/m, 'bad lower');
    
    like($result, qr/^ERROR: bad_df: invalid value 'def' for 'limit_\/var'$/m, 'bad limit var');
    
    like($result, qr/^ERROR: bad_df: invalid value '160' for 'lower_\/var'$/m, 'bad lower var');
    
    like($result, qr/^WARNING: bad_df: unrecognized key 'bad_key'$/m, 'error bad key');
    
    like($result, qr/^Bad configuration$/m, 'final message');
};


subtest 'bad sys limits' => sub {

    my $result = `script/webcheck -f t/badconfig3.yml bad_sys 2>&1`;

    foreach my $key ( qw(load_limit load_lower load_critical
			 mem_limit mem_lower mem_critical
			 swap_limit swap_lower swap_critical
			 procs_limit procs_lower procs_critical) )
    {
	like($result, qr/^ERROR: bad_sys: invalid value 'abc' for '$key'/m, "bad key $key");
    }
    
    like($result, qr/^WARNING: bad_sys: unrecognized key 'bad_key'$/m, 'error bad key');
    
    like($result, qr/^Bad configuration$/m, 'final message');
};


subtest 'duplicate state file' => sub {

    my $result = `script/webcheck -f t/badconfig4.yml all 2>&1`;
    
    my $check = $result =~ /^ERROR: 'bad_df' and 'bad_url' have the same state file 'foo.state'$/m;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'error duplicate state');
};


