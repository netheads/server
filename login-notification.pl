#!/usr/bin/perl

use strict;
use warnings;

use Email::Valid;
use MIME::Lite;
use String::Util qw(trim);

if (not @ARGV or not Email::Valid->address($ARGV[0])) {
	die "First argument must be a valid mail address\n";
}

my $date = trim(scalar `date`);
my $who = trim(scalar `who -a`);

my $whoami = trim(scalar `whoami`);
my $hostname = trim(scalar `hostname --long`);
 
my $mail = MIME::Lite->new(
	From => $whoami . '@' . $hostname,
	To => $ARGV[0],
	Subject => "Login on $hostname with user $whoami",
	Type => 'multipart/mixed',
);

$mail->attach(
	Type => 'TEXT',
	Data => "$date\n\n$who\n\n",
);

$mail->send;
