require Cache::File;

our $Opts;

sub init_cache { 
  die "Cache directory must be specified as 'cachedir'\n"
    unless ( defined $Opts->{'cachedir'} );

  die "Cache location " . $Opts->{'cachedir'} . " isn't valid\n"
    unless ( -d $Opts->{'cachedir'} && -w $Opts->{'cachedir'} );

  my $cacheFile = Cache::File->new( cache_root => $Opts->{'cachedir'});

  return $cacheFile;
}


# Load successfully
1;

