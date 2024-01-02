#!/usr/bin/env perl
# 
# Ask the user for an e-mail address, and test webcheck with sendmail using that
# address. 


use strict;

use feature 'say';


say "Enter an e-mail address to test webcheck with sendmail: ";

my $address = <STDIN>;

if ( $address !~ /\S/ )
{
    exit;
}

elsif ( $address !~ /^\S+\@\S+\.\S+/ )
{
    say "That doesn't look like an e-mail address.";
    exit;
}

else
{
    say "\nSending test e-mail to: $address";
    
    $ENV{RECIPIENTS} = $address;
    system("script/webcheck --sendmail -f t/test.yml test");
}

