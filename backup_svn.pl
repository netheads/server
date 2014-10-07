#!/usr/bin/perl

use strict;
use warnings;

use File::Copy;
use Getopt::Compact;

my $hot_backup_script = '/var/backup/svn/backup_svn-hot-backup.py';

sub options_validate {
	my ($opts) = @_;
	
	for my $i(qw/path-backup path-repositories/) {
		if (not $opts->{$i}) {
			print "Error: $i is needed.\n";

			return;
		}
	}
	
	for my $i(qw/path-backup path-repositories/) {
		if (not -d $opts->{$i}) {
			print "Error: $i '" . $opts->{$i} . "' does not exists\n";
			
			return;
		}
	}
	
	if (not -w $opts->{'path-backup'}) {
		print "Error: path-backup '" . $opts->{'path-backup'} . "' is not writeable\n";
		
		return;
	}
	
	return 1;
}

my $options = Getopt::Compact->new(
	name => 'Nethead SVN backup',
	struct => [
		[ 'keep-revision-in-name', 'If the backups get renamed, keep the revision number in the backup name' ],
		[ 'only-backup-if-new-revision', 'Only backup if there is a new revision of the repository' ],
		[ 'path-backup', 'The backup folder', '=s' ],
		[ 'path-repositories', 'The repositories folder', '=s' ],
		[ 'rename-backups', 'Sanely rename the backups' ],
	]
);

my $opts = $options->opts();

if (not $options->status() or not options_validate($opts)) {
	print $options->usage();
	
	exit 1;
}

print "---\n";
print "svn backup\n";

# directory to save backups in, must be rwx by svn user
my $dir_backup = $opts->{'path-backup'};
my $dir_repositories = $opts->{'path-repositories'};

my %old_backups;

if (opendir(DIR, $dir_backup)) {
	for my $repository (sort readdir(DIR)) {
		if (-f "$dir_backup/$repository" and ($repository =~ m/(.+)-(\d+)-\d+.+/ or $repository =~ m/(.+)-(\d+).+/)) {
			$old_backups{$1} = $2;
		}
	}
	
	closedir(DIR);
}
else {
	die 'Couldn\'t open backup dir';
}

if (opendir(DIR, $dir_repositories)) {
	for my $repository (sort readdir(DIR)) {
		if ($repository ne '.' and $repository ne '..' and -d "$dir_repositories/$repository") {
			print "-\nLooking at repository $repository\n";
			
			if ($opts->{'only-backup-if-new-revision'} and exists $old_backups{$repository}) {
				my $cmd_svnlook = "svnlook youngest $dir_repositories/$repository";
				my $out_svnlook = `$cmd_svnlook`;
				
				if ($out_svnlook =~ m/(\d+)/) {
					if ($1 == $old_backups{$repository}) {
						print "  No need to backup. Already at revision $1\n";

						next;
					}
					else {
						print "  Revision changed from $old_backups{$repository} to $1. Let's backup\n";
					}
				}
				else {
					print "  ERROR: Could not fetch current revision numbert\n";
				}
			}
			
			my $cmd_hot_backup = "$hot_backup_script --archive-type=bz2 --num-backups=1 $dir_repositories/$repository $dir_backup";
			my $out_hot_backup = `$cmd_hot_backup`;
			
			print $out_hot_backup;
			
			if ($out_hot_backup =~ m/Archive created, removing backup/s) {
				if ($opts->{'rename-backups'}) {
					$out_hot_backup =~ m|Archiving backup to '(.+?)'|s;

					my $backup_name = $1;
					my ($backup_revision, $backup_version, $backup_extension);
					
					if ($backup_name =~ m/^.+-(\d+)-(\d+)\.(.+?)$/s) {
						($backup_revision, $backup_version, $backup_extension) = ($1, $2, $3);
					}
					elsif ($backup_name =~ m/^.+-(\d+)\.(.+?)$/s) {
						($backup_revision, $backup_version, $backup_extension) = ($1, undef, $2);
					}

					if ($opts->{'keep-revision-in-name'}) {
						print "  rename backup $backup_name to $repository-$backup_revision.$backup_extension\n";

						move($backup_name, "$dir_backup/$repository-$backup_revision.$backup_extension");
					}
					else {
						print "  rename backup $backup_name to $repository.$backup_extension\n";
					
						move($backup_name, "$dir_backup/$repository.$backup_extension");
					}
				}
			}
			else {
				print "  ERROR: Backup was not created!\n";
			}
		}
	}
	
	closedir(DIR);
}
else {
	die 'Couldn\'t open repository dir';
}

print "---\n";

exit(0);
