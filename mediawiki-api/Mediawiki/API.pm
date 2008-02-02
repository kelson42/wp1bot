package Mediawiki::API;

use strict;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Cookies;
use XML::Simple;
use POSIX qw(strftime);
use HTML::Entities;
use Encode;


$XML::Simple::PREFERRED_PARSER = "XML::Parser";
# $XML::Simple::PREFERRED_PARSER = "XML::LibXML::SAX";

###########################################################

=pod

Mediawiki::API -
Provides methods to access the Mediawiki API via an object oriented interface. 
Attempts be less stupid about errors.

Version: $Revision: 1.23 $

=head1 Synopsis

 $api = Mediawiki::API->new();
 $api->base_url($newurl);
 @list = @{$api->pages_in_category($categoryTitle)};
 $api->overwrite_page($pageTitle, $pageContent, $editSummary);

=cut

#############################################################3

=head1 Methods

=head2 Initialize the object

=over 

=item $api = Mediawiki::API->new();


Create a new API 
object

=back

=cut

###

sub new { 
  my $self = {};

  $self->{'agent'} = new LWP::UserAgent;
  $self->{'agent'}->cookie_jar(HTTP::Cookies->new());

  $self->{'baseurl'} = 'http://192.168.1.71/~mw/wiki/api.php';
  $self->{'loggedin'} = 'false';
  $self->{'maxRetryCount'} = 3;
  $self->{'debugLevel'} = 1;
  $self->{'maxlag'} = 5;
  $self->{'requestCount'} = 0;
  $self->{'htmlMode'} = 0;

  $self->{'debugXML'} = 0;

  $self->{'botlimit'} = 1000;
  bless($self);
  return $self;
}

#############################################################

=head2 Get/set configuration parameters

=over

=item $url = $api->base_url($newurl);

=item $url = $api->base_url();

Set and/or fetch the url of the 
Mediawiki server.  It should be a full URL to api.php on the server.

=cut

sub base_url () { 
  my $self = shift;
  my $newurl = shift;
  if ( defined $newurl)  {
    $self->{'baseurl'} = $newurl;
    $self->print(1, "A Set base URL to: $newurl");
  }

  return $self->{'baseurl'};
}

####################################3

sub max_retries  {
  my $self = shift;
  my $count = shift;
  if ( defined $count)  {
    $self->{'maxRetryCount'} = $count;
    $self->print(1, "A Set maximum retry count to: $count");
  }

  return $self->{'maxRetryCount'};
}



sub html_mode  {
  my $self = shift;
  my $mode = shift;
  if ( defined $mode)  {
    $self->{'htmlMode'} = $mode;
    if ( $self->{'htmlMode'} > 0 ) { 
      $self->print(1, "A Enable HTML mode");
    } else {
      $self->print(1, "A Disable HTML mode");
    }
  }

  return $self->{'htmlMode'};
}


sub debug_xml  {
  my $self = shift;
  my $mode = shift;
  if ( defined $mode)  {
    $self->{'debugXML'} = $mode;
    if ( $self->{'debugXML'} > 0 ) { 
      $self->print(1, "A Enable XML debug mode");
    } else {
      $self->print(1, "A Disable XML debug mode");
    }
  }

  return $self->{'debugXML'};
}



##################

=item $level = $api->debug_level($newlevel);

=item $level = $api->debug_level();

Set the level of output, from 0 to 5. Level 1 gives minimal feedback, 
level 5 is detailed for debugging.  Intermediate levels give intermediate 
amounts of information.

=cut

sub debug_level { 
 my $self = shift;
 my $level = shift;
 if ( defined $level) { 
   $self->{'debugLevel'} = $level;
   $self->print(1,"A Set debug level to: $level");
 }
 return $self->{'debugLevel'};
}



#####################################################3

=item $lag = $api->maxlag($newlag)

=item $lag = $api->maxlag()

Get and/or set the maxlag value for requests.

=cut

sub maxlag { 
  my $self = shift;
  my $maxlag = shift;

  if ( defined $maxlag) { 
    $self->{'maxlag'} = $maxlag;
    $self->print(1,"A Maxlag set to " . $self->{'maxlag'});
  }

  return $self->{'maxlag'};
}


#############################################################3

=head2 Log in

=back

=over

=item $api->login($userName, $password)

Log in to the Mediawiki server, check whether the user has a bot flag, 
and set some defaults appropriately

=back

=cut

sub login { 
 my $self = shift;
 my $userName = shift;
 my $userPassword = shift;

 $self->print(1,"A Logging in");

 my $xml  = $self->makeXMLrequest(
                      [ 'action' => 'login', 
                        'format' => 'xml', 
                        'lgname' => $userName, 
                        'lgpassword' => $userPassword  ]);

  if ( ! defined $xml->{'login'} 
       || ! defined $xml->{'login'}->{'result'}) {
    
    print "Foo: " . Dumper($xml);
    $self->handleXMLerror("login err");
  }

  if ( ! ( $xml->{'login'}->{'result'} eq 'Success') ) {
    die( "Login error. Message was: " . $xml->{'login'}->{'result'} . "\n");
  }

  $self->print(1,"R Login successful");

  foreach $_ ( 'lgusername', 'lgtoken', 'lguserid' ) { 
   $self->print(5, "I\t" . $_ . " => " . $xml->{'login'}->{$_} );
   $self->{$_} = $xml->{'login'}->{$_};
  }

  $self->{'loggedin'} = 'true';


  if ( $self->is_bot() ) { 
    $self->print (1,"R Logged in user has bot rights");
  }
}

##################################

sub login_from_file {
  my $self = shift;
  my $file = shift;
  open IN, "<$file" or die "Can't open file $file: $!\n";

  my ($a, $b, $user, $pass, $o);
  $o = $/;
  $/ = "\n";
  while ( <IN> ) { 
    chomp;
    ($a, $b) = split /\s+/, $_, 2;
    if ( $a eq 'user') { $user = $b;}
    if ( $a eq 'pass') { $pass = $b;}
  }

  close IN;
  $/ = $o;

  if ( ! defined $user ) { 
    die "No username to log in\n";
  }

  if ( ! defined $pass ) { 
    die "No password to log in\n";
  }

  $self->login($user, $pass);

}

#############################################################3

# Internal function

sub cookie_jar {
  my $self = shift;
  return $self->{'agent'}->cookie_jar();
}

#############################################################3


=head2 Edit pages

=over

=item $api->overwrite_page($pageTitle, $pageContent, $editSummary);

Overwrite a page with new content.

=back

=cut

sub overwrite_page { 
 my $self = shift;
 my $pageTitle = shift;
 my $pageContent = shift;
 my $editSummary = shift;

 $self->print(1,"A Overwriting $pageTitle");

 $pageContent = $pageContent . " " . strftime('%Y-%m-%dT%H:%M:00Z', gmtime(time()));

 my $xml  = $self->makeXMLrequest(
                  [ 'action' => 'query', 
                    'prop' => 'info',
                    'titles' => $pageTitle,
                    'intoken' => 'edit',
                    'format' => 'xml']);

  print Dumper($xml);

  if ( ! defined $xml->{'query'}
       || ! defined $xml->{'query'}->{'pages'}
       || ! defined $xml->{'query'}->{'pages'}->{'page'} 
       || ! defined $xml->{'query'}->{'pages'}->{'page'}->{'edittoken'} ) { 
     $self->handleXMLerror($xml);
  }

  my $editToken= $xml->{'query'}->{'pages'}->{'page'}->{'edittoken'};
  $self->print(5, "R edit token: ... $editToken ...");

  my $res  = $self->makeHTMLrequest(
                  [ 'action' => 'edit',
                    'epedittoken' => $editToken,
                    'epsummary' => $editSummary,
                    'eptext' => $pageContent,
                    'eptitle' => $pageTitle,
                    'format' => 'xml'  ]);

  print Dumper($res);

  return;

}

############################################################
# 

=head2 Get lists of pages

=over

=item $articles = 
    $api->pages_in_category($categoryTitle [ , $namespace])

Return the list of page titles in a category. Optional parameter
to filter by namespace. Return $articles, an array ref.

=cut

sub pages_in_category {
  my $self = shift;
  my $categoryTitle = shift;
  my $namespace = shift;

  $categoryTitle =~ s/^Category://;

  my $results = $self->pages_in_category_detailed($categoryTitle,$namespace);

  my @articles;

  my $result;
  foreach $result (@{$results}) { 
      push @articles, $result->{'title'};
  }

  return \@articles;
}

############################################################
# Compatibility function from old framework

=item $articles = $api->fetch_backlinks_compat($pageTitle)

Return a list of pages that link to a given page.
Return $articles as an arrayreference.

=cut

sub fetch_backlinks_compat {
  my $self = shift;
  my $pageTitle = shift;

  my $results = $self->backlinks($pageTitle);

  my @articles;

  my $result;
  foreach $result (@{$results}) { 
      push @articles, $result->{'title'};
  }

  return \@articles;
}


#############################################################3

=item $pages = $api->backlinks($pageTitle);

Return the pages that link to a particular page title.
Return a reference to an array.

=cut

sub backlinks { 
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching backlinks for $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'backlinks', 
                           'bllimit' => '500',
                           'bltitle' => $pageTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'bllimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'backlinks', 'bl'],   
                    'bl', 
                    ['query-continue', 'backlinks', 'blcontinue'], 
                    'blcontinue');

  return $results;
}


################################################################

=item $articles = 

$api->pages_in_category_detailed($categoryTitle [, $namespace])

Return the contents of a category. Optional parameter to filter out a 
specific namespace. Return $contents, a reference to an array of hash 
references.

=cut

sub pages_in_category_detailed {
  my $self = shift;
  my $categoryTitle = shift;
  my $namespace = shift;

  $self->print(1,"A Fetching category contents for $categoryTitle");

  if ( $categoryTitle =~ /^Category:/) { 
    $self->print(1,"WARNING: Don't pass categories with namespace included");
    $categoryTitle =~ s/^Category://;
  } 

  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'categorymembers', 
                           'cmlimit' => '500',
                           'cmprop' => 'ids|title|sortkey|timestamp',
                           'cmcategory' => $categoryTitle,
                           'format' => 'xml' );

  if ( defined $namespace ) {
    $queryParameters{'cmnamespace'} = $namespace;
  }

  if ( $self->is_bot) { $queryParameters{'cmlimit'} = $self->{'botlimit'}; }

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'categorymembers', 'cm'],   
                    'cm', 
                    ['query-continue', 'categorymembers', 'cmcontinue'], 
                    'cmcontinue');

  return $results;
}


#############################################################3

=item $list = $api->where_embedded($templateName);

Return the list of pages that tranclude $templateName.
If $templateName refers to a template, it SHOULD start with "Template:".
Return $list, a reference to an array of hash references.

=cut

sub where_embedded { 
  my $self = shift;
  my $templateTitle = shift;

  $self->print(1,"A Fetching list of pages transcluding $templateTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'embeddedin', 
                           'eilimit' => '500',
                           'eititle' => $templateTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'eilimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'embeddedin', 'ei'],   
                    'ei', 
                    ['query-continue', 'embeddedin', 'eicontinue'],
                    'eicontinue');

  return $results;
}

#############################################################3

=item $list = $api->log_events($pageName);

Fetch a list of log entries for the page.
Return $list, a reference to an array of hashes.

=cut

sub log_events { 
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching log events for $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'logevents', 
                           'lelimit' => '500',
                           'letitle' => $pageTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'lelimit'} = $self->{'botlimit'}
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'logevents','item'],   
                    'item', 
                    ['query-continue', 'logevents', 'lestart'],
                    'lestart');



  return $results;
}

#############################################################3

=item $list = $api->image_embedded($imageName);

Return the list of pages that display the image $imageName.
The value of $imageName should NOT start with "Image:".
Return $list, a reference to an array of hash references.

=cut

sub image_embedded { 
  my $self = shift;
  my $imageTitle = shift;

  $self->print(1,"A Fetching list of pages displaying image $imageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'imageusage', 
                           'iulimit' => '500',
                           'iutitle' => $imageTitle,
                           'format' => 'xml' );

  if ( $self->is_bot) { 
    $queryParameters{'iulimit'} = $self->{'botlimit'};
  } 

  my $results 
    = $self->fetchWithContinuation(\%queryParameters, 
                    ['query', 'imageusage', 'iu'],
                    'iu', 
                    ['query-continue', 'imageusage', 'iucontinue'],
                    'iucontinue');

  return $results;
}
######################################################


#########################################################33

=item $text = $api->content($pageTitles);

Get the contents (text) of a page.

=cut

sub content { 
  my $self = shift;
  my $titles = shift;

  if (ref($titles) eq "") { 
     return $self->content_single($titles);
  }
 
  if ( scalar @$titles == 1) { 
     return $self->content_single(${$titles}[0]);
  }


  $self->print(1,"A Fetching content of " . scalar @$titles . " pages");
 
  my $titlestr = join "|", @$titles;

  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'revisions', 
                           'titles' => $titlestr,
                           'rvprop' => 'content',
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

#  print Dumper($results);

  my $arr = {};
  my $data = $self->child_data($results, ['query', 'pages', 'page']);

  my $result;

  foreach $result ( @$data) { 
    $arr->{$result->{'title'}} = $result->{'revisions'}->{'rev'};
  }

  return $arr;

}
 


sub content_single { 
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching content of $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'revisions', 
                           'titles' => $pageTitle,
                           'rvprop' => 'content',
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

#  print Dumper($results);

  return $self->child_data_if_defined($results, 
                       ['query', 'pages', 'page', 'revisions', 'rev'], '');
}



################################################################
=item $info = $api->page_info($page);

Fetch information about a page. Returns a reference to a hash. 

=cut

sub page_info {
  my $self = shift;
  my $pageTitle = shift;

  $self->print(1,"A Fetching info for $pageTitle");
 
  my %queryParameters =  ( 'action' => 'query', 
                           'prop' => 'info',
                           'titles' => $pageTitle,
                           'format' => 'xml' );

  my $results 
    = $self->makeXMLrequest([%queryParameters]);

#  print Dumper($results);
  return $self->child_data($results,  ['query', 'pages', 'page']);
}


#######################################################

# Internal Function

sub fetchWithContinuation {
  my $self = shift;
  my $queryParameters = shift;
  my $dataPath = shift;
  my $dataName = shift;
  my $continuationPath = shift;
  my $continuationName = shift;
  
  $self->add_maxlag_param($queryParameters);

  $self->print(5, "I Query parameters:\n" . Dumper($queryParameters));

  my $xml =$self->makeXMLrequest([ %{$queryParameters}], [$dataName]);
  my @results = @{$self->child_data_if_defined($xml, $dataPath, [])};
  while ( defined $xml->{'query-continue'} ) { 
    $queryParameters->{$continuationName} =     
            $self->child_data( $xml, $continuationPath,
                                     "Error in categorymembers xml");
    $xml =$self->makeXMLrequest([ %{$queryParameters}], [$dataName]);
    @results = (@results, 
                @{$self->child_data_if_defined($xml, $dataPath, [])} );
  }

  return \@results;
}

#######################################################
# Internal function

sub add_maxlag_param {
 my $self = shift;
 my $hash = shift;

 if ( defined $self->{'maxlag'} && $self->{'maxlag'} >= 0 ) { 
   $hash->{'maxlag'} = $self->{'maxlag'}
 }
}

#############################################################3

=item $contribs = $api->user_contribs($userName);

Fetch the list of nondeleted edits by a user. Return $contents as a 
reference to an array of hash references.

=cut

sub user_contribs { 
  my $self = shift;
  my $userName = shift;
  my @results;
  $self->print(1,"A Fetching contribs for $userName");

  my %queryParameters =  ( 'action' => 'query', 
                           'list' => 'usercontribs', 
                           'uclimit' => '500',
                           'ucdirection' => 'older',
                           'ucuser' => $userName,
                           'format' => 'xml' ); 

  if ( $self->is_bot) { 
    $queryParameters{'uclimit'} = $self->{'botlimit'};
  } 

  $self->add_maxlag_param(\%queryParameters);

  my $res  = $self->makeHTMLrequest([ %queryParameters ]);
  
  my $xml = $self->parse_xml($res);

  @results =  @{$self->child_data( $xml, ['query', 'usercontribs', 'item'],  
                                          "Error in usercontribs xml")};

  while ( defined $xml->{'query-continue'} ) { 
    $queryParameters{'ucstart'} = 
            $self->child_data( $xml, ['query-continue', 'usercontribs', 'ucstart'],
                               "Error in usercontribs xml");

    $self->print(3, "I Continue from: " . $xml->{'query-continue'}->{'usercontribs'}->{'ucstart'} );

    $res  = $self->makeHTMLrequest([%queryParameters]);

    $xml = $self->parse_xml($res);

    @results = ( @results, 
                 @{$self->child_data( $xml, ['query', 'usercontribs', 'item'],                                                 
                                      "Error in usercontribs xml")});
  }

  return \@results;
}

#############################################################3

=back

=head2 Information about the logged in user

=over

=item $api->watchlist();

Return an array with watchlist entries for the logged in user.

=cut

sub watchlist { 
 my $self = shift;

 $self->print(1,"A Fetching watchlist");

 my $timeStamp; 
 my $delay = 20;
 $delay = $delay * 60 * 60; # delay is in hours
 $timeStamp = strftime('%Y-%m-%dT%H:%M:00Z', gmtime(time() - $delay));

 my $xml  = $self->makeXMLrequest(
                  [ 'action' => 'query', 
                    'list' => 'watchlist', 
                    'wllimit' => '5',
                    'wlprop' =>  'ids|title|timestamp|user|comment|flags',
                    'wlend' => $timeStamp,      
                    'format' => 'xml'  ]);

  if ( ! defined $xml->{'query'}
       || ! defined $xml->{'query'}->{'watchlist'}
       || ! defined $xml->{'query'}->{'watchlist'}->{'item'} ) { 
     $self->handleXMLerror($xml);
  }

  return  $xml->{'query'}->{'watchlist'}->{'item'};
}

#############################################################3

=item $properties = $api->user_properties();

Return the properties the server reports for the logged in 
user.  Returns a references to an array.

=cut

sub user_properties { 
  my $self = shift;
  my @results;
  $self->print(1,"A Fetching information about logged in user");

  my %queryParameters =  ( 'action' => 'query', 
                           'meta' => 'userinfo', 
                           'uiprop' => 'rights|hasmsg',
                           'format' => 'xml' ); 
  $self->add_maxlag_param(\%queryParameters);

  my $xml  = $self->makeXMLrequest([ %queryParameters ]);

  return $self->child_data($xml,['query','userinfo']);
}

##############################################################

=item $info = $api->site_info();

Return the properties about the mediawiki site (namespaces,
main page, etc.)

=cut

sub site_info { 
  my $self = shift;
  my @results;
  $self->print(1,"A Fetching information mediawiki site");



  my %queryParameters =  ( 'action' => 'query', 
                           'meta' => 'siteinfo', 
                           'siprop' => 'general|namespaces|statistics|interwikimap|dbrepllag',
                           'format' => 'xml' ); 
  $self->add_maxlag_param(\%queryParameters);

  my $xml  = $self->makeXMLrequest([ %queryParameters ]);

  return $self->child_data($xml,['query']);
}

##############################################################

=item $rights = $api->user_rights();

Return the rights (flags) the server reports for the logged 
in user.  Returns a reference to an array of rights.

=cut


sub user_rights {
   my $self = shift;
   my $r = $self->user_properties();
   return $self->child_data($r, ['rights','r']);
}

#############################################################


=item $api->user_is_bot()

Returns nonzero if the logged in user has the 'bot' flag

=cut

sub user_is_bot {
  my $self = shift;
  my $rights = $self->user_rights();

  my $r;
  foreach $r ( @{$rights}) { 
    if ( $r eq 'bot') { 
      return 1;
    }
  }
  return 0;
}

#############################################################3

=back 

=head2 Advanced usage and internal functions

=over

=item $api->makeXMLrequest($queryArgs [ , $arrayNames])

Makes a request to the server, parses the result as XML, and
attempts to detect errors from the API and retry. $arrayNames,
optional, is used for the 'ForceArray' parameter of XML::Simple.

=cut

sub makeXMLrequest {  
  my $self = shift;
  my $args = shift;
  my $arrayNames = shift;

  my $retryCount = 0;

  my $res;
  my $xml;

  while (1) { 
    $res = $self->makeHTMLrequest($args);
  
    $self->print(6, "Got result\n$res\n---\n");

    if ( length $res == 0) { 
      my $edelay = 10;
      $self->print(1,"E Error: empty XML response");
      $self->print(2,"I Query params: \n" . Dumper($args));
      $self->print(2,"I ... sleeping $edelay seconds");
      sleep $edelay;
      next;
    }
 
    if ( defined $arrayNames ) { 
      $xml = $self->parse_xml($res, 'ForceArray', $arrayNames);
    } else { 
      $xml = $self->parse_xml($res);
    } 

    $self->print(6, "XML dump:");
    $self->print(6, Dumper($xml));

    last if ( ! defined $xml->{'error'} );

    if ( $xml->{'error'}->{'code'} eq 'maxlag') { 
      $xml->{'error'}->{'info'} =~ /: (\d+) seconds/;
      my $lag = $1;
      if ($lag > 0) { 
        $self->print(2,"E Maximum server lag exceeded");
        $self->print(3,"I Current lag $lag, limit " . $self->{'maxlag'});
      }
      sleep $lag + 1;
      next;
    }

    $self->print(2,"E APR response indicates error");
    $self->print(3, "Err: " . $xml->{'error'} ->{'code'});
    $self->print(4, "Info: " . $xml->{'error'} ->{'info'});
    sleep 5;
  }

  return decode_recursive($xml);
}

######################################

=item $api->makeHTMLrequest($args)

Makes an HTML request and returns the resulting content. This is the 
most low-level access to the server. It provides error detection and 
automatically retries failed attempts as appropriate. Most queries will 
use a more specific method.

The $args parameter must be an array reference to an array of 
KEY => VALUE pairs. These are passed directly to the HTTP POST request.

=cut

sub makeHTMLrequest {
  my $self = shift;
  my $args = shift;

#  $self->{'requestCount'}++;
  my $k = 0;
  while ( $k < scalar @{$args}) { 
    $self->print(5, "I\t" . ${$args}[$k] . " => " . ${$args}[$k+1]);
    $k += 2;
  }

  my $retryCount = 0;
  my $delay = 4;
 
  my $res;

  while (1) { 
    $self->{'requestCount'}++;

    if ( $retryCount == 0) { 
      $self->print(2, "A  Making HTML request (" . $self->{'requestCount'} . ")");
      $self->print(5, "I  Base URL: " . $self->{'baseurl'});
    } else { 
      $self->print(1,"A  Repeating request ($retryCount)");
    }

    $res = $self->{'agent'}->post($self->{'baseurl'}, $args);
    last if $res->is_success();

#    print Dumper($res);

    $self->print(1, "HTTP response code: " . $res->code() ) ;

    if (defined $res->header('x-squid-error')) { 
      $self->print(1,"I  Squid error: " . $res->header('x-squid-error'));
    }

    $retryCount++;

    $self->print(5, "I  Sleeping for " . $delay . " seconds");

    sleep $delay;
    $delay = $delay * 2;
     
    if ( $retryCount > $self->{'maxRetryCount'}) { 
      my $errorString = 
           "Exceeded maximum number of tries for a single request.\n";
      $errorString .= 
       "Final HTTP error code was " . $res->code() . " " . $res->message . "\n";
      $errorString .= "Aborting.\n";
      die($errorString);
    }
  }

  $self->print(6, $res->content());

  return $res->content();
}


##############################################################

# Internal function

sub child_data_is_defined { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name})  {	
      return 0;
    }
  }
  return 1;
}

################################################################

# Internal function

sub child_data { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};
  my $errorMsg = shift;

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name}) { 
        $self->handleXMLerror($p, "$errorMsg; child '$name' not defined");
    }
    $p = $p->{$name}
  }

  return $p;
}

sub child_data_if_defined { 
  my $self = shift;
  my $p = shift;
  my @r = @{shift()};
  my $default = shift;

  my $name;
  foreach $name ( @r) { 
    if ( ! defined $p->{$name}) { 
        return $default;
    }
    $p = $p->{$name}
  }

  return $p;
}

###################################

# Internal function

sub print { 
  my $self = shift;
  my $limit = shift;
  my $message = shift;
  if ( $limit <= $self->{'debugLevel'} ) {
    print $message;
    if ( $self->{'htmlMode'} > 0) { 
      print " <br/>\n";
    } else { 
      print "\n";
    }
  }
}

#############################################################

# Internal method

sub dump { 
 my $self = shift;
 return Dumper($self);
}


#############################################################3

# Internal function

sub handleXMLerror { 
 my $self = shift;
 my $xml = shift;
 my $text =  shift;

 my $error = "XML error";

 if ( defined $text) { 
   $error = $error . ": " . $text;
 }

 print Dumper($xml);

 die "$error\n";
}
######################################3


sub decode_recursive {
  my $data = shift;
  my $newdata;
  my $i;

  if ( ref($data) eq "" ) { 
    return decode_entities($data);
  } 

  if ( ref($data) eq "SCALAR") { 
    $newdata = decode_entities($$data);
    return \$newdata;
  } elsif ( ref($data) eq "ARRAY" ) { 
    $newdata = [];
    foreach $i ( @$data) {
      push @$newdata, decode_recursive($i);
    }
    return $newdata;
  } elsif ( ref($data) eq "HASH") { 
    $newdata = {};
    foreach $i ( keys %$data ) {
      $newdata->{decode_recursive($i)} = decode_recursive($data->{$i});
    }
    return $newdata;
  }

  die "Bad value $data\n";
}



#######################################################

# Internal function

sub is_bot { 
  my $self = shift;

  if ( ! defined $self->{'isbot'} )  { 
    if ( $self->user_is_bot() ) {
      $self->{'isbot'} = "true";
    } else { 
      $self->{'isbot'} = "false";
    }
  }

  return ( $self->{'isbot'} eq 'true');
}

sub parse_xml {
  my $self = shift;
  if ( $self->debug_xml() > 0) { 
    print "DEBUG_XML Parsing at " . time() . "\n";
  }
  my $xml;


  #  The API may return XML that is not valid UTF-8
  my $t = decode("utf8", $_[0]);
  $_[0] = encode("UTF-8", $t);  # this is a secret code for strict UTF-8

  eval { 
   $xml = XML::Simple::parse_string(@_);
  };
  if ( $@ ) { 
    print "XML PARSING ERROR 1\n";

#    print "Code: $! \n";
#not well-formed (invalid token)

    print Dumper(@_);

    die;
  }
  if ( $self->debug_xml() > 0) { 
    print "DEBUG_XML Finish parsing at " . time() . "\n";
  }
  return $xml;
}

###############################3
# Close POD

=back

=head1 Copryright

Copyright 2007 by Carl Beckhorn. 

Released under GNU Public License (GPL) 2.0.

=cut


########################################################
## Return success upon loading class
1;


