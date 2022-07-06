#!/usr/bin/perl

# use strict;
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

my ($o_help,$o_verb,$o_username,$o_picks,$o_teams,$o_nosimple,$o_simple,$o_single,$o_drafting,$o_currentdrafttype);
my (@possibleusers,@leaguelist,@expandedusers,@dlist,@Slist,@Rlist);
my ($user,$blist,$ulist);

#Variables
my $o_startup = 10; # Search for 10 startup drafts by default.
my $o_rookie = 0; # Search for 0 Rookie Drafts
my $o_maxage = 7;
my $o_minsearchage = 2;
my $o_maxusers = 1000;
my $sport = "nfl";
my $seasonleagues = "2022";
my $seasondrafts = "2022";
my $o_progressbar = 0;
my $countdrafts = 0;
my @correctScorings = ("dynasty","dynasty_2qb","dynasty_ppr","dynasty_half_ppr","dynasty_std");
my @BannedPicks = ('4046','6797','1466','6794','4034'); #Players searched to discard 'rookie drafts' with them (Mahomes/Herbert/Kelce/Jefferson/CMC)
check_options();

# DateTime variables
my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
my $dt1 = DateTime->now();
my $formatter = DateTime::Format::Epoch->new(epoch => $dt,unit => 'milliseconds');
my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(days => $o_minsearchage)->epoch();

# Database configuration
my $dbh = DBI->connect("DBI:mysql:database=Sleeper;mysql_read_default_file=$ENV{HOME}/.my.cnf;mysql_read_default_group=Sleeper",undef,undef) or die "Something went wrong ($DBI::errstr)";

if ($o_rookie>0 and $o_startup>0){
  $blist = $dbh->selectall_hashref ('SELECT DraftID FROM DraftsIgnored',"DraftID");
}elsif($o_rookie>0){
  $blist = $dbh->selectall_hashref ('SELECT DraftID FROM DraftsIgnored WHERE DType = "Rookie"',"DraftID");
}else{
  $blist = $dbh->selectall_hashref ('SELECT DraftID FROM DraftsIgnored WHERE DType = "Startup"',"DraftID");
}

if(!defined($o_username)) {
  if (($o_minsearchage == 0) or ($o_rookie > 0 and $o_startup > 0)){
    @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s WHERE (s.ScrapeDateStartup < $dtold OR s.ScrapeDateStartup IS NULL) AND (s.ScrapeDateRookie < $dtold OR s.ScrapeDateRookie IS NULL) LIMIT $o_maxusers") };
  }elsif($o_rookie>0){
    @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s WHERE s.ScrapeDateRookie < $dtold OR s.ScrapeDateRookie IS NULL LIMIT $o_maxusers") };
  }else{
    @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s WHERE s.ScrapeDateStartup < $dtold OR s.ScrapeDateStartup IS NULL LIMIT $o_maxusers") };
  }
}else{
  if ($o_rookie > 0 and $o_startup > 0){
    $ulist = $dbh->selectall_hashref ("SELECT UserID FROM UserDraftsSearched","UserID");
  }elsif($o_rookie>0){
    $ulist = $dbh->selectall_hashref ("SELECT UserID FROM UserDraftsSearched WHERE ScrapeDateRookie > $dtold","UserID");
  }else{
    $ulist = $dbh->selectall_hashref ("SELECT UserID FROM UserDraftsSearched WHERE ScrapeDateStartup > $dtold","UserID");
  }
  $user = get_userid($o_username);
  if (defined($o_single)){ # Mode for only 1 user.
    get_Drafts($user);
    print "Have found ".scalar(@dlist)." drafts from ${countdrafts} detected on user ${o_username}.\n";
    print_drafts();
    exit(0);
  }
  get_leagues($user); # Gets all the Leagues from a user
  if (scalar(@leaguelist)>0){
    my $currentLeag = 0;
    my $nextLeagupdate = 0;
    my $progressLeag = Term::ProgressBar->new({name => 'Searching Users', count => scalar(@leaguelist), ETA => 'linear', remove => 1,silent => $o_progressbar});
    $progressLeag->max_update_rate(1);
    $progressLeag->message("Searching Users for ".scalar(@leaguelist)." Leagues");
    foreach my $leagueid ( @leaguelist ) { #For each league, get all users in those leagues
      $currentLeag++;
      $nextLeagupdate = $progressLeag->update($currentLeag) if $currentLeag > $nextLeagupdate;
      get_leagueusers($leagueid);
    }
    $progressLeag->update(scalar(@leaguelist)) if scalar(@leaguelist) >= $nextLeagupdate;
  }
}

if (scalar(@possibleusers)>0){
  my $currentUser = 0;
  my $nextUserupdate = 0;
  my $progressUser = Term::ProgressBar->new({name => 'Searching Drafts', count => scalar(@possibleusers), ETA => 'linear', remove => 1,silent => $o_progressbar});
  $progressUser->max_update_rate(1);
  $progressUser->message("Searching Drafts for ".scalar(@possibleusers)." Users");
  foreach my $useritem (@possibleusers){ #For each user in one of those leagues gets all their drafts
    $currentUser++;
    if ($o_minsearchage > 0){
      if (exists($ulist->{$useritem})){ #Check for userID in AlreadyScrapedUsers
        verb("Skipping User ${useritem} since it's already scraped");
        next;
      }
      # next unless (!exists($ulist->{$useritem}));
    }
    get_Drafts($useritem);
    $nextUserupdate = $progressUser->update($currentUser) if $currentUser > $nextUserupdate;
    if (((scalar(@Rlist) >= $o_rookie)) and ((scalar(@Slist) >= $o_startup))){ #If already found enough drafts for each type, stop!
      $progressUser->update(scalar(@possibleusers));
      print_drafts($currentUser);
      exit;
    }
  }
  $progressUser->update(scalar(@possibleusers)) if scalar(@possibleusers) >= $nextUserupdate;
}

print_drafts(scalar(@possibleusers));
exit;

sub get_userid { # Get the UserID from a username
  my $username = shift;
  my $userjson = get_json("https://api.sleeper.app/v1/user/${username}");
  return $userjson->{user_id};
}

sub get_leagues { # Get All leagues from a User
  my $userID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/user/${userID}/leagues/${sport}/${seasonleagues}");
  foreach my $leagueitem (@$leaguejson){
    push(@leaguelist, $leagueitem->{league_id});
  }
  return;
}

sub get_numberpicks {
  my $leagueID = shift;
  my $draftpicksjson = get_json("https://api.sleeper.app/v1/draft/${leagueID}/picks");
  my $pickcounter = 0;
  foreach my $draftpick ( @$draftpicksjson ) {
    $pickcounter++;
    last if ($pickcounter > 50);
    if ($draftpick->{picked_by} eq ""){ # If has no userID, discard it and ignore it
      insert_newdraft($leagueID);
      verb ("Skipped draft ${leagueID} since it has a pick with no userID");
      return 0;
    }
    if ($o_currentdrafttype eq "Rookie"){ # Drafts with less than 10 rounds but with veteran players... discard them and add as scraped.
      if (grep(/$draftpick->{player_id}/, @BannedPicks)){
        insert_newdraft($leagueID);
        verb ("Skipped draft ${leagueID} since it's a rookie draft with elite veteran picks");
        return 0;
      }
    }
    if (($o_currentdrafttype eq "Startup") and (defined($o_simple))){ #If only want draft without Rookies, If somebody has 0 years experience discard it.
      if ($draftpick->{metadata}->{years_exp} == 0){
        verb ("Skipped draft ${leagueID} since it's a Startup draft with Rookies when we are looking for simple drafts");
        return 0;
      }
    }

    if (defined($o_picks)){ #If only want draft with picks, check for kickers and if none
      if ($draftpick->{metadata}->{position} eq "K"){
        return keys @$draftpicksjson;
      }
    }
    if (($o_currentdrafttype eq "Startup") and (defined($o_nosimple))){ #If only want draft with Rookies, If somebody has 0 years experience discard it.
      if ($draftpick->{metadata}->{years_exp} == 0){
        return keys @$draftpicksjson;
      }
    }
  }
  if ((defined($o_picks)) || (defined($o_nosimple))){
    return 0;
    verb ("Skipped draft ${leagueID} since it's a Startup draft without Picks/Rookies and we were looking for one with them");
  }else{
    return keys @$draftpicksjson; # Return number of picks
  }
}

sub get_leagueusers { # Gets all Users from a League
  my $leagueID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/league/${leagueID}/users");
  foreach my $leagueuser ( @$leaguejson ) {
    push(@possibleusers, $leagueuser->{user_id});
  }
  return;
}

sub get_Drafts { # Gets All Draft for a User With certain settings
  my $user_id = shift;
  insert_newuser($user_id);
  my $draftsjson = get_json("https://api.sleeper.app/v1/user/${user_id}/drafts/${sport}/${seasondrafts}");
  if (scalar(@$draftsjson)>0){
    foreach my $draft( @$draftsjson ) {
      $countdrafts++;
      verb("Checking Draft ".$draft->{draft_id});
      if ($draft->{settings}->{rounds} < 10){

        if (scalar(@Rlist)>= $o_rookie){ # If we already have the max Rookie drafts skip.
          verb("Skipped ".$draft->{draft_id}." since it has ".$draft->{settings}->{rounds}." rounds and we already have ".scalar(@Rlist)." that is more than the ${o_rookie} rookie drafts needed");
          next;
        }
        $o_currentdrafttype = "Rookie";
      }
      if ($draft->{settings}->{rounds} >= 10){
        if(scalar(@Slist)>= $o_startup){ # If we already have the max Startup drafts skip.
          verb("Skipped ".$draft->{draft_id}." since it has ".$draft->{settings}->{rounds}." rounds and we already have ".scalar(@Slist)." that is more than the ${o_startup} startup drafts needed");
          next;
        }
        $o_currentdrafttype = "Startup";
      }
      if (exists($blist->{$draft->{draft_id}})){
        verb("Skipped ".$draft->{draft_id}." since it is on the blacklist.");
        next;
      }
      $blist->{$draft->{draft_id}} = $draft->{draft_id}; # Add this draft to list so it doesn't repeat for next users
      my $dt2 = $formatter->parse_datetime($draft->{start_time});
      my $days = $dt2->delta_days($dt1)->delta_days();
      if (!($o_maxage > $days)){
        verb("Skipped ".$draft->{draft_id}." since it is ${days} old (that is more than ${o_maxage})");
        next;
      }
      verb("Age of the draft: ${days} days");
      if (defined($o_drafting)){
        if (!($draft->{status} eq "drafting")){ # Only search for currently drafting
          verb("Skipped ".$draft->{draft_id}." since it is not currently drafting (status ".$draft->{status}.")");
          next;
        }
      }else{
        if (!(($draft->{status} eq "drafting") || ($draft->{status} eq "complete"))){ # Check that is not in pre-draft
          verb("Skipped ".$draft->{draft_id}." since it is not currently drafting or complete (status ".$draft->{status}.")");
          next;
        }
      }
      if (defined ($o_teams)){
        if (!($draft->{settings}->{teams} == $o_teams)){ # To filter by X team leagues
          verb("Skipped ".$draft->{draft_id}." since it has ".$draft->{settings}->{teams}." teams but we are looking for only ${o_teams} teams");
          next;
        }
      }
      next unless (get_numberpicks($draft->{draft_id}) > 0);
      insert_newdraft($draft->{draft_id});
      if ($dt2 > $dt1){ # Skip if draft is in the "future"
        verb("Skipped ".$draft->{draft_id}." since it seems to be in the future. Date: ".$dt2.".");
        next;
      }
      if (!(defined($draft->{league_id}))){ # To Filter Mocks
        verb("Skipped ".$draft->{draft_id}." since it has no leagueID");
      }
      next unless (defined($draft->{league_id}));
      if ($draft->{type} eq "auction"){ # To discard auctions
        verb("Skipped ".$draft->{draft_id}." since it is an auction");
        next;
      }
      if (defined ($draft->{settings}->{position_limit_k})){
        if ($draft->{settings}->{position_limit_k} == 1){ # To Filter Max 1 Kicker Drafts (some leagues use kickers as rookie placement, first kicker is 1.01/2.01/3.01 etc..)
          verb("Skipped ".$draft->{draft_id}." since has 1 limit kicker");
          next;
        }
      }
      if (($o_currentdrafttype eq "Rookie") and (grep(/\bdevy\b/i,$draft->{metadata}->{name}))){ # To discard rookie leagues with Devy in name Leagues
        verb("Skipped ".$draft->{draft_id}." since it has in 'Devy' the name as a rookie draft");
        next;
      }
      if (($o_currentdrafttype eq "Rookie") and (grep(/\bC2C\b/i,$draft->{metadata}->{name}))){ # To discard rookie leagues with C"C in name Leagues
        verb("Skipped ".$draft->{draft_id}." since it has in 'C2C' the name as a rookie draft");
        next;
      }
      if (grep(/\bfree\b/i,$draft->{metadata}->{name})){ # To discard leagues with Free in name Leagues
        verb("Skipped ".$draft->{draft_id}." since it has in 'Free' the name");
        next;
      }
      if (grep(/\bmock\b/i,$draft->{metadata}->{name})){ # To discard leagues with Mock Leagues
        verb("Skipped ".$draft->{draft_id}." since it has in 'mock' the name");
        next;
      }
      if (!(grep(/^$draft->{metadata}->{scoring_type}$/, @correctScorings))){ # To Filter non-Dynasty
        verb ("Skipped ".$draft->{draft_id}." since if has an incorrect scoring (".$draft->{metadata}->{scoring_type}.")");
        next;
      }
      if (!( ($draft->{settings}->{teams} == 12) || ($draft->{settings}->{teams} == 14) )){ # To filter 12/14 team leagues
        verb ("Skipped ".$draft->{draft_id}." since it does not have an acceptable number of teams (".$draft->{settings}->{teams}.")");
        next;
      }
      if (!(exists($draft->{settings}->{slots_super_flex}))){ # To Filter non-SF
        verb ("Skipped ".$draft->{draft_id}." since it's not a SuperFlex draft");
        next;
      }
      if (exists($draft->{settings}->{slots_def})){ # To Filter leagues with Defenses
        verb ("Skipped ".$draft->{draft_id}." since it has Defense slots");
        next;
      }
      if (exists($draft->{settings}->{slots_db})){ # To Filter leagues with IDP
        verb ("Skipped ".$draft->{draft_id}." since it has IDP slots");
        next;
      }
      if (exists($draft->{settings}->{slots_lb})){ # To Filter leagues with IDP
        verb ("Skipped ".$draft->{draft_id}." since it has IDP slots");
        next;
      }
      if (exists($draft->{settings}->{slots_dl})){ # To Filter leagues with IDP
        verb ("Skipped ".$draft->{draft_id}." since it has IDP slots");
        next;
      }
      if (exists($draft->{settings}->{slots_idp_flex})){ # To Filter leagues with IDP
        verb ("Skipped ".$draft->{draft_id}." since it has IDP slots");
        next;
      }
      if (defined($draft->{settings}->{slots_te})){
        if (!($draft->{settings}->{slots_te} < 2)){ # To 2TE Drafts
          verb ("Skipped ".$draft->{draft_id}." since it has 2 TE slots");
          next;
        }
      }
      verb("GOOD: Added draft ".$draft->{draft_id}."to the ${o_currentdrafttype} list");
      insert_gooddraft($draft->{draft_id});
      push (@Slist,$draft->{draft_id}) if ($o_currentdrafttype eq "Startup");
      push (@Rlist,$draft->{draft_id}) if ($o_currentdrafttype eq "Rookie");
      push (@dlist,$draft->{draft_id});
    }
  }
  return;
}

sub print_drafts{
  my $currentu = shift;
  print "Have found";
  print " ".scalar(@Rlist)." Rookie drafts (> ${o_rookie})," if ($o_rookie >0);
  print " ".scalar(@Slist)." Startup drafts (> ${o_startup})" if ($o_startup >0);
  print " from ${countdrafts} detected on ${currentu} users.\n";
  if (($o_rookie >0) and (scalar(@Rlist)>0)) {
    print "Rookie Drafts:\n";
    foreach my $draftID (@Rlist){
      print "https://sleeper.app/draft/nfl/${draftID}\n";
    }
  }
  if (($o_startup >0) and (scalar(@Slist)>0)){
    print "Startup Drafts:\n";
    foreach my $draftID (@Slist){
      print "https://sleeper.app/draft/nfl/${draftID}\n";
    }
  }
}

sub insert_newdraft{ # Adds a new League to the list
  my $new_draft = shift;
  my $sth = $dbh->prepare(qq/INSERT IGNORE INTO DraftsIgnored(DraftID,ScrapeDate,DType) VALUES ($new_draft,$dtnow,"$o_currentdrafttype") ON DUPLICATE KEY UPDATE DraftsIgnored.ScrapeDate = $dtnow;/);
  $sth->execute();
  $sth->finish;
}

sub insert_gooddraft{ # Adds a new League to the list
  my $new_draft = shift;
  my $drafttype = $o_currentdrafttype;
  $drafttype .= " Picks" if (defined($o_picks));
  my $sth = $dbh->prepare(qq/INSERT IGNORE INTO DraftsScraped(DraftID,ScrapeDate,DType) VALUES ($new_draft,$dtnow,"$drafttype") ON DUPLICATE KEY UPDATE DraftsScraped.ScrapeDate = $dtnow;/);
  $sth->execute();
  $sth->finish;
}

sub insert_newuser{ # Adds a new League to the list
  my $new_user = shift;
  if ($o_startup>0){
    my $sth = $dbh->prepare(qq/INSERT INTO UserDraftsSearched(UserID,ScrapeDateStartup) VALUES ($new_user,$dtnow) ON DUPLICATE KEY UPDATE UserDraftsSearched.ScrapeDateStartup = $dtnow;/);
    $sth->execute();
    $sth->finish;
  }
  if ($o_rookie>0){
    my $stt = $dbh->prepare(qq/INSERT INTO UserDraftsSearched(UserID,ScrapeDateRookie) VALUES ($new_user,$dtnow) ON DUPLICATE KEY UPDATE UserDraftsSearched.ScrapeDateRookie = $dtnow;/);
    $stt->execute();
    $stt->finish;
  }
  return;
}

sub get_json{ # Generic Decode Json from URL
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
    print "CRITICAL: Error '".$response->status_line."' on the url: ${url}\n";
    verb($response->error_as_HTML);
    return("");
  }
}

sub verb {
  my $t=shift;
  print STDOUT $t,"\n" if defined($o_verb);
}

sub print_usage {
  print "Usage: $0 -u <USERNAME> [-a <MAXAGE>] [-d] [-r] [-p] [-n] [-s] [-v] [-h]\n";
}

sub help {
  print "\nSearch Sleeper Drafts $0\n";
  print_usage();
  print <<EOT;
-A, --maxage <INTEGER>
    Max age in days of the start of the draft (to search for recent drafts). (default 31)
-a, --minage <INTEGER>
    Min age of user latest scrapedate (to make them rescrape). (default 5)
-M, --maxusers <INTEGER>
    Max number of users to scan (default 25)
-d, --drafting
    Only search for drafts currently Drafting.
-t, --teams <INTEGER>
    Only drafts with X managers.
-r, --rookies <INTEGER>
    How many rookie drafts to search (default 0).
-s, --startup <INTEGER>
    How many startups drafts to search (default 10).
-p, --picks
    Only Drafts that cointains at least a kicker selected (filter affects only startups only).
-n, --nosimple
    Only Startup Draft that contain rookie players.
-q, --simple
    Only Startup Draft that do contain rookie players.
-u, --username <STRING>
    Sleeper username to search.
-s, --singleuser
    Only Search Drafts by the specified user.
-y, --year <INTEGER>
    Year to search
-P, --progressbar
    Disable the progressbar (for verbose for example)
-v, --verbose
    Verbose mode.

-h, --help
    Print this help message.
EOT
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
    'h'     => \$o_help,            'help'            => \$o_help,
    'A:i'   => \$o_maxage,          'maxage:i'        => \$o_maxage,
    'a:i'   => \$o_minsearchage,    'minage:i'        => \$o_minsearchage,
    'M:i'   => \$o_maxusers,        'maxusers:i'      => \$o_maxusers,
    'd'     => \$o_drafting,        'drafting'        => \$o_drafting,
    't:i'   => \$o_teams,           'teams:i'         => \$o_teams,
    'r:i'   => \$o_rookie,          'rookies:i'       => \$o_rookie,
    's:i'   => \$o_startup,         'startup:i'       => \$o_startup,
    'p'     => \$o_picks,           'picks'           => \$o_picks,
    'n'     => \$o_nosimple,        'nosimple'        => \$o_nosimple,
    'q'     => \$o_simple,          'simple'          => \$o_simple,
    'u:s'   => \$o_username,        'username:s'      => \$o_username,
    's'     => \$o_single,          'singleuser'      => \$o_single,
    'y:i'   => \$seasonleagues,     'year:i'          => \$seasonleagues,
    'P'     => \$o_progressbar,     'progressbar'     => \$o_progressbar,
    'v'     => \$o_verb,            'verbose'         => \$o_verb
  );
  if(defined($o_help)) {
    help();
    exit 0;
  }
  if ($o_rookie == 0 and $o_startup == 0) {
    print "You have to choose more than 0 in Startups of Rookie drafts\n";
    help();
    exit 0;
  }
  if ((defined($o_progressbar)) || (defined($o_verb))){
    $o_progressbar = 1;
  }
  if ((defined($o_nosimple)) and (defined($o_simple))){
    print "You can't filter by both Simple and no Simple\n";
    help();
    exit 0;
  }
  if (defined($o_teams)){
    help() unless (($o_teams == 12) || ($o_teams == 14));
    exit 2 unless (($o_teams == 12) || ($o_teams == 14));
  }
}