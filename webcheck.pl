#!/usr/bin/env perl
# 
#     WebCheck - check web services and notify when they are down
# 
# 
# Author: Michael McClennen <mmcclenn@geology.wisc.edu>
# 
# This script is designed to be run periodically as a cron job.  Depending on
# the configuration, it can check for an acceptable response from one or more
# web services, and can also check free disk space. Notifications are written to
# STDOUT by default, which allows for them to be directed to the responsible
# personnel either through an email inbox or a text message gateway. They can
# also be sent directly through sendmail. It is recommended that this script be
# run every 10 minutes, or as often as necessary to ensure prompt notification
# of outages.
# 
# The results of all status checks are written to a log file, and the status of
# each service is also stored in a state file. This stored state enables an
# abnormal condition to be notified once when it occurs, with a specified
# follow-up notification pattern.
# 
# Originally written in the 1990s.
# Rewritten: 2019-02-25, 2023-12-02


use strict;

use feature 'say';
no warnings 'uninitialized';

use YAML::Tiny;


my %TOPLEVEL = (checks => 1, log_dir => 1, log_file => 1, state_dir => 1,
		sendmail => 1, sendmail_report => 1, from => 1,
		url_command => 1, url_followup => 1, 
		df_command => 1, df_limit => 1);


# Defaults

my $config_file = 'webcheck.yml';
my $default_log = 'webcheck.log';
my $log_dir = '.';
my $state_dir;


# Globals

my $REPORT = '';
my $CHECK;
my $VERBOSE;

my ($log_file, $log_fh, $state_file, $state_temp, $state_fh);

my %state_uniq;
my %name_uniq;

sub output_message;
sub log_message;
sub write_log;
sub write_state;

# All of the log entries and state entries generated by this run will have a single
# timestamp.

my $curtime = time;
my $timestamp = scalar(localtime);


# Check for options.
# 
# The option '-f' or '--file' specifies a configuration file. The default is
# 'webcheck.yml'. The option '-r' or '--report' or 'report' will cause output to
# be generated for all selected entries even if the status is an unchanged 'OK'.

while ( @ARGV )
{
    if ( $ARGV[0] =~ /^-f$|--file$/ )
    {
	shift @ARGV;
	$config_file = shift @ARGV or die "ERROR: you must specify a configuration file name\n";
    }
    
    elsif ( $ARGV[0] =~ /^--file=(.*)/ )
    {
	$config_file = $1 or die "ERROR: you must specify a configuration file name\n";
	shift @ARGV;
    }
    
    elsif ( $ARGV[0] =~ /^-r$|^--report$/ )
    {
	$REPORT = 'REPORT ';
	shift @ARGV;
    }
    
    elsif ( $ARGV[0] =~ /^-c$|^--check$/ )
    {
	$CHECK = 1;
	shift @ARGV;
    }
    
    elsif ( $ARGV[0] =~ /^-v|^--verbose$/ )
    {
	$VERBOSE = 1;
	shift @ARGV;
    }
    
    elsif ( $ARGV[0] =~ /^-h$|^--help$/ )
    {
	&help_message;
	exit;
    }
    
    elsif ( $ARGV[0] eq '-' )
    {
	shift @ARGV;
    }
    
    elsif ( $ARGV[0] =~ /^-/ )
    {
	die "ERROR: unrecognized option '$ARGV[0]'\n";
    }
    
    else
    {
	last;
    }
}


# Read and validate the configuration file.

my ($CONFIG, @ALL_CHECKS);

&ReadConfigurationFile($config_file);


# Process the remaining arguments, which should specify entries in the
# configuration file to be checked. If no arguments were given, default to
# 'all'. Resulting notifications will be appended to @NOTIFICATIONS.

my @NOTIFICATIONS;

push @ARGV, 'all' unless @ARGV;

&PerformStatusChecks(@ARGV);


# If any notifications were generated, send them out now. Otherwise, exit
# silently unless we are running in verbose mode.

if ( @NOTIFICATIONS )
{
    &SendNotifications;
}

elsif ( $VERBOSE )
{
    say STDERR "No notifications";
}

exit;


# ReadConfigurationFile ( filename )
# 
# Read and parse the specified file, which must be in YAML format. Store the
# configuration variables as a hashref in $CONFIG.

sub ReadConfigurationFile {
    
    my ($filename) = @_;
    
    # Read the specified file, or die if an error occurs.
    
    die "ERROR: could not read $config_file: $!" unless -r $config_file;
    
    $CONFIG = YAML::Tiny->read($config_file);
    
    $CONFIG = $CONFIG->[0];
    
    # Validate the file contents.
    
    die "ERROR: you must have 'checks' as a top-level key in $config_file\n" 
	unless ref $CONFIG eq 'HASH' && $CONFIG->{checks};

    foreach my $key ( keys $CONFIG->%* )
    {
	warn "ERROR: invalid key '$key' in $config_file\n"
	    unless $TOPLEVEL{$key};
	
	if ( $key eq 'log_dir' && $CONFIG->{$key} )
	{
	    $log_dir = $CONFIG->{$key};
	}
	
	elsif ( $key eq 'state_dir' && $CONFIG->{$key} )
	{
	    $state_dir = $CONFIG->{$key};
	}
	
	elsif ( $key eq 'log_file' && $CONFIG->{$key} )
	{
	    $default_log = $CONFIG->{$key};
	}
    }
    
    # Now read the raw file contents, and grab the entry names in order. It is
    # important that when all checks are carried out, they are always done in
    # the order in which they are listed in the file.
    
    open(my $ifh, '<', $config_file) or 
	die "ERROR: could not read $config_file: $!";
    
    while ( my $line = <$ifh> )
    {
	if ( $line =~ qr{ ^ \s+ (\w+) : }xs )
	{
	    push @ALL_CHECKS, $1 if ref $CONFIG->{checks}{$1} eq 'HASH';
	}
    }
}


# PerformStatusChecks ( entry... )
# 
# Carry out one or more status checks, using entries specified in the
# configuration file. See the help message for more details.

sub PerformStatusChecks {
    
    # Check for each of the specified entries in the configuration file. These
    # must be top-level keys.
    
 ENTRY:
    while ( @_ )
    {
	my $check_name = shift @_;
	
	# Ignore empty entries, and perform each check only once.
	
	next ENTRY unless $check_name && ! $name_uniq{$check_name};
	
	$name_uniq{$check_name} = 1;
	
	# The keyword 'all' expands to all of the entries under 'checks'.
	
	if ( $check_name eq 'all' )
	{
	    unshift @_, @ALL_CHECKS;
	    next ENTRY;
	}
	
	# Throw an exception if we are asked to perform a nonexistent check.
	
	unless ( exists $CONFIG->{checks}{$check_name} )
	{
	    die "ERROR: could not find '$check_name' in $config_file\n";
	}
	
	# If the check exists but is empty, skip it.
	
	my $specification = $CONFIG->{checks}{$check_name};
	
	next ENTRY unless $specification;
	
	# If the value of the entry is a string, it represents a list of other entries to be
	# checked. So split it on whitespace and replace it in the entry list with a list of the
	# resulting strings.
	
	if ( ! ref $specification )
	{
	    my @list = split /\s+/, $specification;
	    
	    foreach my $e ( reverse @list )
	    {
		unshift @_, $e if $e;
	    }
	    
	    next ENTRY;
	}
	
	# If the entry includes the key 'url', it represents a server status
	# check.
	
	if ( $specification->{url} )
	{
	    say STDERR "Performing check '$check_name'" if $VERBOSE;
	    CheckWebService($check_name, $specification);
	}
	
	# If the entry includes the key 'limit', it represents a disk space check.
	
	elsif ( $specification->{limit} )
	{
	    say STDERR "Performing check '$check_name'" if $VERBOSE;
	    CheckDiskSpace($check_name, $specification);
	}
	
	# If the entry includes the key 'test', it can be used to test this
	# system. 
	
	elsif ( defined $specification->{cycle} && $specification->{cycle} ne '' )
	{
	    say STDERR "Performing check '$check_name'" if $VERBOSE;
	    CheckTest($check_name, $specification);
	}
	
	# Otherwise, throw an exception.
	
	else
	{
	    die "ERROR: could not determine entry type for '$check_name' in $config_file\n";
	}
    }
    
    # If a log file has been opened, close it now.
    
    close $log_fh if $log_fh;
}


# CheckWebService ( name, parameters )
# 
# Check the status of a remote server, by fetching a specified URL.

sub CheckWebService {

    my ($name, $params) = @_;
    
    # Look up the parameters relevant to this entry.
    
    my $command = $params->{command} || $CONFIG->{url_command} || "curl --head --silent '%'";
    my $followup = $params->{followup} || $CONFIG->{url_followup} || '';
    my $check_url = $params->{url};
    my $label = $params->{label} || $name;
    
    unless ( $check_url && $check_url =~ qr{ ^ \w+ :// [\w.:]+ / .* }xs )
    {
	die "ERROR: $name: '$check_url' does not look like a URL, in $config_file\n";
    }
    
    # If the command string contains '%', replace each instance with the value of
    # $check_url.
    
    if ( $command =~ /%/ )
    {
	$command =~ s/%/$check_url/g;
    }
    
    # Use the indicated command to fetch the specified page. If we don't get a
    # valid HTTP response code, set the code to a string indicating an error.
    
    my ($response, $code, $errmsg);
    
    eval {
	$response = `$command`;
    };
    
    if ( $! )
    {
	$code = 'EXC';
	$errmsg = "EXC $label";
    }
    
    elsif ( $response =~ qr{ ^ HTTP/\d[.]\d \s+ (\d+) }xsi )
    {
	$code = $1;
	$errmsg = "DOWN $label ($code)";
    }
    
    else
    {
	$code = 'NOR';
	$errmsg = "DOWN $label (NOR)";
    }
    
    # If we are running in check mode, output the result and return.
    
    if ( $CHECK )
    {
	if ( $code eq '200' )
	{
	    output_message "OK $label";
	}
	
	else
	{
	    output_message $errmsg;
	}
	
	return;
    }
    
    # Otherwise, open the correct log file and read the prior state of this
    # entry. The fields of the state file are as follows:
    # 
    # 1. The previous status of the service (OK or DOWN)
    # 2. The timestamp at which that result was first observed
    # 3. The number of DOWN results in a row since the last OK
    # 4. The HTTP response code from the service, or NOR for no response
    # 5. The service label
    
    SelectLog($name, $params);
    
    my $prior = ReadState($name, $params);
    
    my ($pstatus, $ptime, $pcount, $pcode) = split /[|]/, $prior;
    
    # If the response code is 200 and the prior status is 'OK', then everything
    # is hunky dory. Generate output only if running in report mode, but always
    # generate a log entry. This should be the case on the vast majority of runs
    # of this script.
    
    if ( $code eq '200' && $pstatus eq 'OK' )
    {
	output_message "OK $label" if $REPORT;
	write_log "OK $label";
	return;
    }
    
    # If the response code is 200 and the prior state is not 'OK', generate a
    # notification that the checked server is okay again. Also generate a log
    # entry, and write the new state.
    
    elsif ( $code eq '200' )
    {
	log_message "OK $label";
	write_state "OK|$curtime|0|200|$label";
	return;
    }
    
    # If the code is anything else, and the prior status was 'OK', generate an
    # initial notification that something is wrong.
    
    elsif ( ! $pcount > 0 )
    {
	my $notification = "DOWN $label ($code)";
	
	log_message $notification;
	write_state "DOWN|$curtime|1|$code|$label";
	return;
    }
    
    # Otherwise, this is a continuing bad status situation. Determine if we
    # should send a followup notification based on the followup pattern for this
    # entry. Compute the elapsed time since the bad status was first noticed,
    # and generate a notification if appropriate.
    
    else
    {
	my $count = $pcount + 1;
	my @followup_times = split /\s+/, $followup;
	my $is_followup;
	
	foreach my $n ( @followup_times )
	{
	    $is_followup = 1 if $n == $pcount;
	}
	
	my $elapsed = ComputeElapsed($curtime, $ptime);
	
	my $notification = "DOWN $label $elapsed ($code)";
	
	# Generate a notification if the new response code is different from the
	# prior code, or if we are running in report mode, or if the count matches
	# one of the numbers specified by the entry parameter 'followup'.
	
	if ( $code ne $pcode || $REPORT || $is_followup )
	{
	    output_message $notification;
	}
	
	write_log $notification;    
	write_state "DOWN|$ptime|$count|$code|$label";
	return;
    }
}


# CheckDiskSpace ( name, parameters )
# 
# Check if any of the local disks are getting full, or do that check on a remote
# server.

sub CheckDiskSpace {
    
    my ($name, $params) = @_;
    
    # Look up the parameters relevant to this entry.
    
    my $command = $params->{command} || $CONFIG->{df_command} || 'df';
    my $ignore_entries = $params->{ignore} || "_IGNORE NOTHING_";
    my $default_limit = $params->{limit};
    my $label = $params->{label} || $name;
    
    die "ERROR: $name: invalid limit '$default_limit'\n"
	
	unless $default_limit > 0 && $default_limit <= 100;
    
    
    # Run the indicated command and parse the output.
    
    my ($response, $code, @details);
    
    eval {
	$response = `$command`;
    };
    
    if ( $! )
    {
	$code = 'EXC';
    }
    
    else
    {
	$code = 'OK';
    }
    
    my @lines = split /\n/, $response;
    
    foreach my $line ( @lines )
    {
	next if $line =~ /$ignore_entries/;
	
	next unless $line =~ qr{ \s (\d+) [%] \s+ ( / \S* ) }xs;
	
	my $used = $1;
	my $volume = $2;
	
	my $limit = $params->{"limit_" . $volume};
	
	$limit = $default_limit unless $limit > 0 && $limit <= 100;
	
	if ( $used eq '100' )
	{
	    $code = 'FULL';
	    push @details, "$volume 100";
	}
	
	elsif ( $used >= $limit )
	{
	    $code = 'WARN' unless $code eq 'FULL';
	    push @details, "$volume $used";
	}
    }
    
    # If we are running in check mode, output the result and return.
    
    if ( $CHECK )
    {
	output_message "$code $label";
	output_message $_ foreach @details;
	return;
    }
    
    # Otherwise, open the correct log file and read the prior state of this
    # entry.
    
    SelectLog($name, $params);
    
    my $prior = ReadState($name, $params);
    
    # Generate a summary which lists the use percentage of every volume that is
    # at or over its limit. This will be used to generate the new status. If
    # none of the volumes are at or over limit, @details will be empty.
    
    my $summary = join ' - ', @details;
    my $new = "$code|$summary|$label";
    
    # If the summary has changed, this means that either a volume has newly
    # reached the limit, a volume has gone back under the limit, or else the use
    # percentage of a volume over the limit has changed. In either case, the
    # user will want a notification.
    
    if ( $new ne $prior )
    {
	log_message "$code $label";
	output_message $_ foreach @details;
	write_log join ' - ', @details if @details;
	write_state $new;
	return;
    }
    
    # If we are running in report mode, generate a notification. Note that if we
    # reach this branch then the state hasn't changed, so there is no reason to
    # modify the state file.
    
    elsif ( $REPORT )
    {
	log_message "$code $label";
	output_message $_ foreach @details;
	write_log join ' - ', @details if @details;
	return;
    }
    
    else
    {
	write_log "$code $label";
	return;
    }
}


# CheckTest ( name, parameters )
# 
# A check of this type is used for testing purposes. The first time it is
# executed, the status will be OK. If the entry parameter 'cycle' has a positive
# value, then for that many subsequent executions the status will be ERR before
# returning to 'OK'. Subsequent executions will repeat the cycle. If the
# parameter 'cycle' does not have a positive value, the status will always be
# OK.

sub CheckTest {
    
    my ($name, $params) = @_;
    
    # Look up the parameters relevant to this entry.
    
    my $cycle = $params->{cycle} > 0 ? $params->{cycle} + 0 : 0;
    my $label = $params->{label} || $name;
    
    # If we are running in check mode, generate output for a status of CHECK.
    
    if ( $CHECK )
    {
	output_message "CHECK $label";
	return;
    }
    
    # Otherwise, open the correct log file and read the prior state of this
    # entry.
    
    SelectLog($name, $params);
    
    my $prior = ReadState($name, $params);
    
    my ($pstate, $pcount) = split /[|]/, $prior;
    
    # If the prior state is 'INIT', the new state will be OK.
    
    if ( $pstate eq 'INIT' )
    {
	log_message "OK $label";
	write_state "OK||$label";
	return;
    }
    
    # If the prior state is 'OK', the new state will be 'ERR' if $cycle is
    # greater than zero.
    
    elsif ( $pstate eq 'OK' && $cycle )
    {
	log_message "ERR 1 $label";
	write_state "ERR|1|$label";
	return;
    }
    
    # If the prior state is 'OK' and we are not cycling, generate output only if
    # we are running in report mode.
    
    elsif ( $pstate eq 'OK' )
    {
	output_message "OK $label" if $REPORT;
	write_log "OK $label";
	return;
    }
    
    # Otherwise, we are in the ERR part of the cycle. If the count does not
    # exceed the value of the cycle parameter, generate output only if we are
    # running in report mode.
    
    my $count = $pcount + 1;
    
    if ( $count <= $cycle )
    {
	output_message "ERR $count $label" if $REPORT;
	write_log "ERR $count $label";
	write_state "ERR|$count|$label";
    }
    
    # When the count reaches the value of the cycle parameter, set the state
    # back to OK.
    
    else
    {
	log_message "OK $label";
	write_state "OK||$label";
    }
}


# SendNotifications ( )
# 
# Send all notifications that have been generated so far.

sub SendNotifications {
    
    # Generate a subject for the notification message. If all of the check
    # results are OK, the subject will be either 'Notify OK', 'Report OK', or
    # 'Check OK'. Otherwise, it will contain a list of the abnormal result
    # codes. 
    
    my %conditions;
    
    foreach my $n ( @NOTIFICATIONS )
    {
	if ( $n =~ /^(\w+)/ )
	{
	    $conditions{$1} = 1 unless $1 eq 'OK';
	}
    }
    
    my $summary = %conditions ? join(', ', keys %conditions) : 'OK';
    
    my $action = $CHECK  ? 'Check'
	       : $REPORT ? 'Report'
	       :           'Notify';
    
    my $recipients = $CONFIG->{sendmail};
	
    # If we are running in report mode and sendmail_report is also set, use
    # that instead.
    
    if ( $REPORT && $CONFIG->{sendmail_report} )
    {
	$recipients = $CONFIG->{sendmail_report};
    }
    
    # If the 'sendmail' configuration variable was set, and we are not running
    # in check mode, send the notifications directly via sendmail.
    
    if ( $recipients && ! $CHECK )
    {
	say STDERR "Sending notifications to: $recipients" if $VERBOSE;
	
	# Open a pipe to sendmail, and send the notifications.
	
	open(my $sendmail, '|-', "sendmail $recipients") or 
	    die "ERROR: could not run sendmail: $!\n";
	
	say $sendmail "From: $CONFIG->{from}" if $CONFIG->{from};
	say $sendmail "Subject: $action $summary";
	say $sendmail "";
	
	say $sendmail $_ foreach @NOTIFICATIONS;
	
	close $sendmail;
    }
    
    # Otherwise, write the notifications to STDOUT.
    
    else
    {
	say STDOUT "Skipping notification to: $recipients" if $CHECK;
	say STDOUT "$action $summary";
	say STDOUT $_ foreach @NOTIFICATIONS;
    }
}


# ComputeElapsed ( time, prevtime )
# 
# Return a string giving the difference between the first argument and the
# second in seconds (s) if less than 60, or in minutes (m) if less than 3600,
# in hours (h) if less than 86400, or in days.

sub ComputeElapsed {
    
    my ($time, $ptime) = @_;
    
    return '?' unless $time > 0 && $ptime > 0 && $time > $ptime;
    
    my $diff = $time - $ptime;
    
    if ( $diff < 60 )
    {
	return "${diff}s";
    }
    
    elsif ( $diff < 3600 )
    {
	my $min = int($diff/60);
	return "${min}m";
    }
    
    elsif ( $diff < 86400 )
    {
	my $hrs = int($diff/3600);
	return "${hrs}h";
    }
    
    else
    {
	my $days = int($diff/86400);
	return "${days}d";
    }
}


# ReadState ( name, parameters )
# 
# Read the state file for the specified entry, and return its contents.

sub ReadState {
    
    my ($name, $params) = @_;
    
    # If no name is given, the state file defaults to nnn_state.txt, where nnn
    # is the name of the entry being checked.
    
    my $filename = $params->{state_file} || "${name}_state.txt";
    
    # Make sure that each entry has a different state file.
    
    if ( $state_uniq{$filename} && $state_uniq{$filename} ne $name )
    {
	die "ERROR: '$state_uniq{$filename}' and '$name' have the same state file '$filename'\n";
    }
    
    $state_uniq{$filename} = $name;
    
    # If 'state_dir' is specified in the configuration file, then state files
    # are located in that directory. Otherwise, they are located in the log
    # directory.
    
    my $dir = $state_dir || $log_dir;
    
    $state_file = resolve_name($filename, $dir);
    
    my $state_fh;
    
    # If the file does not exist, create it now. The initial state will be
    # 'INIT'.
    
    unless ( -e $state_file )
    {
	open($state_fh, ">", $state_file) 
	    or die "ERROR: cannot create $state_file: $!\n";
	
	say $state_fh "INIT";
	close($state_fh);
    }
    
    # Read and return the contents of the state file. Throw an exception if the
    # file is not readable or not writable.
    
    -w $state_file
	or die "ERROR: cannot write $state_file: $!\n";
    
    open($state_fh, "<", $state_file) 
	or die "ERROR: cannot read $state_file: $!\n";
    
    my $state = <$state_fh>;
    
    close $state_fh;
    
    chomp $state;
    
    return $state;
}


# write_state ( new_state )
# 
# If we are running in notify mode, Write the specified contents to
# the file $state_file. If we are in report or check mode, do nothing.

sub write_state {
    
    my ($new_state) = @_;
    
    return if $REPORT || $CHECK;
    
    open(my $state_fh, ">", $state_file)
	or die "ERROR: cannot write $state_file: $!\n";
    
    say $state_fh $new_state;
    
    close $state_fh
	or die "ERROR: could not write $state_file: $!\n";
}


# SelectLog ( name, parameters )
# 
# Select the proper log file for the specified entry. If that file is already
# open, then leave it. Otherwise, close the open log file (if any) and open this
# one.

sub SelectLog {
    
    my ($name, $params) = @_;
    
    my $filename = $params->{log_file} || $default_log;
    
    my $this_log = resolve_name($filename, $log_dir);
    
    # If this log is already open, we are done. Otherwise, close the currently
    # open log file if any and open the new one.
    
    unless ( $log_file eq $this_log )
    {
	close $log_fh if $log_fh;
	
	$log_file = $this_log;
	
	open $log_fh, '>>', $log_file
	    or die "ERROR: could not write to $log_file: $!\n";
    }
}


# output_message ( message )
# 
# Add the specified line to the output of this command.

sub output_message {
    
    my ($message) = @_;
    
    push @NOTIFICATIONS, $message;
}


# log_message ( message )
# 
# Add the specified line to the output of this command, and also write it to the
# current log file.

sub log_message {
    
    my ($message) = @_;
    
    push @NOTIFICATIONS, $message;
    say $log_fh "[$timestamp] $REPORT$message" if $log_fh;
}


# write_log ( message )
# 
# Write the specified line to the current log file, but don't add it to the
# output.

sub write_log {
    
    my ($message) = @_;
    
    say $log_fh "[$timestamp] $REPORT$message" if $log_fh;    
}


# resolve_name ( name, directory )
# 
# If the specified name is an absolute path or starts with ./ or ../, then
# return it unchanged. Otherwise, return the name relative to the specified
# directory.

sub resolve_name {
    
    my ($filename, $dir) = @_;
    
    if ( $filename =~ qr{ ^[/] | ^ [.][/] | & [.][.][/] }xs )
    {
	return $filename;
    }
    
    else
    {
	return "$dir/$filename";
    }
}



# help_message ( )
# 
# Print out a help message and exit.

sub help_message {
    
    my $pager = $ENV{PAGER};
    
    if ( ! $pager && `which less` )
    {
	$pager = 'less';
    }
    
    else
    {
	$pager = 'more';
    }
    
    my $message = <<END_HELP;

Usage:

  webcheck.pl [options] [arguments]

Check the health of local or remote services. This program is intended to be run
as a cron job, in order to notify responsible personnel when a server is down or
having problems. If arguments are provided, they cause the corresponding status
checks from the configuration file to be performed. With no arguments, all
configured status checks are performed.

Options:

  --file, -f        Use the specified configuration file. The default is
                    ./webcheck.yml.

  --report, -r      Perform the specified checks in the normal way, but report
                    all results instead of only status changes and followups.

  --check, -c       Perform the specified checks without logging or saving
                    state. Report all results.

  --help, -h        Print this message.


Description:

The status checks to be performed are specified by entries in the configuration
file. The format of this file is given below.

The default operation mode is 'notify'. In this mode, each status check result
is appended to a log file. Output is only generated when the status changes, or
when an abnormal condition persists. By running under a crontab entry with the
MAILTO variable set, this output can be sent as a notification to an email inbox
or a text-message gateway. The generated output is formatted to be useful when
received as a text message. As long as the status remains normal, no output is
generated.

In report mode (specified by --report) output is generated for each status check
result even if the status is unchanged. The state is checked but not updated, so
that the next execution in notify mode will properly notify any changed
statuses. This mode can be used periodically to test that the system is working,
in situations where the status of all services remains unchanged for long
periods of time.

The state of each checked service is stored in a state file. The motivation for
the state files, and for this program in general, is to provide for quick
notification when the status of a service changes, without flooding the
responder with notifications if an abnormal condition persists for hours. It is
recommended to run this program every 10 minutes, or as often as necessary for
prompt notification of problems. The 'followup' parameter can be used to provide
additional notifications when an abnormal condition persists.

In check mode (specified by --check) output is generated for each status check
result but nothing is written to the log or to the state files.


Configuration file:

The configuration file must be in YAML format. The status check entries must
be listed under the top level key 'checks'. The following top level keys are
also allowed, with the values interpreted as follows:

  log_file          The name of the log file, defaults to 'webcheck.log'.

  log_dir           The directory in which the log file is located, defaults
                    to '.'

  state_dir         The directory in which the state files are located,
                    defaults to the value of log_dir.

  sendmail          Send any generated notifications to the specified e-mail
                    address(es) directly using sendmail. If this setting is
                    specified, then no output is produced. However, when
                    running in check mode, this setting is ignored and standard
                    output is produced instead.

  from              Sets the 'From' header if used along with 'sendmail'. It
                    can be set to any valid e-mail address. Note that the
                    envelope sender is unaffected.

  url_command       The command to be used for checking remote services.
                    It should contain a '%' character, which will be
                    substituted with the url for each entry. The default
                    is "curl --head --silent '%'".

  url_followup      The value must be a list of numbers. For example, if
                    the value is '2 10', if an abnormal condition persists
                    for two or more executions of this program, a followup
                    notification will be sent on the 2nd and 10th executions.

  
Three types of entries are allowed. Any values specified in an entry override
the corresponding top level values for that entry only.

Remote service check

  An entry of this type must include the key 'url'. The specified command is
  used to fetch the specified URL, and the response is checked for the standard
  http response. A response code of 200 is considered normal, anything else
  is abnormal. The following keys are accepted:

  url               The url to be checked (mandatory)

  command           A command to be executed for this entry only

  followup          A followup pattern for this entry only

  label             A label string used for generating output, defaults
                    to the entry name.

  log_file          Log this entry to the specified file instead of to the main
                    one.

  state_file        Save the state to the specified file. Default is
                    <entry name>_state.txt.

Disk space check

  An entry of this type must include the key 'limit'. The command to be run
  defaults to 'df', and the output is scanned for volumes whose use% meets or
  exceeds the specified threshold. The following keys are accepted:

  limit             The threshold for notification of use%

  limit_/var        The threshold for notification of a particular volume,
                    in this case /var.

  command           A command to be executed, defaults to 'df'.

  label             A label string used for generating output, defaults
                    to the entry name.

  log_file          Log this entry to the specified file instead of to the main
                    one.

  state_file        Save the state to the specified file. Default is
                    <entry name>_state.txt.

Test entry

  An entry of this type must include the key 'cycle'.

  cycle             If the value is greater than zero, the result will cycle
                    from 'OK' to 'ERR', and will repeat for that number of
                    executions before returning to 'OK'. If the value is zero,
                    the result will be 'OK' on every execution.

  label             A label string used for generating output, defaults
                    to the entry name.

  log_file          Log this entry to the specified file instead of to the main
                    one.

  state_file        Save the state to the specified file. Default is
                    <entry name>_state.txt.

END_HELP
    
    if ( open(my $ofh, '|-', $pager) )
    {
	print $ofh $message;
    }
    
    else
    {
	print $message;
    }
}


