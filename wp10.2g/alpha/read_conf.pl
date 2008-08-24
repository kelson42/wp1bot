#!/usr/bin/perl
use strict;
use Data::Dumper;
# Internal variable holding the configuration variables
my $settings = {};

sub read_conf { 
  print "Reading configuration file\n";
  my $filename;
  my $homedir = (getpwuid($<)) [7];
  
  if ( defined $ENV{'WP10_CREDENTIALS'} ) {
    $filename = $ENV{'WP10_CREDENTIALS'};
  } else { 
    $filename = $homedir . "/.wp10.conf";
  }

  die "Can't open database configuration '$filename'\n"
    unless -r $filename;

  my ($opt, $val, $line);
  my $opts = {};

  open CONF, "<", $filename;
  while ( $line = <CONF> ) {
    next if ( $line =~ /\s*#/ );
    next if ( $line =~ /^\s*$/ );
    chomp $line;
    ($opt, $val) = split /\s+/, $line, 2;
    $val =~ s/\s*$//;

    if ( $opt eq 'lib' ) { 
      push @INC, $val;
    } else { 
      $opts->{$opt} = $val;
	  $settings->{$opt} = $val;
    }
  }
  close CONF;

  return $opts;
}

sub get_conf() { 
	my $var = shift;
	my ($hash, $val, $key, $left, $right);
	
	if ( !defined $var)
	{
		print "Missing \$var parameter\n";
		die();
	}
	
	
	if ( defined $settings->{$var})
	{
		$val = $settings->{$var};
		# print "$var found in settings; value = $val\n";
		if ($val =~ /^\{/ && $val =~ /\}$/)
		{
			# Assume that this is a hash variable
			
			# Remove the { and } that are wrapping the hash
			$val = substr($val, 1, length($val) - 2);
			
			my $vars;
			
			# Split along the commas
			my @keys = split(/,/, $val);
			
			# Loop around each key/value pair
			foreach $key (@keys) {
				# Parse around the '=>'
				next unless ( $key =~ /^\s*(\S*)\s*\=>\s*(\S*)\s*$/ ); 
				$left = $1;
				$right = $2;
				# Remove the quotes surrounding key/value pairs, if necessary
				if ($left =~ /^\'/ && $left =~ /\'$/)
				{
					$left = substr($left, 1, length($left) - 2);
				}
				if ( $right =~ /^\'/ && $right =~ /\'$/)
				{
					$right = substr($right, 1, length($right) - 2);
				}
				# Assign the key/value pair to the associative array hash
				$vars->{$left} = $right;   
			}
			return $vars;
		}
		else
		{
			# Not a hash variable
			return $val;
		}
	}
	else
	{
		print Dumper($var);
		print "$var not found in settings\n";
		die();
	}
}


# Load successfully
1;
