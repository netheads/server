#!/usr/bin/perl

use Modern::Perl;

use utf8;

use File::Basename;
use File::Slurp;
use JSON;
use Mojo::UserAgent;

my $script_path = dirname(__FILE__);

my $ua = Mojo::UserAgent->new;

my $filename = $ARGV[0];

$filename ||= $script_path . '/prefetch-websites.json';

my $silence = @ARGV > 1;

if (not -f $filename or not -r $filename) {
	say "ERROR: Cannot open $filename";

	exit 1;
}

my $file_content = read_file($filename);
my $websites = decode_json($file_content);

my $any_errors = 0;

sub print_website_header {
	my ($website) = @_;
	
	print "Fetch $website ";
}

while (my ($website, $checks) = each(%$websites)) {
	if (not $silence) {
		print_website_header($website);
	}

	my $tx = $ua->get($website);

	if (!$tx->error) {
		my $body = $tx->res->body;
		my $ok = 1;

        if (ref($checks) eq 'HASH') {
            if (exists $checks->{body_size} and $checks->{body_size} != length $body) {
		print_website_header($website);

                say "\n\tFailed body size is " . (length $body) . " should be $checks->{body_size}.";
            
                $ok = 0;
                $any_errors = 1;
            }
        }
        else {
            for my $regex (@$checks) {
                if ($body !~ m/$regex/sg) {
                    if ($silence) {
                        print_website_header($website);

                        say "\n\tRegex failed: $regex";
                    }
                    else {
                        say "\n\tRegex failed: $regex";
                    }
                
                    $ok = 0;
                    $any_errors = 1;
                    
                    last;
                }
            }
        }
	
		if ($ok) {
			if (not $silence) {
				say 'ok';
			}
		}
	}
	else {
		my ($message, $code) = $tx->error;

		$any_errors = 1;

		if ($code) {
			if ($silence) {
				print_website_header($website);
			}

			say "\n\t$code $message response.";
		}
		else {
			if ($silence) {
				print_website_header($website);
			}

			say "\n\tConnection error: $message";
		}
	}
}

if ($any_errors) {
	exit 2;
}
else {
	exit 0;
}
