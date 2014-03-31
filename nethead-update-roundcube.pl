#!/usr/bin/perl

use strict;
use warnings;

use File::Path qw(make_path rmtree);
use File::Slurp;
use Term::ReadLine;
use Term::UI;

if (@ARGV < 4) {
	print "Usage nethead-update-roundcube.pl <Website public folder> <Roundcube Version> <Unix user> <Unix user group> [<PHPRC folder>]\n";

	exit 1;
}

my $phprc = '';

if (@ARGV > 4) {
	my $phprc = $ARGV[4];

	if (not -d $phprc or not -f "$phprc/php.ini") {
		print "Did not find any php.ini in $phprc\n";
		
		exit 1;
	}
	
	print "Set PHPRC to $phprc\n";
	
	$phprc = "PHPRC=$phprc";
}

my $user = $ARGV[2];
my $user_group = $ARGV[3];

my $old_path = $ARGV[0];
$old_path =~ s/\/$//;

if (not -d $old_path) {
	print "Website public folder $old_path does not exists\n";

	exit 1;
}

my $old_index_php = read_file("$old_path/index.php");

if (not $old_index_php) {
	print "$old_path/index.php does not exists\n";

	exit 1;
}

my ($old_version) = $old_index_php =~ m/Version ([^\s]+)/s;

my $new_path = $old_path . 'new';
my $new_version = $ARGV[1];

my $download_file = "roundcube-$new_version.tar.gz";

if (-f $download_file) {
	print "Download $download_file already there\n";
}
else {
	print "Download $download_file\n";
	my $wget_cmd = sprintf('wget http://downloads.sourceforge.net/project/roundcubemail/roundcubemail/%s/roundcubemail-%s.tar.gz -O %s', $new_version, $new_version, $download_file);
	print `$wget_cmd`;

	if (not -f $download_file) {
		print "Could not download $download_file\n";

		exit 1;
	}
}

print "Create $new_path\n";
make_path($new_path);

print "Untar package to $new_path\n";
my $untar_cmd = sprintf('tar xvfz %s -C %s', $download_file, $new_path);
print `$untar_cmd`;

print "Remove package\n";
print `rm $download_file`;

my $tmp_path = $new_path;
$new_path .= "/roundcubemail-$new_version";

if (not -d $new_path) {
	print "Folder $new_path does not exists\n";

	exit 1;
}

my $new_index_php = read_file("$new_path/index.php");

if (not $new_index_php) {
	print "$new_path/index.php does not exists\n";

	exit 1;
}

my ($new_version_check) = $new_index_php =~ m/Version ([^\s]+)/s;

if ($new_version ne $new_version_check) {
	print "Package version $new_version is different to the new index.php version $new_version_check\n";

	exit 1;
}

print "Will update from $old_version to $new_version\n";

my $term = Term::ReadLine->new('brand');

if (not $term->ask_yn(prompt => 'Is that correct?', default => 'n')) {
	exit;
}

print "Update with Roundcube Updater\n";
system("$phprc $new_path/bin/installto.sh $old_path");

print "Chmod and chown correctly\n";
print `chown -R root:$user_group $old_path`;
print `chown $user:$user_group $old_path`;
print `chmod -R 750 $old_path`;

print "Execute /bin/indexcontacts.sh\n";
system("sudo -u $user $phprc $old_path/bin/indexcontacts.sh");

print "Remove some unneeded files\n";
for my $i(qw(CHANGELOG composer.json-dist INSTALL installer LICENSE README.md SQL UPGRADING)) {
	my $file = "$old_path/$i";

	print "\tremove $file\n";

	if (-f $file) {
		unlink($file);
	}
	elsif (-d $file) {
		rmtree($file);
	}
}

print "DONE\n";

print "Please, remove backups and unneeded files from $old_path!!!\n";
