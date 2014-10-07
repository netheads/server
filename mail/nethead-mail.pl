#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 0.1;

use feature ':5.12';

use DBI;
use Digest::MD5 qw(md5_hex);
use Email::Valid;
use File::Slurp;
use Getopt::Compact;
use IO::Prompt;
use Text::TabularDisplay;

my $DKIM_PATH = '/etc/exim/dkim';
my $MAIL_PATH = '/srv/mail';
my $MAX_QUOTA = 8192;

sub system_cmd {
	system(@_) == 0 or die "\"@_\" failed: $?";
}

sub linux_users {
	my %users = ();
	my @text = read_file('/etc/passwd');

	for my $i(@text) {
		my @a = split(/:/, $i);

		$users{$a[0]} = {
			name => $a[0],
			uid => $a[2],
		};
	}

	return \%users;
}

sub linux_user_groups {
	my %groups = ();
	my @text = read_file('/etc/group');


	for my $i(@text) {
		my @a = split(/:/, $i);

		$groups{$a[0]} = {
			name => $a[0],
			gid => $a[2],
			users => [ split(/,/, $a[3]) ],
		};
	}

	return \%groups;
}

sub options_validate {
	my ($opts) = @_;

	return 1;
}

my $options = Getopt::Compact->new(
	name => 'Nethead Mail Management',
	struct => [
		[ 'add-alias', 'Add an alias' ],
		[ 'add-dkim', 'Add a DKIM certificate' ],
		[ 'add-domain', 'Add a domain' ],
		[ 'add-user', 'Add an user' ],
		[ 'list-aliases', 'List all aliases' ],
		[ 'list-domains', 'List all domains' ],
		[ 'list-users', 'List all users' ],
	]
);

my $opts = $options->opts();

if (not $options->status() or not options_validate($opts)) {
	print $options->usage();

	exit 0;
}

my $dbh = DBI->connect('dbi:Pg:dbname=maildb', '', '', { AutoCommit => 0, RaiseError => 1 });

if ($opts->{'add-alias'}) {
	my ($destination, $source, $source_account, $source_domain, $source_domain_row);

	while (my $in = prompt(-prompt => 'Enter source mail address: ')) {
		next if not $in;

		if (not ($source = Email::Valid->address($in))) {
			say "\"$in\" is not a valid mail address\n";

			next;
		}

		$source = lc $source;

		$source =~ m/\A(.+)@(.+)\z/;

		$source_account = $1;
		$source_domain = $2;

		if (length $source_account > 40) {
			say "Source account can only have a maximum of 40 chars\n";

			next;
		}

		if (not ($source_domain_row = $dbh->selectrow_hashref('SELECT d.id FROM virtual_domains d WHERE d.name = ?', undef, $source_domain))) {
			say "Domain \"$source_domain\" does not exists\n";

			next;
		}

		last;
	}

	while (my $in = prompt(-prompt => 'Enter destination mail address: ')) {
		next if not $in;

		if (not ($destination = Email::Valid->address($in))) {
			say "\"$in\" is not a valid mail address\n";

			next;
		}

		if (length $source > 80) {
			say "Source mail address can only have a maximum of 80 chars\n";

			next;
		}

		$destination = lc $destination;

		if ($dbh->selectrow_hashref('SELECT a.id FROM virtual_aliases a WHERE a.source = ? AND a.domain = ? AND a.destination = ?', undef, $source_account, $source_domain_row->{id}, $destination)) {
			say "Alias \"$source\" to \"$destination\" does already exist\n";

			next;
		}

		last;
	}

	$dbh->do('INSERT INTO virtual_aliases(domain, source, destination) VALUES(?, ?, ?)', undef, $source_domain_row->{id}, $source_account, $destination);
	$dbh->commit();
}
elsif ($opts->{'add-dkim'}) {
	my ($domain, $domain_row);

	while ($domain = prompt(-prompt => 'Enter domain: ')) {
		next if not $domain;

		if (not Email::Valid->address('a@' . $domain)) {
			say "\"$domain\" is not a valid domain\n";

			next;
		}

		$domain = lc $domain;

		if (not ($domain_row = $dbh->selectrow_hashref('SELECT d.id, d.quota_mb FROM virtual_domains d WHERE d.name = ?', undef, $domain))) {
			say "Domain \"$domain\" does not exists\n";

			next;
		}

		last;
	}

	system_cmd('sudo', 'openssl', 'genrsa', '-out', "$DKIM_PATH/$domain.pem", 768);
	system_cmd('sudo', 'openssl', 'rsa', '-in', "$DKIM_PATH/$domain.pem", '-out', "$DKIM_PATH/$domain-public.pem", '-pubout', '-outform', 'PEM');
	system_cmd('sudo', 'chown', 'root:mail', "$DKIM_PATH/$domain.pem");
	system_cmd('sudo', 'chmod', '640', "$DKIM_PATH/$domain.pem");
	system_cmd('sudo', 'chown', 'root:mail', "$DKIM_PATH/$domain-public.pem");
	system_cmd('sudo', 'chmod', '640', "$DKIM_PATH/$domain-public.pem");
}
elsif ($opts->{'add-domain'}) {
	my ($domain, $quota_mb, $system_gid, $system_uid);

	while ($domain = prompt(-prompt => 'Enter domain: ')) {
		next if not $domain;

		if (not Email::Valid->address('a@' . $domain)) {
			say "\"$domain\" is not a valid domain\n";

			next;
		}

		$domain = lc $domain;

		if (length $domain > 40) {
			say "Domain can only have a maximum of 40 chars\n";

			next;
		}

		if ($dbh->selectrow_hashref('SELECT d.id FROM virtual_domains d WHERE d.name = ?', undef, $domain)) {
			say "Domain \"$domain\" does already exists\n";

			next;
		}

		last;
	}

	while ($quota_mb = prompt(-prompt => 'Enter quota (1-' . $MAX_QUOTA . ' or 0 for no quota): ', -integer)) {
		$quota_mb = 0 if not $quota_mb;

		if ($quota_mb < 0 or $quota_mb > $MAX_QUOTA) {
			say "Quota can only range from 1 to $MAX_QUOTA\n";

			next;
		}

		last;
	}

	my $linux_user_groups = linux_user_groups();

	if (not exists $linux_user_groups->{$domain}) {
		system_cmd('sudo', 'groupadd', $domain);

		$linux_user_groups = linux_user_groups();
	}

	$system_gid = $linux_user_groups->{$domain}->{gid};

	my $linux_users = linux_users();

	my $user_name = 'm.' . $domain;

	if (not exists $linux_users->{$user_name}) {
		system_cmd('sudo', 'useradd', '-d', "$MAIL_PATH/$domain", '-g', $system_gid, '-G', $system_gid, '-U', '077', '-s', '/bin/false', $user_name);
		system_cmd('sudo', 'passwd', $user_name); # set password
		system_cmd('sudo', 'passwd', '-l', $user_name); # disable login

		$linux_users = linux_users();
	}

	$system_uid = $linux_users->{$user_name}->{uid};

	system_cmd('sudo', 'mkdir', "$MAIL_PATH/$domain");
	system_cmd('sudo', 'chown', '-R', "$user_name:mailfolder", "$MAIL_PATH/$domain");
	system_cmd('sudo', 'chmod', '-R', '750', "$MAIL_PATH/$domain");

	system_cmd('sudo', 'setquota', '-u', $system_uid, ($quota_mb * 1024), ($quota_mb * 1024), 0, 0, $MAIL_PATH);

	$dbh->do('INSERT INTO virtual_domains(name, quota_mb, system_gid, system_uid) VALUES(?, ?, ?, ?)', undef, $domain, $quota_mb, $system_gid, $system_uid);
	$dbh->commit();

	say "Do not forget to add the DKIM certificate!";
}
elsif ($opts->{'add-user'}) {
	my ($password, $quota_mb, $user, $user_account, $user_domain, $user_domain_row);

	while (my $in = prompt(-prompt => 'Enter user mail address: ')) {
		next if not $in;

		if (not ($user = Email::Valid->address($in))) {
			say "\"$in\" is not a valid mail address\n";

			next;
		}

		$user = lc $user;

		$user =~ m/\A(.+)@(.+)\z/;

		$user_account = $1;
		$user_domain = $2;

		if (length $user > 40) {
			say "User account can only have a maximum of 40 chars\n";

			next;
		}

		if (not ($user_domain_row = $dbh->selectrow_hashref('SELECT d.id, d.quota_mb FROM virtual_domains d WHERE d.name = ?', undef, $user_domain))) {
			say "Domain \"$user_domain\" does not exists\n";

			next;
		}

		if ($dbh->selectrow_hashref('SELECT u.id FROM virtual_users u WHERE u.account = ? AND u.domain = ?', undef, $user_account, $user_domain_row->{id})) {
			say "Alias \"$user\" does already exist\n";

			next;
		}

		last;
	}

	while ($password = prompt(-prompt => 'Enter password: ', -echo => '*')) {
		next if not $password;

		if (length $password < 5) {
			say "Password must have at least 5 chars\n";

			next;
		}

		last;
	}

	if ($user_domain_row->{quota_mb}) {
		while ($quota_mb = prompt(-prompt => 'Enter quota (1-' . $user_domain_row->{quota_mb} . ' or 0 for no quota): ', -integer)) {
			$quota_mb = 0 if not $quota_mb;

			if ($quota_mb < 0 or $quota_mb > $user_domain_row->{quota_mb}) {
				say "Quota can range from 1 to $user_domain_row->{quota_mb}\n";

				next;
			}

			last;
		}
	}
	else {
		$quota_mb = 0;
	}

	$dbh->do('INSERT INTO virtual_users(domain, account, password, quota_mb) VALUES(?, ?, ?, ?)', undef, $user_domain_row->{id}, $user_account, md5_hex($password), $quota_mb);
	$dbh->commit();
}
elsif ($opts->{'list-aliases'}) {
	my $table = Text::TabularDisplay->new('domain', 'source', 'destination', 'active');

	for my $i(@{$dbh->selectall_arrayref(
		'SELECT d.name, a.source, a.destination, a.active FROM virtual_aliases a JOIN virtual_domains d ON a.domain = d.id ORDER BY d.name, a.source, a.destination'
	)}) {
		$table->add(@$i);
	}

	if ($table->items) {
		say $table->render;
	}
	else {
		say 'No aliases defined';
	}
}
elsif ($opts->{'list-domains'}) {
	my $table = Text::TabularDisplay->new('domain', 'quota', 'system gid', 'system uid', 'active');

	for my $i(@{$dbh->selectall_arrayref(
		'SELECT d.name, d.quota_mb, d.system_gid, d.system_uid, d.active FROM virtual_domains d ORDER BY d.name'
	)}) {
		$table->add(@$i);
	}

	if ($table->items) {
		say $table->render();
	}
	else {
		say 'No domains defined';
	}
}
elsif ($opts->{'list-users'}) {
	my $table = Text::TabularDisplay->new('domain', 'source', 'quota', 'active');

	for my $i(@{$dbh->selectall_arrayref(
		'SELECT d.name, u.account, u.quota_mb, u.active FROM virtual_users u JOIN virtual_domains d ON u.domain = d.id ORDER BY d.name, u.account'
	)}) {
		$table->add(@$i);
	}

	if ($table->items) {
		say $table->render;
	}
	else {
		say 'No users defined';
	}
}
else {
	print $options->usage();
}

$dbh->disconnect();

exit 1;
