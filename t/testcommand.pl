#!/usr/bin/env perl

if ( $ARGV[0] eq '-b' && $ARGV[1] eq 'TEST=1' )
{
    print "HTTP/1.1 200 OK\nHost: myservice.com\netc.";
}

else
{
    print "HTTP/1.1 500 Server Error\nHost: myservice.com\netc.";
}

