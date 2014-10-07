#!/usr/bin/perl

use strict;
use warnings;

use feature ':5.12';

our $VERSION = 1.0;

use File::Path qw(mkpath);
use File::Slurp;
use SVN::Access;
use Text::TabularDisplay;

my $SVN_ACCESS_CONFIG = exists $ENV{SVN_ACCESS_CONFIG} ? $ENV{SVN_ACCESS_CONFIG} : '/srv/svn/config/access.conf';
my $SVN_REPOSITORIES_PATH = exists $ENV{SVN_REPOSITORIES_PATH} ? $ENV{SVN_REPOSITORIES_PATH} : '/srv/svn/repositories/';
my $SVN_USERS_CONFIG = exists $ENV{SVN_USERS_CONFIG} ? $ENV{SVN_USERS_CONFIG} : '/srv/svn/config/user.list';

my $SVN_USER = exists $ENV{SVN_USER} ? $ENV{SVN_USER} : 'website.svn.nethead.at';
my $SVN_USER_GROUP = exists $ENV{SVN_USER_GROUP} ? $ENV{SVN_USER_GROUP} : 'svn.nethead.at';

my $svn;

if ($SVN_REPOSITORIES_PATH !~ m/\/$/) {
	$SVN_REPOSITORIES_PATH .= '/';
}

sub init_svn {
	if (not -f $SVN_ACCESS_CONFIG) {
		print "ERROR: Cannot find access config \"$SVN_ACCESS_CONFIG\"\n";

		exit -2;
	}
	elsif (not -d $SVN_REPOSITORIES_PATH) {
		print "ERROR: Cannot find repositories folder \"$SVN_REPOSITORIES_PATH\"\n";

		exit -2;
	}
	elsif (not -f $SVN_USERS_CONFIG) {
		print "ERROR: Cannot find users config \"$SVN_USERS_CONFIG\"\n";

		exit -2;
	}

	$svn = SVN::Access->new( acl_file => $SVN_ACCESS_CONFIG );

	if (not $svn) {
		print "ERROR: Cannnot initialize SVN:Access object\n";

		exit -3;
	}
};

sub check_group_name {
	my ($name, $message) = @_;

	if ($name !~ m/^[\da-zA-Z-_]+$/) {
		if ($message) {
			print "ERROR: \"$name\" is not a valid group name. A group name can have only digits, letters and [-_.].\n";
		}

		return 0;
	}

	return 1;
}

sub check_repository_name {
	my ($name, $message) = @_;

	if ($name !~ m/^[\da-zA-Z-_.]+$/) {
		if ($message) {
			print "ERROR: \"$name\" is not a valid repository name. A repository name can have only digits, letters and [-_.].\n";
		}

		return 0;
	}

	return 1;
}

sub check_user_name {
	my ($name, $message) = @_;

	if ($name !~ m/^[\da-zA-Z-_.]+$/) {
		if ($message) {
			print "ERROR: \"$name\" is not a valid user name. A user name can have only digits, letters and [-_.].\n";
		}

		return 0;
	}

	return 1;
}

sub get_users {
	my %users = ();

	for my $line(read_file($SVN_USERS_CONFIG)) {
		my $name = $line;

		if ($name=~ s/^(.+?):.+$/$1/sg) {
			$users{$name} = 1;
		}
	}

	return \%users;
}

my @options = (
	{
		option => [ 'add', 'group', { type => 's', name => 'group' } ],
		description => 'Add a group',
		exec => sub {
			my ($group_name) = @_;

			init_svn();

			if (not check_group_name($group_name, 1)) {
				exit -4;
			}

			if ($svn->group($group_name)) {
				print "ERROR: Group \"$group_name\" does already exists.\n";
			}
			else {
				$svn->add_group($group_name);
				$svn->write_acl();
			}
		},
	},
	{
		option => [ 'add', 'group', { type => 's', name => 'group' }, 'to', 'repository', { type => 's', name => 'repository' }, 'with', 'right', { type => [ 'r', 'rw' ], name => 'right' } ],
		description => 'Add a group to a repository',
		exec => sub {
			my ($group_name, $repository_name, $right) = @_;

			init_svn();

			if (not $svn->group($group_name)) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			$repository->authorize('@' . $group_name => $right);
			$svn->write_acl();
		},
	},
	{
		option => [ 'add', 'repository', { type => 's', name => 'repository' } ],
		description => 'Add a repository',
		exec => sub {
			my ($repository_name) = @_;

			init_svn();

			if (not check_repository_name($repository_name, 1)) {
				exit -3;
			}

			if ($svn->resource($repository_name . ':/')) {
				print "Repository \"$repository_name\" access entry does already exists.\n";
			}
			else {
				$svn->add_resource($repository_name . ':/');
				$svn->write_acl();
			}

			if (-d $SVN_REPOSITORIES_PATH . $repository_name) {
				print "Repository \"$repository_name\" folder does already exists. No need to create it.\n";
			}
			else {
				system_cmd('svnadmin', 'create', $SVN_REPOSITORIES_PATH . $repository_name);

				# we need this folder because of the webdav access otherwhise we cannot backup the repository.
				mkpath($SVN_REPOSITORIES_PATH . $repository_name . '/dav/activities.d');

				system_cmd('chown', '-R', "$SVN_USER:$SVN_USER_GROUP", $SVN_REPOSITORIES_PATH . $repository_name);
				system_cmd('chmod', '-R', '770', $SVN_REPOSITORIES_PATH . $repository_name);
			}
		},
	},
	{
		option => [ 'add', 'user', { type => 's', name => 'user' } ],
		description => 'Add an user',
		exec => sub {
			my ($user_name) = @_;

			init_svn();

			if (not check_user_name($user_name, 1)) {
				exit -4;
			}

			if (exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does already exists.\n";
			}
			else {
				system_cmd('htpasswd2', '-m', $SVN_USERS_CONFIG, $user_name);
			}
		},
	},
	{
		option => [ 'add', 'user', { type => 's', name => 'user' }, 'to', 'group', { type => 's', name => 'group' } ],
		description => 'Add an user to a group',
		exec => sub {
			my ($user_name, $group_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			my $group = $svn->group($group_name);

			if (not $group) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			$group->add_member($user_name);
			$svn->write_acl();
		},
	},
	{
		option => [ 'add', 'user', { type => 's', name => 'user' }, 'to', 'repository', { type => 's', name => 'repository' }, 'with', 'right', { type => [ 'r', 'rw' ], name => 'right' } ],
		description => 'Add an user to a repository',
		exec => sub {
			my ($user_name, $repository_name, $right) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			$repository->authorize($user_name => $right);
			$svn->write_acl();
		},
	},
	{
		option => [ 'help' ],
		description => 'Display usage',
		exec => sub { print_usage(); },
	},
	{
		option => [ 'list', 'groups' ],
		description => 'List all groups',
		exec => sub {
			init_svn();

			my $table = Text::TabularDisplay->new('Name', 'Members');

			my @rows = ();

			for ($svn->groups()) {
				next if not $_;

				push(@rows, [ $_->name, join(', ', sort $_->members) ]);
			}

			if (@rows) {
				for my $row(sort { $a->[0] cmp $b->[0] } @rows) {
					$table->add(@$row);
				}

				print $table->render(), "\n";
			}
			else {
				print "No groups found\n";
			}
		},
	},
	{
		option => [ 'list', 'repositories' ],
		description => 'List all repositories',
		exec => sub {
			init_svn();

			my $table = Text::TabularDisplay->new('Name', 'Members');

			my @rows = ();

			for ($svn->resources()) {
				next if not $_;

				my $name = $_->name;

				$name=~ s/(.+):\/\z/$1/sg;

				my %authorized = %{$_->authorized};

				push(@rows, [ $name, join(', ', sort map { "$_ = $authorized{$_}" } keys %authorized) ]);
			}

			if (@rows) {
				for my $row(sort { $a->[0] cmp $b->[0] } @rows) {
					$table->add(@$row);
				}

				print $table->render(), "\n";
			}
			else {
				print "No repositories found\n";
			}
		},
	},
	{
		option => [ 'list', 'users' ],
		description => 'List all users',
		exec => sub {
			init_svn();

			my $table = Text::TabularDisplay->new('Name');

			my @rows = ();

			for my $user_name(keys %{get_users()}) {
				push(@rows, [ $user_name ]);
			}

			if (@rows) {
				for my $row(sort { $a->[0] cmp $b->[0] } @rows) {
					$table->add(@$row);
				}

				print $table->render(), "\n";
			}
			else {
				print "No users found\n";
			}
		},
	},
	{
		option => [ 'modify', 'group', { type => 's', name => 'group' }, 'name', 'to', { type => 's', name => 'name' } ],
		description => 'Modify the name of a group',
		exec => sub {
			my ($group_name, $group_new_name) = @_;

			init_svn();

			my $group = $svn->group($group_name);

			if (not $group) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			if (not check_group_name($group_new_name, 1)) {
				exit -4;
			}

			if ($svn->group($group_new_name)) {
				print "ERROR: Group \"$group_new_name\" does already exists.\n";

				exit -4;
			}

			my $group_new = $svn->add_group($group_new_name);

			for ($group->members()) {
				next if not $_;

				$group_new->add_member($_);
			}

			for ($svn->resources()) {
				next if not $_;

				my $authorized = $_->authorized();

				if (exists $authorized->{'@' . $group_name}) {
					$_->authorize('@' . $group_new_name => $authorized->{'@' . $group_name});
					$_->deauthorize('@' . $group_name);
				}
			}

			$svn->remove_group($group_name);

			$svn->write_acl();
		},
	},
	{
		option => [ 'modify', 'repository', { type => 's', name => 'repository' }, 'name', 'to', { type => 's', name => 'name' } ],
		description => 'Modify the name of a repository',
		exec => sub {
			my ($repository_name, $repository_new_name) = @_;

			init_svn();

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			if (not check_repository_name($repository_new_name, 1)) {
				exit -3;
			}

			if ($svn->resource($repository_new_name . ':/') or -d $SVN_REPOSITORIES_PATH . $repository_new_name) {
				print "Repository \"$repository_new_name\" does already exists.\n";

				exit -4;
			}

			my $repository_new = $svn->add_resource($repository_new_name . ':/');

			while (my ($entity, $right) = each %{$repository->authorized()}) {
				$repository_new->authorize($entity => $right);
			}

			$svn->remove_resource($repository_name . ':/');

			$svn->write_acl();

			if (-d $SVN_REPOSITORIES_PATH . $repository_name) {
				rename($SVN_REPOSITORIES_PATH . $repository_name, $SVN_REPOSITORIES_PATH . $repository_new_name);
			}
		},
	},
	{
		option => [ 'modify', 'user', { type => 's', name => 'user' }, 'name', 'to', { type => 's', name => 'name' } ],
		description => 'Modify the name of an user',
		exec => sub {
			my ($user_name, $user_new_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists.\n";

				exit -4;
			}

			if (not check_user_name($user_new_name, 1)) {
				exit -4;
			}

			if (exists get_users()->{$user_new_name}) {
				print "ERROR: User \"$user_new_name\" does already exists.\n";

				exit -4;
			}

			for ($svn->groups()) {
				next if not $_;

				if ($_->member_exists($user_name)) {
					$_->add_member($user_new_name);
					$_->remove_member($user_name);
				}
			}

			for ($svn->resources()) {
				next if not $_;

				my $authorized = $_->authorized();

				if (exists $authorized->{$user_name}) {
					$_->authorize($user_new_name => $authorized->{$user_name});
					$_->deauthorize($user_name);
				}
			}

			$svn->write_acl();

			my $users_config = read_file($SVN_USERS_CONFIG);

			if ($users_config =~ s/^$user_name(:.+)$/$user_new_name$1/mg) {
				write_file($SVN_USERS_CONFIG, $users_config);
			}
		},
	},
	{
		option => [ 'modify', 'user', { type => 's', name => 'user' }, 'password' ],
		description => 'Modify the password of an user',
		exec => sub {
			my ($user_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists.\n";

				exit -4;
			}

			system_cmd('htpasswd2', '-m', $SVN_USERS_CONFIG, $user_name);
		},
	},
	{
		option => [ 'modify', 'user', { type => 's', name => 'user' }, 'right', 'of', 'repository', { type => 's', name => 'repository' }, 'to', { type => [ 'r', 'rw' ], name => 'right' } ],
		description => 'Modify the repository right of an user',
		exec => sub {
			my ($user_name, $repository_name, $right) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			$repository->authorize($user_name => $right);
			$svn->write_acl();
		},
	},
	{
		option => [ 'remove', 'group', { type => 's', name => 'group' } ],
		description => 'Remove a group',
		exec => sub {
			my ($group_name) = @_;

			init_svn();

			if (not $svn->group($group_name)) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			for ($svn->resources()) {
				next if not $_;

				if ($_->is_authorized('@' . $group_name)) {
					$_->deauthorize('@' . $group_name);
				}
			}

			$svn->remove_group($group_name);
			$svn->write_acl();
		},
	},
	{
		option => [ 'remove', 'group', { type => 's', name => 'group' }, 'from', 'repository', { type => 's', name => 'repository' } ],
		description => 'Remove a group from a repository',
		exec => sub {
			my ($group_name, $repository_name) = @_;

			init_svn();

			if (not $svn->group($group_name)) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			if (not $repository->is_authorized('@' . $group_name)) {
				print "ERROR: Gruop \"$group_name\" is not in repository \"$repository_name\"\n";
			}

			$repository->deauthorize('@' . $group_name);
			$svn->write_acl();
		},
	},
	{
		option => [ 'remove', 'repository', { type => 's', name => 'repository' } ],
		description => 'Remove a repository',
		exec => sub {
			my ($repository_name) = @_;

			init_svn();

			if (not $svn->resource($repository_name . ':/')) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			$svn->remove_resource($repository_name . ':/');
			$svn->write_acl();

			if (-d $SVN_REPOSITORIES_PATH . $repository_name) {
				print "INFO: Only removed access rights of the repository. FS folder is still there!\n";
			}
		},
	},
	{
		option => [ 'remove', 'user', { type => 's', name => 'user' } ],
		description => 'Remove an user',
		exec => sub {
			my ($user_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			for ($svn->groups()) {
				next if not $_;

				if ($_->member_exists($user_name)) {
					$_->remove_member($user_name);
				}
			}

			for ($svn->resources()) {
				next if not $_;

				if ($_->is_authorized($user_name)) {
					$_->deauthorize($user_name);
				}
			}

			$svn->write_acl();

			system_cmd('htpasswd2', '-D', $SVN_USERS_CONFIG, $user_name);
		},
	},
	{
		option => [ 'remove', 'user', { type => 's', name => 'user' }, 'from', 'group', { type => 's', name => 'group' } ],
		description => 'Remove an user from a group',
		exec => sub {
			my ($user_name, $group_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			my $group = $svn->group($group_name);

			if (not $group) {
				print "ERROR: Group \"$group_name\" does not exists\n";

				exit -4;
			}

			if (not $group->member_exists($user_name)) {
				print "ERROR: User \"$user_name\" is not in group \"$group_name\"\n";
			}

			$group->remove_member($user_name);
			$svn->write_acl();
		},
	},
	{
		option => [ 'remove', 'user', { type => 's', name => 'user' }, 'from', 'repository', { type => 's', name => 'repository' } ],
		description => 'Remove an user from a repository',
		exec => sub {
			my ($user_name, $repository_name) = @_;

			init_svn();

			if (not exists get_users()->{$user_name}) {
				print "ERROR: User \"$user_name\" does not exists\n";

				exit -4;
			}

			my $repository = $svn->resource($repository_name . ':/');

			if (not $repository) {
				print "ERROR: Repository \"$repository_name\" does not exists\n";

				exit -4;
			}

			if (not $repository->is_authorized($user_name)) {
				print "ERROR: User \"$user_name\" is not in repository \"$repository_name\"\n";
			}

			$repository->deauthorize($user_name);
			$svn->write_acl();
		},
	},
	{
		option => [ 'usage' ],
		description => 'Display usage',
		exec => sub { print_usage(); },
	},
);

sub system_cmd {
	system(@_) == 0 or die "\"@_\" failed: $?";
}


sub print_usage {
	print "Nethead SVN Management v$VERSION\n";
	print "usage nethead-svn.pl [options]\n";
	print "options\n";

	my @lines = ();
	my $max_line_length = 0;

	for my $option (@options) {
		my @s = ();

		for my $i(@{$option->{option}}) {
			if (not ref $i) {
				push(@s, $i);
			}
			elsif (ref $i eq 'HASH') {
				if (ref $i->{type} eq 'ARRAY') {
					push(@s, '<' . join('|', @{$i->{type}}) . '>');
				}
				else {
					push(@s, '<' . $i->{name} . '>');
				}
			}
		}

		my $s = join(' ', @s);

		if ($max_line_length < length $s) {
			$max_line_length = length $s;
		}

		push(@lines, [ $s, $option->{description} ]);
	}

	$max_line_length += 1;

	for my $line(sort { $a->[0] cmp $b->[0] } @lines) {
		print "\t" . $line->[0] . ( ' 'x($max_line_length - length $line->[0]) ) . ' - ' . $line->[1] . "\n";
	}
}

sub check_options {
	my @arguments = @_;

	OPTION: for my $option(@options) {
		if (scalar @{$option->{option}} == scalar @arguments) {
			my @option_arguments = ();

			ARGUMENT: for my $i(0..scalar @arguments - 1) {
				if (not ref $option->{option}->[$i]) {
					if ($option->{option}->[$i] ne $arguments[$i]) {
						next OPTION;
					}
				}
				elsif (ref $option->{option}->[$i] eq 'HASH') {
					if (ref $option->{option}->[$i]->{type} eq 'ARRAY') {
						for (@{$option->{option}->[$i]->{type}}) {
							if ($_ eq $arguments[$i]) {
								push(@option_arguments, $arguments[$i]);

								next ARGUMENT;
							}
						}

						print sprintf("ERROR: %s has to be <%s>\n", $option->{option}->[$i]->{name}, join('|', @{$option->{option}->[$i]->{type}}));

						return;
					}
					elsif ($option->{option}->[$i]->{type} eq 's') {
						# can be pretty much anything
					}

					push(@option_arguments, $arguments[$i]);
				}
			}

			$option->{exec}->(@option_arguments);

			return;
		}
	}

	if (scalar @arguments == 0) {
		print_usage();

		return;
	}
	else {
		print "ERROR: Cannot find matching option\n\n";

		print_usage();

		exit -1;
	}
}

check_options(@ARGV);

exit 0;
