#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use JSON::XS 'decode_json';
use Getopt::Long;
use DateTime;
use DateTime::Format::Epoch;
use Term::ProgressBar;
use DBI;
use Data::Dumper;

my ($o_help,$o_verb,$o_username,$o_rookie,$o_single,$o_expanded,$o_drafting);
my (@possibleusers,@leaguelist,@expandedusers,@dlist);
my ($blist,$ulist);

#Variables
my $o_maxage = 31;
my $o_maxdrafts = 25;
my $sport = "nfl";
my $season = "2021";
my $countdrafts = 0;
my @correctScorings = ("dynasty","dynasty_2qb","dynasty_ppr","dynasty_half_ppr","dynasty_std");

check_options();

# Database configuration
my $dbh = DBI->connect("DBI:mysql:database=Sleeper;mysql_read_default_file=$ENV{HOME}/.my.cnf;mysql_read_default_group=Sleeper",undef,undef) or die "Something went wrong ($DBI::errstr)";

# DateTime variables
my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
my $dt1 = DateTime->now();
my $formatter = DateTime::Format::Epoch->new(epoch => $dt,unit => 'milliseconds');
my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(days => $o_maxage)->epoch();

$blist = $dbh->selectall_hashref ("SELECT DraftID FROM DraftsIgnored","DraftID");
if ($o_rookie){
  $ulist = $dbh->selectall_hashref ("SELECT UserID FROM UserRookieDraftsSearched WHERE ScrapeDate < $dtold","UserID");
}else{
  $ulist = $dbh->selectall_hashref ("SELECT UserID FROM UserStartupDraftsSearched WHERE ScrapeDate < $dtold","UserID");
}

my $user = get_userid($o_username);

if (defined($o_single)){ # Mode for only 1 user.
  get_Drafts($user);
  print "Have found ".scalar(@dlist)." drafts from ${countdrafts} detected on user ${o_username}.\n";
  print_drafts();
  exit(0);
}

get_leagues($user); #Gets all the Leagues from a user

if (scalar(@leaguelist)>0){
  my $currentLeag = 0;
  my $nextLeagupdate = 0;
  my $progressLeag = Term::ProgressBar->new({name => 'Searching Users', count => scalar(@leaguelist), ETA => 'linear', remove => 1});
  $progressLeag->max_update_rate(1);
  $progressLeag->message("Searching Users for ".scalar(@leaguelist)." Leagues");
  foreach my $leagueid ( @leaguelist ) { #For each league, get all users in those leagues
    $currentLeag++;
    $nextLeagupdate = $progressLeag->update($currentLeag) if $currentLeag > $nextLeagupdate;
    get_leagueusers($leagueid);
  }
  $progressLeag->update(scalar(@leaguelist)) if scalar(@leaguelist) >= $nextLeagupdate;
}

if (scalar(@possibleusers)>0){
  my $currentUser = 0;
  my $nextUserupdate = 0;
  my $progressUser = Term::ProgressBar->new({name => 'Searching Drafts', count => scalar(@possibleusers), ETA => 'linear', remove => 1});
  $progressUser->max_update_rate(1);
  $progressUser->message("Searching Drafts for ".scalar(@possibleusers)." Users");
  foreach my $useritem (@possibleusers){ #For each user in one of those leagues gets all their drafts
    $currentUser++;
    get_Drafts($useritem);
    $nextUserupdate = $progressUser->update($currentUser) if $currentUser > $nextUserupdate;
    if ((scalar(@dlist) >= $o_maxdrafts)){ #If already found enough drafts, stop!
      $progressUser->update(scalar(@possibleusers));
      print "Have already found ".scalar(@dlist)." drafts (> ${o_maxdrafts}) from ${countdrafts} detected on ${currentUser} users.\n";
      print_drafts();
      exit;
    }
  }
  $progressUser->update(scalar(@possibleusers)) if scalar(@possibleusers) >= $nextUserupdate;
}

print "Have found ".scalar(@dlist)." drafts from ${countdrafts} detected on ".scalar(@possibleusers)." users.\n";
print_drafts();
exit;

sub get_userid { #Get the UserID from a username
  my $username = shift;
  my $userjson = get_json("https://api.sleeper.app/v1/user/${username}");
  return $userjson->{user_id};
}

sub get_leagues { #Get All leagues from a User
  my $userID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/user/${userID}/leagues/${sport}/${season}");
  foreach my $leagueitem (@$leaguejson){
    push(@leaguelist, $leagueitem->{league_id});
  }
  return;
}

sub get_numberpicks {
  my $leagueID = shift;
  my $draftpicksjson = get_json("https://api.sleeper.app/v1/draft/${leagueID}/picks");
  if (defined($o_rookie)){
    my @BannedPicks = ('4046','6797','1466','6794','4034'); #If Mahomes/Herbert/Kelce/Jefferson/CMC and Rookie, return 0.
    foreach my $draftpick ( @$draftpicksjson ) {
      if (grep(/$draftpick->{player_id}/, @BannedPicks)){
        insert_newdraft($leagueID);
        return 0;
      }
    }
  }
  return keys @$draftpicksjson; #Return number of picks
}

sub get_leagueusers { #Gets all Users from a League
  my $leagueID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/league/${leagueID}/users");
  foreach my $leagueuser ( @$leaguejson ) {
    push(@possibleusers, $leagueuser->{user_id});
  }
  return;
}

sub get_Drafts { #Gets All Draft for a User With certain settings
  my $user_id = shift;
  insert_newuser($user_id);
  my $draftsjson = get_json("https://api.sleeper.app/v1/user/${user_id}/drafts/${sport}/${season}");
  foreach my $draft( @$draftsjson ) {
    $countdrafts++;
    next unless (!exists($blist->{$draft->{draft_id}})); #Check for DraftID in Blacklist (empty if not defined on -b)
    $blist->{$draft->{draft_id}} = $draft->{draft_id}; # Add this draft to list so it doesn't repeat for next users
    verb("Checking Draft ".$draft->{draft_id});
    my $dt2 = $formatter->parse_datetime($draft->{start_time});
    my $days = $dt2->delta_days($dt1)->delta_days();
    next unless ($o_maxage > $days);
    verb("Age of the draft: ${days} days");
    if (defined($o_rookie)){
      next unless ($draft->{settings}->{rounds} < 10); # To Filter Startups, only Rookies
    }else{
      next unless ($draft->{settings}->{rounds} > 20);# To Filter Rookies, only Startups
    }
    if (defined($o_drafting)){
      next unless ($draft->{status} eq "drafting"); # Only search for currently drafting
    }else{
      next unless ( ($draft->{status} eq "drafting") || ($draft->{status} eq "complete") ); # Check that is not in pre-draft
    }
    next unless (get_numberpicks($draft->{draft_id}) > 0);
    insert_newdraft($draft->{draft_id});
    next if ($dt2 > $dt1); # Skip if draft is in the "future"
    next unless (defined($draft->{league_id})); # To Filter Mocks
    next if ($draft->{type} eq "auction"); # To discard auctions
    next unless (grep(/^$draft->{metadata}->{scoring_type}$/, @correctScorings)); # To Filter non-Dynasty
    next unless ( ($draft->{settings}->{teams} == 12) || ($draft->{settings}->{teams} == 14) ); # To filter 12/14 team leagues
    next unless (exists($draft->{settings}->{slots_super_flex})); # To Filter non-SF
    if (defined($draft->{settings}->{slots_te})){
        next unless ($draft->{settings}->{slots_te} < 2); # To 2TE Drafts
    }
    verb("LeagueID: ".$draft->{league_id});
    push @dlist,$draft->{draft_id};
  }
  return;
}

sub print_drafts{
  foreach my $draftID (@dlist){
    print "https://sleeper.app/draft/nfl/${draftID}\n";
  }
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
    'h'     => \$o_help,            'help'            => \$o_help,
    'u:s'   => \$o_username,        'username:s'      => \$o_username,
    'r'     => \$o_rookie,          'rookies'         => \$o_rookie,
    'a:i'   => \$o_maxage,          'maxage'          => \$o_maxage,
    'm:i'   => \$o_maxdrafts,       'maxdrafts'       => \$o_maxdrafts,
    's'     => \$o_single,          'singleuser'      => \$o_single,
    'e'     => \$o_expanded,        'expanded'        => \$o_expanded,
    'd'     => \$o_drafting,        'drafting'        => \$o_drafting,
    'v'     => \$o_verb,            'verbose'         => \$o_verb
  );
  if(defined($o_help)) {
    help();
    exit 0;
  }
  if(!defined($o_username)) {
    help();
    exit 2;
  }
}

sub insert_newdraft{ # Adds a new League to the list
  my $new_draft = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO DraftsIgnored(DraftID,ScrapeDate) VALUES (?,?)},{},);
  $sth->execute($new_draft,$dtnow);
  $sth->finish;
}

sub insert_newuser{ # Adds a new League to the list
  my $new_user = shift;
  if ($o_rookie){
    my $sth = $dbh->prepare(q{REPLACE INTO UserRookieDraftsSearched(UserID,ScrapeDate) VALUES (?,?)},{},);
    $sth->execute($new_user,$dtnow);
  }else{
    my $sth = $dbh->prepare(q{REPLACE INTO UserStartupDraftsSearched(UserID,ScrapeDate) VALUES (?,?)},{},);
    $sth->execute($new_user,$dtnow);
  }
  return;
}

sub get_json{
  my $url = shift;
  my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $header = HTTP::Request->new(GET => $url);
  $header->header(content_type => "application/json",
                         accept => "application/json");
  my $request = HTTP::Request->new('GET', $url, $header);
  my $response = $ua->request($request);
  if ($response->is_success){
    return decode_json($response->content);
  }elsif ($response->is_error){
    print "CRITICAL: Error: $url\n";
    verb($response->error_as_HTML);
    return("");
  }
}

sub verb {
  my $t=shift;
  print STDOUT $t,"\n" if defined($o_verb);
}

sub print_usage {
  print "Usage: $0 -u <USERNAME> [-m <MAXDRAFTS>] [-a <MAXAGE>] [-r] [-s] [-v] [-h]\n";
}

sub help {
  print "\nSearch Sleeper Drafts $0\n";
  print_usage();
  print <<EOT;
-u, --username
    Sleeper username to search.
-a, --maxage
    Max age of the start of the draft (to search for recent drafts). (default 31)
-d, --drafting
    Only search for drafts currently Drafting.
-m, --maxdrafts
    Max number of drafts to search for. (default 25)
-r, --rookies
    Only Rookie Drafts (< 10 rounds).
-s, --singleuser
    Only Search Drafts by the specified user.
-v, --verbose
    Verbose mode.
-h, --help
    Print this help message.
EOT
}