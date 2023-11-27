#!/usr/bin/env perl
#
# This script is designed to be run periodically by a crontab entry. It checks to make sure that
# the website specified by the argument is responding properly, and creates output if not. This
# output will then be directed as specified by the crontab entry, i.e. to a pager or cell phone.
#
# A state file is used to throttle responses so that only a few (default 2) are sent in a row if a
# problem is detected.
# 
# Author: Michael McClennen
# Date: 2019-02-25


use YAML::Tiny;

# First, read the configuration file.

my $config = YAML::Tiny->read('webcheck.yml') || die "Error: could not read config file 'check.yml': $!";

$config = $config->[0];

# If the first argument is '--report' or 'report', that will cause a message to be sent out
# even if the status continues to be 'OK'.

my $action = '';

if ( lc $ARGV[0] eq 'report' || lc $ARGV[0] eq '--report' )
{
    $action = 'report';
    shift @ARGV;
}


# Now run through all of the remaining arguments and check each one. The resulting messages will
# be concatenated to the following variable.

my @MESSAGES;
my $REPORT = '';

if ( $action eq 'report' )
{
    push @MESSAGES, "REPORT";
    $REPORT = 'REPORT ';
}

unless ( @ARGV )
{
    push @MESSAGES, "ERROR: no target was given";
}

my $timestr = scalar(localtime);

&process_args;

# Print out any messages that were generated. If this script is run from a crontab entry (which is
# usual) then crontab can be set up to e-mail any output to some e-mail address.

if ( @MESSAGES )
{
    print join("\n", @MESSAGES) . "\n";
}

exit;


sub process_args {

    my @entries = @ARGV;

 ENTRY:
    while ( @entries )
    {
	my $check_entry = shift @entries;
	
	# Ignore empty entries, and the keyword 'report'.
	
	next unless $check_entry && $check_entry ne 'report';
	
	# If the entry is not found, add an error message.
	
	unless ( $config->{$check_entry} )
	{
	    push @MESSAGES, "NOTFOUND $check_entry";
	    next ENTRY;
	}
	
	# If the value of the entry is a string, if represents a list of other entries to be
	# checked. So split it on whitespace and replace it in the entry list with a list of the
	# resulting strings.
	
	if ( $config->{$check_entry} && ! ref $config->{$check_entry} )
	{
	    my @list = split /\s+/, $config->{$check_entry};
	    
	    foreach my $entry ( reverse @list )
	    {
		unshift @entries, $entry if $entry;
	    }
	    
	    next ENTRY;
	}
	
	# Otherwise, process this entry.

	else
	{
	    process_entry($check_entry);
	}
    }
}


sub process_entry {

    my ($check_entry) = @_;
    
    # Look up the parameters relevant to this entry.
    
    my $retries = $config->{$check_entry}{retries} || $config->{retries} || 2;
    my $check_command = $config->{$check_entry}{$command} || $config->{command} || "curl --head";
    my $state_file = $config->{$check_entry}{statefile} || $config->{statefile} || "logs/webcheck.txt";
    my $log_file = $config->{$check_entry}{logfile} || $config->{logfile} || "logs/webcheck.log";
    my $check_url = $config->{$check_entry}{url} || $config->{url};
    
    if ( ! $check_url )
    {
	push @MESSAGES, "ERROR $check_entry: no URL given\n";
	return;
    }

    elsif ( $check_url !~ qr{ ^ \w+ :// [\w.]+ / .* }xs )
    {
	push @MESSAGES, "ERROR $check_entry: '$check_url' does not look like a URL";
	return;
    }
    
    # Use the indicated command to fetch the specified page. Either extract an HTTP response code, or
    # a 3-character string indicating that an error occurred.
    
    my ($response, $code);
    
    eval {
	$response = `$check_command '$check_url'`;
    };
    
    if ( $@ )
    {
	$code = "FETCH_DIE";
	push @MESSAGES, "DIE $check_entry: $@";
    }
    
    elsif ( $response =~ qr{ ^ HTTP/1.1 \s+ (\d+) }xsi )
    {
	$code = $1;
    }
    
    else
    {
	$code = 'FETCH_ERR';
    }
    
    # Now we need to check the state file and see if an error message is needed. If we cannot
    # read the state file for some reason, use /var/tmp/checkstate.txt as a temporary.

    unless ( -e $state_file )
    {
	open($statefh, ">", $state_file);
	close($statefh);
    }
    
    my $statefh;
    my $result = open($statefh, "<", $state_file);
    
    unless ( $result )
    {
	push @MESSAGES, "FILE_ERROR $check_entry: $!";
	$code = "FILE_ERR" if $code eq '200';
	$state_file = "/var/tmp/check_${check_entry}.txt";
	open($statefh, "<", $state_file);
    }
    
    # If we don't need the /var/tmp file and one is there, unlink it.
    
    elsif ( -e "/var/tmp/check_${check_entry}.txt" )
    {
	unlink("/var/tmp/check_${check_entry}.txt");
    }

    # Read the current state from the state file.
    
    my ($state) = <$statefh>;
    
    # Now re-open the state file for writing.
    
    $result = open($statefh, ">", $state_file);
    
    unless ( $result )
    {
	push @MESSAGES, "WRITE_ERR $check_entry: $!";
	$code = "WRITE_ERR";
    }
    
    # Now open the log file for writing, if possible.
    
    $result = open($logfh, ">>", $log_file);
    
    # If the state is 'OK' and the response code is 200, then at this point we know everything is
    # okay. This should be the case on the vast majority of runs of this script. terminate silently
    # unless the action is 'report', in which case an 'All well' output is produced. This should be
    # scheduled by a separate crontab line once per day, to indicate that the system is working as
    # expected.
    
    if ( $code eq '200' )
    {
	if ( $action eq 'report' )
	{
	    push @MESSAGES, "OK $check_entry";
	    print $logfh "[$timestr] ${REPORT}OK $check_entry\n" if $logfh;
	}
	
	elsif ( $state && $state !~ qr{ ^ OK }xs )
	{
	    push @MESSAGES, "OK $check_entry";
	    print $logfh "[$timestr] ${REPORT}OK $check_entry\n" if $logfh;
	}
	
	print $statefh "OK 200 $check_entry\n";
    }
    
    # If the code is anything else, and the state is 'OK', then we need to send an initial warning.
    
    elsif ( $state && $state =~ qr{ ^ OK }xs )
    {
	push @MESSAGES, "ERR $check_entry 1 $code";
	print $statefh "ERR 1 $code $check_entry\n";
	print $logfh "[$timestr] ${REPORT}ERR $check_entry 1 $code\n" if $logfh;
    }
    
    # If the code is anything else, and the state is 'ERR <n>' then we send a followup warning unless
    # we have already reached the configured warning count.
    
    elsif ( $state && $state =~ qr{ ^ ERR \s+ (\d+) \s+ ([^\s]+) }xs )
    {
	my $count = $1;
	my $previous = $2;
	
	if ( $previous ne $code )
	{
	    push @MESSAGES, "ERR $check_entry 1 $code";
	    print $statefh "ERR 1 $code $check_entry\n";
	    print $logfh "[$timestr] ${reportstr}ERR $check_entry 1 $code\n" if $logfh;
	}
	
	else
	{
	    $count++;
	    push @MESSAGES, "ERR $check_entry $count $code" if $action eq 'report' || $count <= $retries;
	    print $statefh "ERR $count $code $check_entry\n";
	    print $logfh "[$timestr] ${REPORT}ERR $check_entry $count $code\n" if $logfh;
	}
    }
    
    # Otherwise, send out the error anyway and try to set the state file to known contents.
    
    else
    {
	push @MESSAGES, "ERR $check_entry n $code";
	print $statefh "ERR 1 $code\n";
	print $logfh "[$timestr] ${REPORT}ERR $check_entry x $code\n" if $logfh;
    }
    
    unless ( close $statefh )
    {
	push @MESSAGES, "WRITE_ERR $check_entry state: $!";
    }

    unless ( close $logfh )
    {
	push @MESSAGES, "WRITE_ERR $check_entry log: $!";
    }
}


# # The URL to check is read from the command-line arguments. If a second argument is given, it is
# # interpreted as an action. The only available action at the present time is 'report', which will
# # send a message to indicate that the software is working as expected.

# my ($check_entry, $action) = @ARGV;

# $action ||= '';
# $action = lc $action;

# # If no URL was given, or if the first argument does not look like a URL, throw an error message
# # and fail.

# die "Error: no entry was given" unless $check_entry;

# my $retries = $config->{$check_entry}{retries} || $config->{retries} || 2;
# my $check_command = $config->{$check_entry}{$command} || $config->{command} || "curl --head";
# my $state_file = $config->{$check_entry}{statefile} || $config->{statefile} || "logs/webcheck.txt";
# my $log_file = $config->{$check_entry}{logfile} || $config->{logfile} || "logs/webcheck.log";
# my $check_url = $config->{$check_entry}{url} || $config->{url};

# die "Error: no URL was given for '$check_entry'"
#     unless $check_url;

# die "Error: the string '$check_url' does not look like a URL"
#     unless $check_url =~ qr{ ^ \w+ :// [\w.]+ / .* }xs;

# # Use the indicated command to fetch the specified page. Either extract an HTTP response code, or
# # a 3-character string indicating that an error occurred.

# my ($response, $code);

# eval {
#     $response = `$check_command '$check_url'`;
# };

# if ( $@ )
# {
#     $code = "FETCH_DIE";
# }

# elsif ( $response =~ qr{ ^ HTTP/1.1 \s+ (\d+) }xsi )
# {
#     $code = $1;
# }

# else
# {
#     $code = 'FETCH_ERR';
# }

# # Otherwise, we need to check the state file and see if an error message is needed. If we cannot
# # read the state file for some reason, use /var/tmp/checkstate.txt as a temporary.

# my ($statefh, $logfh);
# my $result = open($statefh, "+<", $state_file);

# unless ( $result )
# {
#     my $err = $!;
#     $code = "FILE_ERR: $err" if $code eq '200';
#     $state_file = "/var/tmp/checkstate.txt";
#     open($statefh, "+<", $state_file);
# }

# # If we don't need the /var/tmp file and one is there, unlink it.

# elsif ( -e "/var/tmp/checkstate.txt" )
# {
#     unlink("/var/tmp/checkstate.txt");
# }

# my ($state) = <$statefh>;

# # Now re-open the state file for writing.

# $result = open($statefh, ">", $state_file);

# unless ( $result )
# {
#     $code = "WRITE_ERR $!";
# }

# # Now open the log file for writing, if possible.

# $result = open($logfh, ">>", $log_file);

# my $timestr = scalar(localtime);

# my $reportstr = '';
# $reportstr = 'REPORT ' if $action eq 'report';

# # If the state is 'OK' and the response code is 200, then at this point we know everything is
# # okay. This should be the case on the vast majority of runs of this script. terminate silently
# # unless the action is 'report', in which case an 'All well' output is produced. This should be
# # scheduled by a separate crontab line once per day, to indicate that the system is working as
# # expected.

# if ( $code eq '200' )
# {
#     if ( $action eq 'report' )
#     {
# 	print "${reportstr}OK $check_entry\n";
# 	print $logfh "[$timestr] ${reportstr}OK $check_entry\n" if $logfh;
#     }
    
#     elsif ( $state && $state !~ qr{ ^ OK }xs )
#     {
# 	print "OK $check_entry\n";
# 	print $logfh "[$timestr] OK $check_entry\n" if $logfh;
#     }
    
#     print $statefh "OK 200 $check_entry\n";
# }

# # If the code is anything else, and the state is 'OK', then we need to send an initial warning.

# elsif ( $state && $state =~ qr{ ^ OK }xs )
# {
#     print $statefh "ERR 1 $code $check_entry\n";

#     print $logfh "[$timestr] ${reportstr}ERR $check_entry 1 $code\n" if $logfh;
#     print "${reportstr}ERR $check_entry 1 $code\n";
# }

# # If the code is anything else, and the state is 'ERR <n>' then we send a followup warning unless
# # we have already reached the configured warning count.

# elsif ( $state && $state =~ qr{ ^ ERR \s+ (\d+) \s+ ([^\s]+) }xs )
# {
#     my $count = $1;
#     my $previous = $2;
    
#     if ( $previous ne $code )
#     {
# 	print $statefh "ERR 1 $code $check_entry\n";
# 	print $logfh "[$timestr] ${reportstr}ERR $check_entry 1 $code\n" if $logfh;
# 	print "${reportstr}ERR $check_entry 1 $code\n";
#     }
    
#     else
#     {
# 	$count++;
# 	print $statefh "ERR $count $code $check_entry\n";
# 	print $logfh "[$timestr] ${reportstr}ERR $check_entry $count $code\n" if $logfh;
# 	print "${reportstr}ERR $check_entry $count $code\n" if $action eq 'report' || $count <= $retries;
#     }
# }

# # Otherwise, send out the error anyway and try to set the state file to known contents.

# else
# {
#     print $statefh "ERR 1 $code $check_entry\n";
#     print $logfh "[$timestr] ${reportstr}ERR $check_entry x $code\n" if $logfh;
#     print "ERR $check_entry x $code\n";
# }

# close $statefh || print "WRITE_ERR state: $!\n";
# close $logfh || print "WRITE_ERR log: $!\n";
