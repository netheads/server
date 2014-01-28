#!/usr/bin/perl

use strict;
use warnings;

use Filter::Arguments;

sub get_logical_volume_information {
	my ($volume_group) = @_;
	
	my @lines = `lvdisplay $volume_group`;
	
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
	print "usage: backup_lvm_post.pl --backup <backup path> --vg <volume group> --lv (<logical volume>)+\n";
	
	exit(1);
}

my %vg = get_logical_volume_information($args{vg});

if (not %vg) {
	exit (2);
}

$args{lv} = [ $args{lv} ] if not ref $args{lv};

for my $lv_name (@{$args{lv}}) {
	my $lv = $vg{$lv_name};
	
	while (1) {
		if (-d "$args{backuppath}/$lv_name") {
			`umount $args{backuppath}/$lv_name`;
			
			print "$args{backuppath}/$lv_name unmounted\n";
		}
		
		`lvremove -f /dev/$args{vg}/backup_$lv_name`;
		
		if (not -l "/dev/$args{vg}/backup_$lv_name") {
			print "/dev/$args{vg}/backup_$lv_name removed\n";
			
			last;
		}
		
		print "retrying in 2 seconds\n";
		
		sleep 2;
	}
}
