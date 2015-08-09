#!/usr/bin/perl

use strict;
use warnings;

use Filter::Arguments;
use POSIX;

sub get_logical_volume_information {
	my ($volume_group) = @_;

	my @lines = `lvdisplay $volume_group 2>&1`;

	return if not @lines;

	my %vg;
	my $lv = {};

	for my $line (@lines) {
		if ($line =~ m/--- Logical volume ---/) {
			$vg{$lv->{name}} = $lv if %$lv;

			$lv = {};
		}
		elsif ($line =~ m/LV Path\s*(\S+)\n/) {
			$lv->{path} = $1;

			$lv->{path} =~ m/\/dev\/$volume_group\/(.+)/;
			$lv->{name} = $1;
		}
		elsif ($line =~ m/LV Size\s*(\S+) (\S+)\n/) {
			$lv->{size} = $1;
			$lv->{size_unit} = $2;
		}
	}

	$vg{$lv->{name}} = $lv if %$lv;

	return %vg;
}

my %args = Arguments;

if (not exists $args{backuppath} or not exists $args{vg} or not exists $args{lv}) {
	print "usage: backup_lvm_pre.pl --backup <backup path> --vg <volume group> --lv (<logical volume>)+\n";

	exit(1);
}

my %vg = get_logical_volume_information($args{vg});

if (not %vg) {
	exit (2);
}

$args{lv} = [ $args{lv} ] if not ref $args{lv};

for my $lv_name (@{$args{lv}}) {
	my $lv = $vg{$lv_name};

	my $size = $lv->{size};

	# convert to . comma
	$size =~ s/,/./;

	# round to full number
	$size =  ceil($size * 0.3);

	my $create = `lvcreate -L$size$lv->{size_unit} -s -n backup_$lv_name $lv->{path} 2>&1`;
	print $create;

	print "/dev/$args{vg}/backup_$lv_name created\n";

	my $mkdir = `mkdir -p $args{backuppath}/$lv_name 2>&1`;
	print $mkdir;

	my $mount = `mount /dev/$args{vg}/backup_$lv_name $args{backuppath}/$lv_name 2>&1`;
	print $mount;

	print "/dev/$args{vg}/backup_$lv_name mounted\n";
}
