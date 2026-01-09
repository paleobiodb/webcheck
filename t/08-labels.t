#
# Check that labels and groups work properly.

use strict;

use Test::More tests => 2;

subtest 'all subtests' => sub {

    my $result = `script/webcheck -f t/test2.yml all 2>&1`;
    
    my $check = $result =~ /^Check OK testing[\n\r]+OK test A[\n\r]+OK test cookie[\n\r]+$/s;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'check all subtests');
};


subtest 'multitest' => sub {

    my $result = `script/webcheck -f t/test2.yml multitest 2>&1`;
    
    my $check = $result =~ /^Check OK multitest[\n\r]+OK test A[\n\r]+OK test cookie[\n\r]+$/s;
    
    print STDERR ($result || 'EMPTY RESULT') unless $check;
    
    ok($check, 'check multitest');
};


