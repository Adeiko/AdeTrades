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

my ($o_help,$o_verb,$o_username,$o_rookie,$o_picks,$o_teams,$o_nosimple,$o_single,$o_drafting);
my (@possibleusers,@leaguelist,@expandedusers,@dlist);
my ($user,$blist,$ulist);

#Variables
my $o_maxage = 14;
my $o_minsearchage = 7;
my $o_maxusers = 25;
my $o_maxdrafts = 25;
my $sport = "nfl";
my $seasonleagues = "2022";
my $seasondrafts = "2022";
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

if (defined($o_rookie)){
  $blist = $dbh->selectall_hashref ('SELECT DraftID FROM DraftsIgnored WHERE DType = "Rookie"',"DraftID");
}else{
  $blist = $dbh->selectall_hashref ('SELECT DraftID FROM DraftsIgnored WHERE DType = "Startup"',"DraftID");
}


if(!defined($o_username)) {
  if ($o_minsearchage == 0){
    @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s LIMIT $o_maxusers") };
  }else{
    if ($o_rookie){
      @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s WHERE s.ScrapeDateRookie < $dtold OR s.ScrapeDateRookie IS NULL LIMIT $o_maxusers") };
    }else{
      @possibleusers = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM UserDraftsSearched s WHERE s.ScrapeDateStartup < $dtold OR s.ScrapeDateStartup IS NULL LIMIT $o_maxusers") };
    }
  }
}else{
  if ($o_rookie){
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
}

if (scalar(@possibleusers)>0){
  my $currentUser = 0;
  my $nextUserupdate = 0;
  my $progressUser = Term::ProgressBar->new({name => 'Searching Drafts', count => scalar(@possibleusers), ETA => 'linear', remove => 1});
  $progressUser->max_update_rate(1);
  $progressUser->message("Searching Drafts for ".scalar(@possibleusers)." Users");
  foreach my $useritem (@possibleusers){ #For each user in one of those leagues gets all their drafts
    $currentUser++;
    if ($o_minsearchage > 0){
      verb("Skipping User ${useritem}");
      next unless (!exists($ulist->{$useritem})); #Check for userID in AlreadyScrapedUsers
    }
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
      return 0;
    }
    if (defined($o_rookie)){ # Drafts with less than 10 rounds but with veteran players... discard them and add as scraped.
      if (grep(/$draftpick->{player_id}/, @BannedPicks)){
        insert_newdraft($leagueID);
        return 0;
      }
    }
    if (defined($o_picks)){ #If only want draft with picks, check for kickers and if none
      if ($draftpick->{metadata}->{position} eq "K"){
        return keys @$draftpicksjson;
      }
    }
    if (defined($o_nosimple)){ #If only want draft with picks, check for kickers and if none
      if ($draftpick->{metadata}->{years_exp} == 0){
        return keys @$draftpicksjson;
      }
    }
  }
  if ( (defined($o_picks)) || (defined($o_nosimple)) ){
    return 0;
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
      if (defined ($o_teams)){
        next unless ($draft->{settings}->{teams} == $o_teams); # To filter by X team leagues
      }
      next unless (get_numberpicks($draft->{draft_id}) > 0);
      insert_newdraft($draft->{draft_id});
      next if ($dt2 > $dt1); # Skip if draft is in the "future"
      next unless (defined($draft->{league_id})); # To Filter Mocks
      next if ($draft->{type} eq "auction"); # To discard auctions
      if (defined ($draft->{settings}->{position_limit_k})){
        next if ($draft->{settings}->{position_limit_k} == 1); # To Filter Max 1 Kicker Drafts
      }
      next if (grep(/\bfree\b/i,$draft->{metadata}->{name})); # To discard leagues with Free in name Leagues
      next if (grep(/\bmock\b/i,$draft->{metadata}->{name})); # To discard leagues with Mock Leagues
      next unless (grep(/^$draft->{metadata}->{scoring_type}$/, @correctScorings)); # To Filter non-Dynasty
      next unless ( ($draft->{settings}->{teams} == 12) || ($draft->{settings}->{teams} == 14) ); # To filter 12/14 team leagues
      next unless (exists($draft->{settings}->{slots_super_flex})); # To Filter non-SF
      next if (exists($draft->{settings}->{slots_def})); # To Filter leagues with Defenses
      next if (exists($draft->{settings}->{slots_db})); # To Filter leagues with IDP
      next if (exists($draft->{settings}->{slots_lb})); # To Filter leagues with IDP
      next if (exists($draft->{settings}->{slots_dl})); # To Filter leagues with IDP
      next if (exists($draft->{settings}->{slots_idp_flex})); # To Filter leagues with IDP
      if (defined($draft->{settings}->{slots_te})){
          next unless ($draft->{settings}->{slots_te} < 2); # To 2TE Drafts
      }
      verb("LeagueID: ".$draft->{league_id});
      push @dlist,$draft->{draft_id};
    }
  }
  return;
}

sub print_drafts{
  foreach my $draftID (@dlist){
    print "https://sleeper.app/draft/nfl/${draftID}\n";
  }
}

sub insert_newdraft{ # Adds a new League to the list
  my $new_draft = shift;
  my $drafttype = "Startup";
  $drafttype = "Rookie" if (defined($o_rookie));
  my $sth = $dbh->prepare(qq/INSERT IGNORE INTO DraftsIgnored(DraftID,ScrapeDate,DType) VALUES ($new_draft,$dtnow,"$drafttype") ON DUPLICATE KEY UPDATE DraftsIgnored.ScrapeDate = $dtnow;/);
  $sth->execute();
  $sth->finish;
}

sub insert_newuser{ # Adds a new League to the list
  my $new_user = shift;
  my $scolumn = "ScrapeDateStartup";
  $scolumn = "ScrapeDateRookie" if ($o_rookie);
  my $sth = $dbh->prepare(qq/INSERT INTO UserDraftsSearched(UserID,$scolumn) VALUES ($new_user,$dtnow) ON DUPLICATE KEY UPDATE UserDraftsSearched.$scolumn = $dtnow;/);
  $sth->execute();
  $sth->finish;
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
  print "Usage: $0 -u <USERNAME> [-m <MAXDRAFTS>] [-a <MAXAGE>] [-d] [-r] [-p] [-n] [-s] [-v] [-h]\n";
}

sub help {
  print "\nSearch Sleeper Drafts $0\n";
  print_usage();
  print <<EOT;
-u, --username
    Sleeper username to search.
-a, --maxage
    Max age of the start of the draft (to search for recent drafts). (default 31)
-A, --minage
    Min age of user latest scrapedate (to make them rescrape). (default 5)
-d, --drafting
    Only search for drafts currently Drafting.
-m, --maxdrafts
    Max number of drafts to search for. (default 25)
-M, --maxusers
    Max number of users to scan (default 25)
-n, --norookies
    Only Startup Draft that contain rookie players.
-r, --rookies
    Only Rookie Drafts (< 10 rounds).
-p, --picks
    Only Drafts that cointains at least a kicker selected.
-s, --singleuser
    Only Search Drafts by the specified user.
-y, --year
    Year to search
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
    'u:s'   => \$o_username,        'username:s'      => \$o_username,
    'r'     => \$o_rookie,          'rookies'         => \$o_rookie,
    'p'     => \$o_picks,           'picks'           => \$o_picks,
    'n'     => \$o_nosimple,       'nosimple'        => \$o_nosimple,
    't:i'   => \$o_teams,           'teams:i'         => \$o_teams,
    'a:i'   => \$o_maxage,          'maxage:i'        => \$o_maxage,
    'A:i'   => \$o_minsearchage,    'minage:i'        => \$o_minsearchage,
    'm:i'   => \$o_maxdrafts,       'maxdrafts:i'     => \$o_maxdrafts,
    'M:i'   => \$o_maxusers,        'maxusers:i'      => \$o_maxusers,
    's'     => \$o_single,          'singleuser'      => \$o_single,
    'd'     => \$o_drafting,        'drafting'        => \$o_drafting,
    'y'     => \$seasonleagues,     'year'            => \$seasonleagues,
    'v'     => \$o_verb,            'verbose'         => \$o_verb
  );
  if(defined($o_help)) {
    help();
    exit 0;
  }
  if (defined($o_teams)){
    help() unless (($o_teams == 12) || ($o_teams == 14));
    exit 2 unless (($o_teams == 12) || ($o_teams == 14));
  }
}