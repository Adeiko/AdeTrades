#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use JSON::XS 'decode_json';
use Scalar::Util qw(looks_like_number);
use Getopt::Long;
use DateTime;
use DateTime::Format::Epoch;
use Term::ProgressBar;
use DBI;
use Text::CSV_XS qw( csv );
use Git::Repository;
use Data::Dumper;

my ($o_help,$o_verb,$o_update,$o_newleagues,$o_leagueinfo,$o_leaguerookies,$o_updatedb,$o_expandusersearch,$o_rosteridinfo,$o_export);
my ($tradedb,$transtradelist,$transpicklist,$transignorelist,$translist,$leaguehashlist,$userhashlist,$players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds);
my (@LeagueList,@playerstemp,@LeagueSearchList,@UserSearchList,@LeagueNameList,@LeagueRosterIDList);
my %dlist;

my $sport = "nfl";
my $season = "2021";
my $gitrepodir = "XXXX";

# Default thresholds
my $o_maxleagues = 50;
my $o_refreshage = 5;
my $o_refreshrosterids = 90;
my $o_currentweek = 1;
my $maxIteminTrade = 5;

check_options(); #Check for the arguments

#Database configuration
my $database =          "XXXX";
my $database_hostname = "XXXX";
my $database_port =     "XXXX";
my $database_user =     "XXXX";
my $database_password = "XXXX";

my $dbh = DBI->connect("DBI:mysql:database=$database;host=$database_hostname;port=$database_port", $database_user, $database_password,{PrintError => 1, RaiseError => 1}) || die  "ERROR: Error de conexion a la BBDD ${database_hostname}:${database_port} - ${database}\n";

# DateTime variables
my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
my $formatter = DateTime::Format::Epoch->new(epoch => $dt,unit => 'milliseconds');
my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(days => $o_refreshage)->epoch();
my $dtoldrosters = DateTime->now()->subtract(days => $o_refreshrosterids)->epoch();

if ($o_newleagues){ #To find new leagues
  $leaguehashlist = $dbh->selectall_hashref ("SELECT LeagueID FROM Leagues","LeagueID");
  $userhashlist = $dbh->selectall_hashref ("SELECT UserID FROM SearchedUsers","UserID");
  my $newleagueuser = get_userid($o_newleagues);
  get_leagues($newleagueuser);
  if (scalar(@LeagueSearchList)>0){
    my $currentLeag = 0;
    my $nextLeagupdate = 0;
    my $progressLeag = Term::ProgressBar->new({name  => 'Searching Users', count => scalar(@LeagueSearchList), ETA   => 'linear', remove => 1});
    $progressLeag->max_update_rate(1);
    $progressLeag->message("Searching Users for ".scalar(@LeagueSearchList)." Leagues");
    foreach my $leaguesearch ( @LeagueSearchList ) { #For each league, get all users in those leagues
      $currentLeag++;
      $nextLeagupdate = $progressLeag->update($currentLeag) if $currentLeag > $nextLeagupdate;
      if (!(defined($o_expandusersearch))){
        next if (exists($leaguehashlist->{$leaguesearch})); #To skip recheck leagues already in the DB (but it could expand the search).
      }
      get_leagueusers($leaguesearch);
    }
    $progressLeag->update(scalar(@LeagueSearchList)) if scalar(@LeagueSearchList) >= $nextLeagupdate;
  }
  if (scalar(@UserSearchList)>0){
    my $currentUser = 0;
    my $nextUserupdate = 0;
    my $progressUser = Term::ProgressBar->new({name  => 'Searching Leagues', count => scalar(@UserSearchList), ETA   => 'linear', remove => 1});
    $progressUser->max_update_rate(1);
    $progressUser->message("Searching Leagues for ".scalar(@UserSearchList)." Users");
    foreach my $useritem (@UserSearchList){ #For each user in one of those leagues gets their leagues
      next if (exists($userhashlist->{$useritem}));
      get_leagues($useritem);
      insert_searchedUser($useritem); #Adds them to the "ignore" list.
      $currentUser++;
      $nextUserupdate = $progressUser->update($currentUser) if $currentUser > $nextUserupdate;
    }
    $progressUser->update(scalar(@UserSearchList)) if scalar(@UserSearchList) >= $nextUserupdate;
  }
  my $leaguecount = 0;
  foreach my $newleague ( @LeagueSearchList ) {
    next if (exists($leaguehashlist->{$newleague})); # Only add leagues not already in the DB.
    verb ("Found new league: $newleague");
    insert_newleague($newleague);
    $leaguecount++;
  }
  print "$leaguecount new leagues (from ". scalar(@LeagueSearchList)." found) added from the query of user ${o_newleagues}\n";
}

if ($o_update){
  $transpicklist = $dbh->selectall_hashref ("SELECT TradeID FROM Trades","TradeID");
  $transtradelist = $dbh->selectall_hashref ("SELECT TradeID FROM PickTrades","TradeID");
  $transignorelist = $dbh->selectall_hashref ("SELECT TradeID FROM RevertedTrades","TradeID");
  $translist = { %$transpicklist, %$transtradelist, %$transignorelist };
  get_leaguelist($o_maxleagues);
  if (scalar(@LeagueList) > 0){
    my $currentLeague = 0;
    my $next_update = 0;
    my $progress = Term::ProgressBar->new({name  => 'Searching Trades', count => scalar(@LeagueList), ETA   => 'linear', remove => 1});
    $progress->max_update_rate(1);
    $progress->message("Searching for Trades for ".scalar(@LeagueList)." Leagues (still ".get_leaguePendingUpdate()." pending)\n");
    foreach my $leagueN (@LeagueList){
      $currentLeague++;
      get_trades($leagueN,$o_currentweek);
      $next_update = $progress->update($currentLeague) if $currentLeague > $next_update;
    }
    $progress->update(scalar(@LeagueList)) if scalar(@LeagueList) >= $next_update;
    insert_tradeHash();
  }else{
    print ("No leagues pending to update\n");
  }
}

if ($o_leagueinfo){
  get_leaguelistUpdateInfo($o_maxleagues);
  if (scalar(@LeagueNameList) > 0){
    my $currentInfo = 0;
    my $nextInfoupdate = 0;
    my $progressInfo = Term::ProgressBar->new({name  => 'Finding League Info', count => scalar(@LeagueNameList), ETA   => 'linear', remove => 1});
    $progressInfo->max_update_rate(1);
    $progressInfo->message("Searching for Info  for ".scalar(@LeagueNameList)." Leagues\n");
    foreach my $leagueU (@LeagueNameList){
      get_leagueinfo($leagueU);
      $currentInfo++;
      $nextInfoupdate = $progressInfo->update($currentInfo) if $currentInfo > $nextInfoupdate;
    }
    $progressInfo->update(scalar(@LeagueNameList)) if scalar(@LeagueNameList) >= $nextInfoupdate;
  }else{
    print "No League info pending to update\n";
  }
}

if ($o_rosteridinfo){
  get_leaguelistUpdateRosterID($o_maxleagues);
  if (scalar(@LeagueRosterIDList) > 0){
    my $currentRosterID = 0;
    my $nextRosterIDupdate = 0;
    my $progressRosterID = Term::ProgressBar->new({name  => 'Finding RosterID data', count => scalar(@LeagueRosterIDList), ETA   => 'linear', remove => 1});
    $progressRosterID->max_update_rate(1);
    $progressRosterID->message("Searching for RosterIDs for ".scalar(@LeagueRosterIDList)." Leagues\n");
    foreach my $leagueU (@LeagueRosterIDList){
      get_leaguerosterID($leagueU);
      $currentRosterID++;
      $nextRosterIDupdate = $progressRosterID->update($currentRosterID) if $currentRosterID > $nextRosterIDupdate;
    }
    $progressRosterID->update(scalar(@LeagueRosterIDList)) if scalar(@LeagueRosterIDList) >= $nextRosterIDupdate;
  }else{
    print "No League RosterID info pending to update\n";
  }
}

if ($o_leaguerookies){
  get_updateleaguelistdrafts($o_maxleagues);
  foreach my $leagueU (@LeagueNameList){
    get_leagueinfo($leagueU);
  }
}

export_data() if (defined($o_export)); #ExportDatatoCSV

exit;

sub get_leaguelistUpdateInfo{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT LeagueID FROM Leagues WHERE trade_deadline IS NULL LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueNameList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguelistUpdateRosterID{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/  SELECT DISTINCT l.LeagueID FROM Leagues l LEFT JOIN RosterID_Reference r ON r.LeagueID = l.LeagueID WHERE r.LeagueID IS NULL AND (r.LastUpdate < $dtoldrosters OR r.LastUpdate IS NULL) LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueRosterIDList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguerosterID{
  my $league_id = shift;
  verb ("League: ${league_id}");
  my $rosterid_json_string = undef;
  my $rosterid_url = "https://api.sleeper.app/v1/league/$league_id/rosters";
  my $rosterid_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $rosterid_header = HTTP::Request->new(GET => $rosterid_url);
  $rosterid_header->header(content_type => "application/json",
                         accept => "application/json");
  my $rosterid_request = HTTP::Request->new('GET', $rosterid_url, $rosterid_header);
  my $rosterid_response = $rosterid_ua->request($rosterid_request);
  if ($rosterid_response->is_success){
    $rosterid_json_string = $rosterid_response->content;
    my $rosteridjson = decode_json($rosterid_json_string);
    my $sth = $dbh->prepare(q{INSERT IGNORE INTO RosterID_Reference(LeagueID) VALUES (?)},{},);
    $sth->execute($league_id);
    $sth->finish;
    foreach my $roster( @$rosteridjson ) {
      my $ownerid;
      if (defined($roster->{owner_id})){ $ownerid = $roster->{owner_id} }else{ $ownerid = "0" };
      if (!(defined($roster->{owner_id}))){next;};
      my $sts = $dbh->prepare(qq/UPDATE RosterID_Reference SET RosterID$roster->{roster_id} = $ownerid WHERE LeagueID = $league_id ;/);
      $sts->execute();
      $sts->finish;
    }
    my $stq = $dbh->prepare(qq/UPDATE RosterID_Reference SET LastUpdate = $dtnow WHERE LeagueID = $league_id/);
    $stq->execute();
    $stq->finish;
  }
}

sub get_leagueinfo { #Get All leagues from a User
  my $league_id = shift;
  my $league_json_string = undef;
  my $league_url = "https://api.sleeper.app/v1/league/${league_id}";
  my $league_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $league_header = HTTP::Request->new(GET => $league_url);
  $league_header->header(content_type => "application/json",
                         accept => "application/json");
  my $league_request = HTTP::Request->new('GET', $league_url, $league_header);
  my $league_response = $league_ua->request($league_request);
  if ($league_response->is_success){
    $league_json_string = $league_response->content;
  }elsif ($league_response->is_error){
    print "CRITICAL: Error: $league_url\n";
    update_PossibleDeleted($league_id);
    verb($league_response->error_as_HTML);
    return;
  }
  my $leaguejson = decode_json($league_json_string);
  my ($league_name,$league_total_rosters,$league_taxi_slots,$league_rec,$league_bonus_rec_wr,$league_bonus_rec_te,$league_bonus_rec_rb,$league_pass_td,$league_pass_int,$league_draftrounds,$league_status,$league_draftid,$league_tradedl,$league_previousleague);
  if (exists($leaguejson->{name})){ $league_name = $leaguejson->{name} }else{ $league_name = "NoName" };
  if (exists($leaguejson->{total_rosters})){ $league_total_rosters =$leaguejson->{total_rosters} }else{ $league_total_rosters = 0 };
  if (exists($leaguejson->{status})){ $league_status =$leaguejson->{status} }else{ $league_status = 0 };
  if (exists($leaguejson->{previous_league_id})){ $league_previousleague =$leaguejson->{previous_league_id} }else{ $league_previousleague = 0 };
  if (exists($leaguejson->{draft_id})){ $league_draftid =$leaguejson->{draft_id} }else{ $league_draftid = 0 };
  if (exists($leaguejson->{settings}->{taxi_slots})){ $league_taxi_slots = $leaguejson->{settings}->{taxi_slots} }else{ $league_taxi_slots = 0 };
  if (exists($leaguejson->{settings}->{trade_deadline})){ $league_tradedl = $leaguejson->{settings}->{trade_deadline} }else{ $league_tradedl = 0 };
  if (exists($leaguejson->{settings}->{draft_rounds})){ $league_draftrounds = $leaguejson->{settings}->{draft_rounds} }else{ $league_draftrounds = 0 };
  if (exists($leaguejson->{scoring_settings}->{rec})){ $league_rec = $leaguejson->{scoring_settings}->{rec} }else{ $league_rec = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_wr})){ $league_bonus_rec_wr = $leaguejson->{scoring_settings}->{bonus_rec_wr} }else{ $league_bonus_rec_wr = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_te})){ $league_bonus_rec_te = $leaguejson->{scoring_settings}->{bonus_rec_te} }else{ $league_bonus_rec_te = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_rb})){ $league_bonus_rec_rb = $leaguejson->{scoring_settings}->{bonus_rec_rb} }else{ $league_bonus_rec_rb = 0 };
  if (exists($leaguejson->{scoring_settings}->{pass_td})){ $league_pass_td = $leaguejson->{scoring_settings}->{pass_td} }else{ $league_pass_td = 0 };
  if (exists($leaguejson->{scoring_settings}->{pass_int})){ $league_pass_int = $leaguejson->{scoring_settings}->{pass_int} }else{ $league_pass_int = 0 };
  if (!defined($league_previousleague)){$league_previousleague = 0};
  my $Positions_QB = grep { $_ eq "QB" } @{ $leaguejson->{roster_positions} };
  my $Positions_RB = grep { $_ eq "RB" } @{ $leaguejson->{roster_positions} };
  my $Positions_WR = grep { $_ eq "WR" } @{ $leaguejson->{roster_positions} };
  my $Positions_TE = grep { $_ eq "TE" } @{ $leaguejson->{roster_positions} };
  my $Positions_FLEX = grep { $_ eq "FLEX" or $_ eq "REC_FLEX"} @{ $leaguejson->{roster_positions} };
  my $Positions_SUPER_FLEX = grep { $_ eq "SUPER_FLEX" } @{ $leaguejson->{roster_positions} };
  my $Positions_BN = grep { $_ eq "BN" } @{ $leaguejson->{roster_positions} };
  my $total_players = $Positions_QB + $Positions_RB + $Positions_WR + $Positions_TE + $Positions_FLEX + $Positions_SUPER_FLEX + $Positions_BN;
  my $league_name_q = $dbh->quote($league_name);
  my $query = qq/UPDATE Leagues SET name = $league_name_q, total_rosters = $league_total_rosters, taxi_slots = $league_taxi_slots, rec_bonus = $league_rec, bonus_rec_wr = $league_bonus_rec_wr, bonus_rec_te = $league_bonus_rec_te, bonus_rec_rb = $league_bonus_rec_rb, pass_td = $league_pass_td, pass_int = $league_pass_int, roster_positions_QB = $Positions_QB, roster_positions_RB = $Positions_RB, roster_positions_WR = $Positions_WR, roster_positions_TE = $Positions_TE, roster_positions_FLEX = $Positions_FLEX, roster_positions_SUPER_FLEX = $Positions_SUPER_FLEX, roster_positions_BN = $Positions_BN, total_players = $total_players, RookieRounds = $league_draftrounds, RookieTimeUpdate = $dtnow, RookieStatus = "$league_status", RookieDraft = $league_draftid, trade_deadline = $league_tradedl, previous_league_id = $league_previousleague WHERE LeagueID = $league_id;/;
  my $sth = $dbh->prepare($query);
  verb ("Query: ${query}");
  $sth->execute();
  $sth->finish;
  verb ("League ${league_id}");
  verb ("league_name: ${league_name}");
  verb ("league_total_rosters: ${league_total_rosters}");
  verb ("league_taxi_slots: ${league_taxi_slots}");
  verb ("league_rec: ${league_rec}");
  verb ("league_bonus_rec_wr: ${league_bonus_rec_wr}");
  verb ("league_bonus_rec_te: ${league_bonus_rec_te}");
  verb ("league_bonus_rec_rb: ${league_bonus_rec_rb}");
  verb ("league_pass_td: ${league_pass_td}");
  verb ("league_pass_int: ${league_pass_int}");
  verb ("Positions_QB: ${Positions_QB}");
  verb ("Positions_RB: ${Positions_RB}");
  verb ("Positions_WR: ${Positions_WR}");
  verb ("Positions_TE: ${Positions_TE}");
  verb ("Positions_FLEX: ${Positions_FLEX}");
  verb ("Positions_SUPER_FLEX: ${Positions_SUPER_FLEX}");
  verb ("Positions_BN: ${Positions_BN}");
  verb ("total_players: ${total_players}");
  return;
}

sub insert_tradeHash{ # Imports  all the %TradeDB to the MySQL
  foreach my $leaguehash (keys %$tradedb) {
    foreach my $transhash (keys %{%$tradedb{$leaguehash}}) {
      if (looks_like_number($transhash)){
        foreach my $ownershash (keys %{%$tradedb{$leaguehash}->{$transhash}}) {
          if (looks_like_number($ownershash)){
            for my $playerhash (@{$tradedb->{$leaguehash}->{$transhash}->{$ownershash}}) {
              push (@playerstemp,$playerhash);
            }
            if (!defined $players1){$players1 = join("; ",@playerstemp)}elsif(!defined $players2){$players2 = join("; ",@playerstemp)}else{$players3 = join("; ",@playerstemp)};
            if (!defined $owner1){$owner1 = $ownershash}elsif(!defined $owner2){$owner2 = $ownershash}else{$owner3 = $ownershash};
            @playerstemp = ();
          }
        }
        if (exists($tradedb->{$leaguehash}->{$transhash}->{draftrounds})){ $draftrounds = $tradedb->{$leaguehash}->{$transhash}->{draftrounds} }else{ $draftrounds = 0 };
        verb("League: ${leaguehash} Transaction ${transhash} Time $$tradedb{$leaguehash}->{$transhash}->{date}");
        verb ("Players1: ${players1}") if defined($players1);
        verb ("Owner1: ${owner1}") if defined($owner1);
        verb ("Players2: ${players2}") if defined($players2);
        verb ("Owner2: ${owner2}") if defined($owner2);
        verb ("Players3: ${players3}") if defined($players3);
        verb ("Owner3: ${owner3}") if defined($owner3);
        verb ("DraftRounds: ${draftrounds}") if defined($draftrounds);
        insert_newtrade($transhash,$leaguehash,$tradedb->{$leaguehash}->{$transhash}->{date},$players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds);
        ($players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds) = undef;
      }
    }
  }
}

sub get_LeagueDrafts { # Gets draft slots from the league of that year
  my $league_id = shift;
  my $drafts_json_string = undef;
  my $drafts_url = "https://api.sleeper.app/v1/league/$league_id/drafts";
  my $drafts_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $drafts_header = HTTP::Request->new(GET => $drafts_url);
  $drafts_header->header(content_type => "application/json",
                         accept => "application/json");
  my $drafts_request = HTTP::Request->new('GET', $drafts_url, $drafts_header);
  my $drafts_response = $drafts_ua->request($drafts_request);
  if ($drafts_response->is_success){
    $drafts_json_string = $drafts_response->content;
    my $draftsjson = decode_json($drafts_json_string);
    foreach my $draft( @$draftsjson ) {
      next unless ($draft->{season} eq $season);
      my $draft_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
      my $draft_url = "https://api.sleeper.app/v1/draft/$draft->{draft_id}";
      my $draft_json_string = undef;
      my $draft_header = HTTP::Request->new(GET => $draft_url);
      $draft_header->header(content_type => "application/json",
                            accept => "application/json");
      my $draft_request = HTTP::Request->new('GET', $draft_url, $draft_header);
      my $draft_response = $draft_ua->request($draft_request);
      if ($draft_response->is_success){
        $draft_json_string = $draft_response->content;
        my $draftjson = decode_json($draft_json_string);
        $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{draftrounds} = $draftjson->{settings}->{rounds} if (exists( $draftjson->{settings}->{rounds}));
        $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{last_picked} = $draftjson->{last_picked} if (exists( $draftjson->{last_picked}));
        if (exists( $draftjson->{slot_to_roster_id})){
          foreach my $slots( $draftjson->{slot_to_roster_id} ) {
            for my $slot (keys(%$slots)) {
              $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{slots}->{$slots->{$slot}} = $slot unless ($slot eq '' );
            }
          }
        }else{
          $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{slots} = "0";
        }
      }
    }
  }
  return;
}

sub get_player{ # Gets the Player String from Sleeper_ID
  my $splayer_id = shift;
  return unless (looks_like_number($splayer_id));
  my $query = qq/SELECT first_name,last_name,fantasy_positions,team FROM Players WHERE player_id=$splayer_id/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  my ($qfname,$qlname,$qpos,$qteam) = $sth->fetchrow;
  $sth->finish;
  if (!(defined($qfname))){
    print "Error: the player ${splayer_id} has not been found";
    return;
  }
  return "$qfname $qlname,$qpos,$qteam";
}

sub get_ownerid{ # Gets the owner of the RosterID
  my $sroster_id = shift;
  my $sleague_id = shift;
  return unless (looks_like_number($sroster_id));
  return unless (looks_like_number($sleague_id));
  if ($sroster_id > 14){
    return $sroster_id;
  }
  my $query = qq/SELECT RosterID${sroster_id} FROM RosterID_Reference WHERE LeagueID=${sleague_id}/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  my $qownerid = $sth->fetchrow;
  $sth->finish;
  if (!(defined($qownerid))){
    return $sroster_id;
  }
  return $qownerid;
}

sub get_leaguelist{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT LeagueID FROM Leagues WHERE PossibleDeleted = FALSE AND LastUpdate < $dtold OR LastUpdate IS NULL LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguePendingUpdate{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT COUNT(LeagueID) FROM Leagues WHERE PossibleDeleted = FALSE AND LastUpdate < $dtold OR LastUpdate IS NULL/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  my $pendingleagues = $sth->fetchrow;
  $sth->finish;
  return $pendingleagues;
}

sub get_updateleaguelistdrafts{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT LeagueID FROM Leagues WHERE RookieStatus = 'pre_draft' AND (RookieTimeUpdate < '$dtold' OR RookieTimeUpdate IS NULL) AND PossibleDeleted = FALSE LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueNameList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_trades { #Get All trades from a League
  my $league_id = shift;
  my $WeekID = shift;
  my $league_json_string = undef;
  my $current_draft = undef;
  verb("Getting trades of $league_id");
  my $league_url = "https://api.sleeper.app/v1/league/${league_id}/transactions/${WeekID}";
  my $league_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $league_header = HTTP::Request->new(GET => $league_url);
  $league_header->header(content_type => "application/json",
                         accept => "application/json");
  my $league_request = HTTP::Request->new('GET', $league_url, $league_header);
  my $league_response = $league_ua->request($league_request);
  if ($league_response->is_success){
    $league_json_string = $league_response->content;
  }elsif ($league_response->is_error){
    print "CRITICAL: Error: $league_url\n";
    update_PossibleDeleted($league_id);
    verb($league_response->error_as_HTML);
    next;
  }
  my $tradesjson = decode_json($league_json_string);
  foreach my $trade( @$tradesjson ) {
    next unless ($trade->{type} eq "trade");
    next unless ($trade->{status} eq "complete");
    next if (exists($translist->{$trade->{transaction_id}}));
    $tradedb->{$league_id}->{$trade->{transaction_id}}->{date} = $trade->{status_updated};
    if (defined($trade->{adds})){
      foreach my $tradetadds( $trade->{adds} ) {
        for my $keyadd (keys(%$tradetadds)) {
          my $userownerid = get_ownerid($tradetadds->{$keyadd},$league_id);
          push @{$tradedb->{$league_id}->{$trade->{transaction_id}}->{$userownerid}}, get_player($keyadd);
        }
      }
    }
    my ($oldtime,$newtime);
    if (defined($trade->{draft_picks})){
      foreach my $tradetpicks( $trade->{draft_picks} ) {
        for my $keypicks (@$tradetpicks) {
          my $picktext = undef;
          if ($keypicks->{season} eq $season){
            if (!exists($tradedb->{$league_id}->{drafts})){
              get_LeagueDrafts($league_id);
            }
            if (scalar(keys %{%$tradedb{$league_id}->{drafts}}) == 1){
              foreach my $leaguekeys (keys %{%$tradedb{$league_id}->{drafts}}) {
                $current_draft = $leaguekeys;
              }
            }else{
              my $drafttime =  $formatter->parse_datetime($trade->{status_updated});
              foreach my $leaguekeys (keys %{%$tradedb{$league_id}->{drafts}}) {
                $newtime = $formatter->parse_datetime($tradedb->{$league_id}->{drafts}->{$leaguekeys}->{last_picked});
                if (!(defined($oldtime))){
                  $oldtime = $formatter->parse_datetime($tradedb->{$league_id}->{drafts}->{$leaguekeys}->{last_picked});
                  $current_draft = $leaguekeys;
                }else{
                  verb("TradeDate: ".${drafttime}->dmy('/')." NewTime: ".${newtime}->dmy('/')." and OldTime: ".${oldtime}->dmy('/'));
                  if (($drafttime > $oldtime) and ($oldtime > $newtime)){
                    verb("Case 1: Trade is NEWER than the OldDraft || the OldDraft is NEWER than the NewDraft - Keep Old");
                  }elsif(($drafttime < $oldtime) and ($oldtime > $newtime) and ($drafttime > $newtime)){
                    verb("Case 2: Trade is OLDER than the OldDraft || the OldDraft is NEWER than the NewDraft || The Trade is NEWER than the NewDraft - Keep Old");
                  }elsif(($drafttime < $oldtime) and ($oldtime > $newtime) and ($drafttime < $newtime)){
                    verb("Case 3: Trade is OLDER than the OldDraft || the OldDraft is NEWER than the NewDraft || The Trade is OLDER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime > $oldtime) and ($oldtime < $newtime) and ($drafttime > $newtime)){
                    verb("Case 4: Trade is NEWER than the OldDraft || the OldDraft is OLDER than the NewDraft || The Trade is NEWER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime > $oldtime) and ($oldtime < $newtime) and ($drafttime < $newtime)){
                    verb("Case 5: Trade is NEWER than the OldDraft || the OldDraft is OLDER than the NewDraft || The Trade is OLDER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime < $oldtime) and ($oldtime < $newtime)){
                    verb("Case 6: Trade is OLDER than the OldDraft || the OldDraft is OLDER than the NewDraft - Keep Old");
                  }
                }
              }
              verb("Finish de Revision, se ha escogido ${current_draft} para el trade ".$drafttime->dmy('/')." con fecha ". $formatter->parse_datetime($tradedb->{$league_id}->{drafts}->{$current_draft}->{last_picked})->dmy('/'));
              ($oldtime,$newtime,$drafttime)=undef;
            }
            if (exists($tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}})){
              $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round}).".".sprintf("%02d",$tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}});
            }else{
              $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round});
            }
          }else{
            $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round});
          }
          my $userpickownerid = get_ownerid($keypicks->{owner_id},$league_id);
          push @{$tradedb->{$league_id}->{$trade->{transaction_id}}->{$userpickownerid}}, $picktext;
          verb("Picks ${picktext}");
          if (defined($current_draft)){
            $tradedb->{$league_id}->{$trade->{transaction_id}}->{draftrounds} = $tradedb->{$league_id}->{drafts}->{$current_draft}->{draftrounds};
          }
          verb("Current Rounds: ". $tradedb->{$league_id}->{drafts}->{$current_draft}->{draftrounds})if (defined($current_draft));
        }
      }
    }
  }
  update_leagueTime($league_id);
  return;
}

sub update_leagueTime{#Inserts in the MySQL the CurrentTime after updating
  my $league_id = shift;
  my $query = qq/UPDATE Leagues SET LastUpdate = $dtnow WHERE LeagueID = $league_id/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  $sth->finish;
  verb("Updating time of league ${league_id}");
}

sub update_PossibleDeleted{#Inserts in the MySQL the Possible Delete Status
  my $league_id = shift;
  my $query = qq/UPDATE Leagues SET PossibleDeleted = TRUE WHERE LeagueID = $league_id/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  $sth->finish;
  verb("Updating Possible Deleted league ${league_id}");
}

sub insert_newtrade{ #Inserts one Trades into MySQL
  my $transactions_id = shift;
  my $league_id = shift;
  my $trans_time = shift;
  my $items1 = shift;
  my $items2 = shift;
  my $items3 = shift;
  my $owners1 = shift;
  my $owners2 = shift;
  my $owners3 = shift;
  my $draftrounds = shift;
  if ((!(defined($items1))) or (!(defined($items2)))){
    return;
  }
  my $countitems1 = () = $items1 =~ /\Q;/g;
  my $countitems2 = () = $items2 =~ /\Q;/g;

  return if (($countitems1 > $maxIteminTrade) or ($countitems2 > $maxIteminTrade));

  if ((!($items1 =~ m/.*,.*/)) and (!($items2 =~ m/.*,.*/))){
    my $dbst = $dbh->prepare(
      q{
        INSERT INTO PickTrades
          (TradeID,League,Time,Items1,Items2,Items3,Items1Owner,Items2Owner,Items3Owner,DraftRounds)
        VALUES
          (?,?,?,?,?,?,?,?,?,?)
      }, {},
    );
    verb("inserting ${transactions_id} in PICKS");
    $dbst->execute($transactions_id, $league_id, $trans_time, $items1, $items2, $items3, $owner1, $owner2, $owner3, $draftrounds)or die $dbst->errstr; # TODO MIRAR DE MEJORAR EL ERROR
    $dbst->finish;
  }else{
    my $dbst = $dbh->prepare(
      q{
        INSERT INTO Trades
          (TradeID,League,Time,Items1,Items2,Items3,Items1Owner,Items2Owner,Items3Owner,DraftRounds)
        VALUES
          (?,?,?,?,?,?,?,?,?,?)
      }, {},
    );
    verb("inserting ${transactions_id} in TRADES");
    $dbst->execute($transactions_id, $league_id, $trans_time, $items1, $items2, $items3, $owner1, $owner2, $owner3, $draftrounds)or die $dbst->errstr; # TODO MIRAR DE MEJORAR EL ERROR
    $dbst->finish;
  }
}

sub insert_newleague{ # Adds a new League to the list
  my $new_league = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO Leagues(LeagueID) VALUES (?)},{},);
  $sth->execute($new_league);
  $sth->finish;
  # verb("Inserting league ${new_league} into the DB");
}

sub insert_searchedUser{ # Adds a new League to the list
  my $new_user = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO SearchedUsers(UserID,ScrapeDate) VALUES (?,?)},{},);
  $sth->execute($new_user,$dtnow);
  $sth->finish;
  # verb("Inserting ${new_user}");
}

sub get_leagues { #Get All leagues from a User
  my $userID = shift;
  my $league_json_string = undef;
  my $league_url = "https://api.sleeper.app/v1/user/${userID}/leagues/${sport}/${season}";
  my $league_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $league_header = HTTP::Request->new(GET => $league_url);
  $league_header->header(content_type => "application/json",
                         accept => "application/json");
  my $league_request = HTTP::Request->new('GET', $league_url, $league_header);
  my $league_response = $league_ua->request($league_request);
  if ($league_response->is_success){
    $league_json_string = $league_response->content;
  }elsif ($league_response->is_error){
    print "CRITICAL: Error: $league_url\n";
    verb($league_response->error_as_HTML);
    next;
  }
  my $leaguejson = decode_json($league_json_string);
  foreach my $leagueitem ( @$leaguejson ) {
    next unless ($leagueitem->{settings}->{type} == 2); # Only DynastyLeagues
    next unless (ref($leagueitem->{roster_positions}) eq 'ARRAY' and grep { $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }); #Only Superflex Leagues
    next unless ( ($leagueitem->{settings}->{num_teams} eq "12") || ($leagueitem->{settings}->{num_teams} eq "14") ); # Only 12/14 Player Leagues
    next unless (scalar @{ $leagueitem->{roster_positions} } > 20); #min 20 players per team
    next unless ((grep { $_ eq "QB" or $_ eq "RB" or $_ eq "WR" or $_ eq "TE" or $_ eq "FLEX" or $_ eq "REC_FLEX" or $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }) >= 8); # Min 8 Starters
    push(@LeagueSearchList, $leagueitem->{league_id}); #Add them to the LeagueList
    verb("Adding league $leagueitem->{league_id} to arraysearch");
  }
  return;
}

sub get_leagueusers { #Gets all Users from a League
  my $leagueID = shift;
  my $league_json_string = undef;
  my $league_url = "https://api.sleeper.app/v1/league/${leagueID}/users";
  my $league_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $league_header = HTTP::Request->new(GET => $league_url);
  $league_header->header(content_type => "application/json",
                         accept => "application/json");
  my $league_request = HTTP::Request->new('GET', $league_url, $league_header);
  my $league_response = $league_ua->request($league_request);
  if ($league_response->is_success){
    $league_json_string = $league_response->content;
  }elsif ($league_response->is_error){
    print "CRITICAL: Error: $league_url\n";
    verb($league_response->error_as_HTML);
    return;
  }
  my $leaguejson = decode_json($league_json_string);
  foreach my $leagueuser ( @$leaguejson ) {
    my $usersearch = $leagueuser->{"user_id"};
    push(@UserSearchList, $leagueuser->{"user_id"}) unless(!(grep(/^$usersearch$/,@UserSearchList)));
  }
  return;
}

sub get_userid { #Get the UserID from a username
  my $username = shift;
  my $user_json_string = undef;
  my $user_url = "https://api.sleeper.app/v1/user/$username";
  my $user_ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $user_header = HTTP::Request->new(GET => $user_url);
  $user_header->header(content_type => "application/json",
                       accept => "application/json");
  my $user_request = HTTP::Request->new('GET', $user_url, $user_header);
  my $user_response = $user_ua->request($user_request);
  if ($user_response->is_success){
    $user_json_string = $user_response->content;
  }elsif ($user_response->is_error){
    print "CRITICAL: Error:$user_url\n";
    verb($user_response->error_as_HTML);
    return;
  }
  my $userjson = decode_json($user_json_string);
  return $userjson->{"user_id"};
}

sub export_data{
  csv (out => "${gitrepodir}/Leagues.csv", sep_char => ";", headers => [qw( leagueid name rosters qb rb wr te flex sflex bn total_players taxi_slots rec_bonus rec_rb rec_wr rec_te pass_td pass_int old_leagueid )], in => $dbh->selectall_arrayref ("SELECT LeagueID,name,total_rosters,roster_positions_QB,roster_positions_RB,roster_positions_WR,roster_positions_TE,roster_positions_FLEX,roster_positions_SUPER_FLEX,roster_positions_BN,total_players,taxi_slots,pass_td,rec_bonus,bonus_rec_te,bonus_rec_rb,bonus_rec_wr,pass_int,previous_league_id FROM Leagues"));
  csv (out => "${gitrepodir}/Trades.csv", sep_char => ";", headers => [qw( tradeid time leagueid items1 items2 owner1 owner2 )], in => $dbh->selectall_arrayref ("SELECT TradeID,Time,League,Items1,Items2,Items1Owner,Items2Owner FROM Trades"));
  csv (out => "${gitrepodir}/PickTrades.csv", sep_char => ";", headers => [qw( tradeid time leagueid items1 items2 owner1 owner2 rounds )], in => $dbh->selectall_arrayref ("SELECT TradeID,Time,League,Items1,Items2,Items1Owner,Items2Owner,DraftRounds FROM PickTrades"));
  printtofile("${gitrepodir}/Date.csv",DateTime->now()->mdy("/"));
  my $repo = Git::Repository->new( work_tree => $gitrepodir);
  $repo->run( add => '.' );
  $repo->run( commit => '-m', DateTime->now()->mdy("/")." Trades" );
  $repo->run ( 'push', '-u' => { origin => 'master' } );
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
      'h'     => \$o_help,            'help'            => \$o_help,
      'm:i'   => \$o_maxleagues,      'maxleagues:i'    => \$o_maxleagues,
      'r:i'   => \$o_refreshage,      'refreshage:i'    => \$o_refreshage,
      'l:s'   => \$o_newleagues,      'newleagues:s'    => \$o_newleagues,
      'U'     => \$o_expandusersearch,'expandsearch'    => \$o_expandusersearch,
      'w:i'   => \$o_currentweek,     'currentweek:i'   => \$o_currentweek,
      'd'     => \$o_updatedb,        'updateplayerdb'  => \$o_updatedb,
      'i'     => \$o_leagueinfo,      'leagueinfo'      => \$o_leagueinfo,
      'R'     => \$o_leaguerookies,   'rookieinfo'      => \$o_leaguerookies,
      'I'     => \$o_rosteridinfo,    'rosteridinfo'    => \$o_rosteridinfo,
      'e'     => \$o_export,          'export'          => \$o_export,
      'u'     => \$o_update,          'update'          => \$o_update,
      'v'     => \$o_verb,            'verbose'         => \$o_verb
  );
  if(defined($o_help)) {
    help();
    exit 0;
  }
  if ($o_leagueinfo and $o_leaguerookies){
    print "You must choose only one option -f or -i";
    help();
    exit 0;
  }
}

sub printtofile{
  my $filename = $_[0];
  my $text = $_[1];
  print "${text}" unless (!$o_verb);
  open(my $fh, '>', $filename);
  print $fh "${text}";
  close $fh;
}

sub verb {
    my $t=shift;
    print STDOUT $t,"\n" if defined($o_verb);
}

sub print_usage {
  print "Usage: $0  [-l <USERMANE>] [-m <INT>] [-r <DAYS>] [-w <WEEK>] [-u] [-U] [-i] [-R] [-e] [-v] [-h]\n";
}

sub help {
  print "\nSearch Sleeper Trades $0\n";
  print_usage();
  print <<EOT;
-h, --help
    Print this help message.
-l, --newleagues <S>
    Username to find new leagues that he and his teammates are in.
-m, --maxleagues <I>
    Max number of leagues to update (to throttle) (default 5).
-r, --refreshage <I>
    How Fresh has to be the data to refresh (default 5 Days).
-w, --currentweek <I>
    Week to update transactions.
-u, --update
    Mode to Update.
-U, --expandsearch
    Expand search to already added leagues.
-i, --leagueinfo
    Update the info of the Leagues in the MySQL.
-I, --rosteridinfo
    Update the RosterID reference information.
-R, --rookieinfo
    Update the info of the Rookie Drafts in the MySQL.
-e, --export
    Export CSV from tables and commit to git repository
-v, --verbose
    Verbose mode.
EOT
}
