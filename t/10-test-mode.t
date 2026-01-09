#
# Check that test mode works properly.

use strict;

use Test::More tests => 2;

subtest 'test mode' => sub {

    my $result = `script/webcheck -tf t/test2.yml multitest 2>&1`;
    
    is($result, <<END_LITERAL, 'test mode output');
Performing check 'test1'
Performing check 'urltest'
Check OK multitest
OK test A
OK test cookie
END_LITERAL
};


subtest 'test sendmail' => sub {
    
    my $result = `script/webcheck -tf t/test2.yml --sendmail multitest 2>&1`;
    
    is($result, <<END_LITERAL, 'test mode with sendmail');
Performing check 'test1'
Performing check 'urltest'
ERROR: you must set the environment variable 'RECIPIENTS'
END_LITERAL
    
    $ENV{RECIPIENTS} = 'me@mydomain.com';
    
    $result = `script/webcheck -tf t/test2.yml --sendmail multitest 2>&1`;

    is($result, <<END_LITERAL, 'test mode with sendmail and environment');
Performing check 'test1'
Performing check 'urltest'
Output would be sent via sendmail -f wc\@myservice.com
To: me\@mydomain.com
Check OK multitest
OK test A
OK test cookie
END_LITERAL
};
