#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 0.1;

use feature ':5.12';

use Digest::MD5;
use File::Slurp;
use File::Temp qw(tempfile);
use Getopt::Compact;

BEGIN {
	$SIG{'__DIE__'} = $SIG{'__WARN__'} = sub {
		print($_[0]);
		write_file('nethead-mail-spam-pipe-error', $_[0]);
		
		exit;
	};
}

sub options_validate {
	my ($opts) = @_;

	if (not $opts->{path}) {
		die "Argument \"path\" is needed.";
	}
	elsif (not $opts->{ham} and not $opts->{spam}) {
		die "Argument \"ham\" or \"spam\" is needed.";
	}
	
	$opts->{path} =~ s/(.+)\/+$/$1/sg;
	
	if (not -d $opts->{path}) {
		mkdir $opts->{path} or die "Cannot create folder $opts->{path}.";
	}
	if (not -d $opts->{path} . '/spam') {
		mkdir $opts->{path} . '/spam' or die "Cannot create folder $opts->{path}/spam.";
	}
	if (not -d $opts->{path} . '/ham') {
		mkdir $opts->{path} . '/ham' or die "Cannot create folder $opts->{path}/ham.";
	}
	
	return 1;
}

my $options = Getopt::Compact->new(
	name => 'Nethead Mail Spam Pipe',
	struct => [
		[ 'path', 'The base path', ':s' ],
		[ 'ham', 'Move the input as ham' ],
		[ 'spam', 'Move the input as spam' ],
	]
);

my $opts = $options->opts();

if (not $options->status() or not options_validate($opts)) {
	die $options->usage();
}

my ($file, $file_temp) = tempfile( DIR => $opts->{path} );
my $md5 = Digest::MD5->new;

if (not $file) {
	die "Cannot open temp file $file_temp.";
}

while (<>) {
	print $file $_;
	
	$md5->add($_);
}

close $file or die "Cannot close temp file $file_temp.";

my $md5_sum = $md5->hexdigest();

my $file_ham = $opts->{path} . '/ham/' . $md5_sum;
my $file_spam = $opts->{path} . '/spam/' . $md5_sum;

if ($opts->{ham}) {
	if (-f $file_spam) {
		unlink $file_spam or die "Cannot remove spam file $file_spam.";
	}

	if (not -f $file_ham) {
		rename $file_temp, $file_ham or die "Cannot rename temp file $file_temp to ham file $file_ham.";
	}
	else {
		unlink $file_temp or die "Cannot remove temp file $file_temp.";
	}
}
elsif ($opts->{spam}) {
	if (-f $file_ham) {
		unlink $file_ham or die "Cannot remove ham file $file_ham.";
	}

	if (not -f $file_spam) {
		rename $file_temp, $file_spam or die "Cannot rename temp file $file_temp to spam file $file_spam.";
	}
	else {
		unlink $file_temp or die "Cannot remove temp file $file_temp.";
	}
}
else {
	die "WTF\n";
}

# IT IS IMPORTANT THAT WE RETURN HERE A SANE EXIT CODE OR OTHERWISE THE MAIL IS COPIED __NOT__ MOVED !!!
