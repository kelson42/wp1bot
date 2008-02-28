#!/usr/bin/perl
# RatingsTable.pm
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0
#
# This class is used to create a table of article rating data,
# to abstract the table generation code away from the main code
#
#
# * The data for the table goes in a 2D hash, indexed by symbolic tags.
#
# * A subset of this data is output, based on parameters.
#
# * The symbolic tags are not used for output; there are other parameters
#   for how to format them.
# 
#

package RatingsTable;
use strict;
use Carp;

use Data::Dumper;

#######################################

sub new {
  my $self = {};
  bless($self);

  $self->{'columns'} = [];
  $self->{'rows'} = [];
  $self->{'columnlabels'} = {};
  $self->{'rowlabels'} = {};
  $self->clear();  # initialize data hash
  return $self;
}

#######################################
## Get/set overarching title

sub title {
  my $self = shift;
  my $newtitle = shift;
  if ( defined $newtitle) { 
    $self->{'title'} = $newtitle;
  }
 return $self->{'title'};
}

####################################
## Clear data
sub clear {
  my $self = shift;
  $self->{'data'}= {};
}

####################################
## Get/set data for a particular cell

sub data { 
  my $self = shift;
  my $row = shift;
  my $col = shift;
  my $newvalue = shift;  

  if ( ! defined $self->{'data'}->{$row} ) {
     $self->{'data'}->{$row} = {};
  }

  if ( defined $newvalue ) { 
    $self->{'data'}->{$row}->{$col} = $newvalue;
  }

  return  $self->{'data'}->{$row}->{$col};
}


#############################
## Increment the number in a table cell

sub incrdata { 
  my $self = shift;
  my $row = shift;
  my $col = shift;

  if ( ! defined $self->{'data'}->{$row} ) {
     $self->{'data'}->{$row} = {};
  }

  if ( ! defined $self->{'data'}->{$row}->{$col} ) {
    $self->{'data'}->{$row}->{$col} = 1;
  } else { 
    $self->{'data'}->{$row}->{$col} =  $self->{'data'}->{$row}->{$col} + 1;
  }    

  return  $self->{'data'}->{$row}->{$col};
}

###############################################################
###### Get/set labels for columns

sub columnlabels {
  my $self = shift;
  my $newlabels = shift;

  if ( defined $newlabels) { 
    $self->{'columnlabels'} = $newlabels;
  }

  return  $self->{'columnlabels'};
}

##################################
### Get/set labels for rows

sub rowlabels {
  my $self = shift;
  my $newlabels = shift;

  if ( defined $newlabels) { 
    $self->{'rowlabels'} = $newlabels;
  }

  return  $self->{'rowlabels'};
}

#######################################
## Get/set list of column names to use

sub columns {
  my $self = shift;
  my $newcolumns = shift;

  if ( defined $newcolumns) { 
    $self->{'columns'} = $newcolumns
  }

  return  $self->{'columns'};
}

############################################33
### Get/set list of row names to use

sub rows {
  my $self = shift;
  my $newrows = shift;

  if ( defined $newrows) { 
    $self->{'rows'} = $newrows;
  }

  return  $self->{'rows'};
}
 
######################################################
#############  A single title over all the columns

sub columntitle {
  my $self = shift;
  my $newtitle = shift;
  if ( defined $newtitle) { 
    $self->{'columntitle'} = $newtitle;
  }
 return $self->{'columntitle'};
}

###########################################################
### A single title over all the rows

sub rowtitle {
  my $self = shift;
  my $newtitle = shift;
  if ( defined $newtitle) { 
    $self->{'rowtitle'} = $newtitle;
  }
 return $self->{'rowtitle'};
}

########################################################3
### Generate wiki code

sub wikicode {

  my $self = shift;
  my $text;

  my $totalCols  = 0;
  my $row;
  my $col; 

  $totalCols = scalar @{$self->{'columns'}} + 1;

  $text .= << "HERE";
{| class="wikitable" style="text-align: center; font-size: 10pt; width: 5.5in;"
HERE

  if ( defined $self->{'title'} ) { 
    $text .= << "HERE";
|- 
! colspan="$totalCols" | $self->{'title'}
HERE
  }

  my $classCols = $totalCols - 1;   
    # Number of columns covered by column title

  if ( defined $self->{'rowtitle'}) {
    if ( defined $self->{'columntitle'} ) {
       #Row and column titles

      $text .= << "HERE";
|-
| rowspan="2" style="vertical-align: bottom" | $self->{'rowtitle'}
| colspan="$classCols" | $self->{'columntitle'}
|-
HERE
    } else {
       #Row title but no column titles

      $text .= << "HERE";
|-
| style="vertical-align: bottom" | $self->{'rowtitle'}
HERE
    }
    foreach $col (@{$self->{'columns'}}) { 
if ( ! defined $self->{'columnlabels'}->{$col} ) { 
  carp("No label for column $col\n");
}
      $text .= << "HERE";
| $self->{'columnlabels'}->{$col}
HERE
    }
  } else {   # no row title 
    if (defined $self->{'columntitle'} ) {
        
      $text .= << "HERE";
|-
| &nbsp;
| colspan="$classCols" | $self->{'columntitle'}
|-
| &nbsp;
HERE

    } else {
      # no row title, no column title
      # Nothing to do in this case
    }
  }

   # output actual table data

  foreach $row ( @{$self->{'rows'}}) { 
if ( ! defined $self->{'rowlabels'}->{$row} ) { 
  carp("No label for row $row\n");
}
    $text .= << "HERE";
|-
| $self->{'rowlabels'}->{$row}
HERE

    foreach $col (@{$self->{'columns'}}) { 
#   print STDERR "Col $col Row $row\n";
      $text .= << "HERE";
|| $self->{'data'}->{$row}->{$col}
HERE
    }
  }

  $text .= "|}\n";

  return $text;
}


###############################
## debugging

sub dump {
  my $self = shift;
  
  print "columns: " . Dumper($self->{'columns'}) . "\n\n";
  print "rows: " . Dumper($self->{'rows'}) . "\n\n";
  print "data: " . Dumper($self->{'data'}) . "\n\n";
}

############################## End

1; # return true on successful loading of the module

__END__
