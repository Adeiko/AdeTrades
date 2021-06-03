#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use LWP::UserAgent;
use HTTP::Request;
use JSON::XS 'decode_json';
use Scalar::Util qw(looks_like_number);
use List::MoreUtils qw(any uniq);
use Getopt::Long;
use DateTime;
use DateTime::Format::Epoch;
use Term::ProgressBar;
use Text::CSV_XS qw( csv );
use Git::Repository;
use Google::RestApi;
use Google::RestApi::SheetsApi4;
use Google::RestApi::Auth::OAuth2Client;
use YAML::Tiny;
use Data::Dumper;

my ($o_help,$o_verb,$o_updatetrades,$o_searchleagues,$o_leagueinfo,$o_expandusersearch,$o_updatedb,$o_rosteridinfo,$o_tradevalues,$o_tradevalueslm,$o_export,$o_currentweek,$o_debugverb,$o_updateadp);
my ($tradedb,$transtradelist,$transpicklist,$transignorelist,$translist,$leaguehashlist,$userhashlist,$players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds);
my (@LeagueList,@playerstemp,@LeagueSearchList,@UserSearchList,@LeagueNameList,@LeagueRosterIDList);
my %dlist;

# Default values
my $season = 2021;
my $o_refreshage = 5;
my $o_refreshagerosterids = 90;
my $o_maxleagues = 50;
my $maxIteminTrade = 5;
my $leaguecount = 0;
my $gitrepodir = "$ENV{HOME}/Repositories/AdeTrades";

check_options(); # Check for the arguments

# Database configuration
my $dbh = DBI->connect("DBI:mysql:database=Sleeper;mysql_read_default_file=$ENV{HOME}/.my.cnf;mysql_read_default_group=Sleeper",undef,undef) or die "Something went wrong ($DBI::errstr)";

# DateTime variables
my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
my $formatter = DateTime::Format::Epoch->new(epoch => $dt,unit => 'milliseconds');
my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(days => $o_refreshage)->epoch();
my $dtoldrosters = DateTime->now()->subtract(days => $o_refreshagerosterids)->epoch();

if ($o_searchleagues){ # To find new leagues
  $leaguehashlist = $dbh->selectall_hashref ("SELECT LeagueID FROM Leagues","LeagueID");
  $userhashlist = $dbh->selectall_hashref ("SELECT UserID FROM SearchedUsers","UserID");
  get_leagues(get_userid($o_searchleagues));
  if (scalar(@LeagueSearchList)>0){
    my $currentLeag = 0;
    my $nextLeagupdate = 0;
    @LeagueSearchList = uniq(@LeagueSearchList);
    my $progressLeag = Term::ProgressBar->new({name  => 'Searching Users', count => scalar(@LeagueSearchList), ETA   => 'linear', remove => 1});
    $progressLeag->max_update_rate(1);
    $progressLeag->message("Searching Users for ".scalar(@LeagueSearchList)." Leagues");
    foreach my $leaguesearch ( @LeagueSearchList ) { # For each league, get all users in those leagues
      $currentLeag++;
      $nextLeagupdate = $progressLeag->update($currentLeag) if $currentLeag > $nextLeagupdate;
      if (!(defined($o_expandusersearch))){
        next if (exists($leaguehashlist->{$leaguesearch})); # To skip recheck leagues already in the DB (but it could expand the search).
      }
      get_leagueusers($leaguesearch);
    }
    $progressLeag->update(scalar(@LeagueSearchList)) if scalar(@LeagueSearchList) >= $nextLeagupdate;
  }
  if (scalar(@UserSearchList)>0){
    my $currentUser = 0;
    my $nextUserupdate = 0;
    @UserSearchList = uniq(@UserSearchList);
    my $progressUser = Term::ProgressBar->new({name  => 'Searching Leagues', count => scalar(@UserSearchList), ETA   => 'linear', remove => 1});
    $progressUser->max_update_rate(1);
    $progressUser->message("Searching Leagues for ".scalar(@UserSearchList)." Users");
    foreach my $useritem (@UserSearchList){ # For each user in one of those leagues gets their leagues
      next if (exists($userhashlist->{$useritem}));
      get_leagues($useritem);
      $userhashlist->{$useritem} = $useritem; # Add to the Hash so if duplicated in the array do not redo.
      insert_searchedUser($useritem); # Adds them to the "ignore" list.
      $currentUser++;
      $nextUserupdate = $progressUser->update($currentUser) if $currentUser > $nextUserupdate;
    }
    $progressUser->update(scalar(@UserSearchList)) if scalar(@UserSearchList) >= $nextUserupdate;
  }
  $leaguecount = 0;
  @LeagueSearchList = uniq(@LeagueSearchList);
  foreach my $newleague ( @LeagueSearchList ) {
    next if (exists($leaguehashlist->{$newleague})); # Only add leagues not already in the DB.
    $leaguehashlist->{$newleague} = $newleague; # Add to the hash so no if duplicated do not repeat.
    verb("Found new league: $newleague");
    insert_newleague($newleague);
    $leaguecount++;
  }
  print "$leaguecount new leagues (from ". scalar(@LeagueSearchList)." found) added from the query of user ${o_searchleagues}\n";
  $o_maxleagues = $leaguecount;
}

if ($o_leagueinfo or ($leaguecount > 0)){
  get_leaguelistUpdateInfo($o_maxleagues);
  if (scalar(@LeagueNameList) > 0){
    my $currentInfo = 0;
    my $nextInfoupdate = 0;
    my $progressInfo = Term::ProgressBar->new({name  => 'Finding League Info', count => scalar(@LeagueNameList), ETA   => 'linear', remove => 1});
    $progressInfo->max_update_rate(1);
    $progressInfo->message("Searching for Info  for ".scalar(@LeagueNameList)." Leagues (still ".get_CountleaguelistUpdateInfo()." pending)\n");
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

if ($o_rosteridinfo or ($leaguecount > 0)){
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

if ($o_updatetrades or ($leaguecount > 0)){
  $transpicklist = $dbh->selectall_hashref ("SELECT TradeID FROM Trades","TradeID");
  $transtradelist = $dbh->selectall_hashref ("SELECT TradeID FROM PickTrades","TradeID");
  $transignorelist = $dbh->selectall_hashref ("SELECT TradeID FROM RevertedTrades","TradeID");
  $translist = {%$transpicklist, %$transtradelist, %$transignorelist};
  get_leaguelist($o_maxleagues);
  if (scalar(@LeagueList) > 0){
    my $currentLeague = 0;
    my $next_update = 0;
    my $progress = Term::ProgressBar->new({name  => 'Searching Trades', count => scalar(@LeagueList), ETA   => 'linear', remove => 1});
    $progress->max_update_rate(1);
    $progress->message("Searching for Trades for ".scalar(@LeagueList)." Leagues (still ".get_leaguePendingUpdate()." pending)\n");
    foreach my $leagueN (@LeagueList){
      $currentLeague++;
      get_currentstate() if (!(defined($o_currentweek)));
      get_trades($leagueN,$o_currentweek);
      $next_update = $progress->update($currentLeague) if $currentLeague > $next_update;
    }
    $progress->update(scalar(@LeagueList)) if scalar(@LeagueList) >= $next_update;
    insert_tradeHash();
  }else{
    print ("No leagues pending to update\n");
  }
}
export_sleeperplayers() if ($o_updatedb); # Update the MySQL PlayerDB with Sleeper Data.

updateTradeValues()if ($o_tradevalues or $o_tradevalueslm);

update_ADP if ($o_updateadp);

if ($o_export){
  clean_data();  # Clean the Database of Reversed/duplicate trades
  export_data(); # Export Data to CSV and commit
}

exit;

sub get_leagueinfo{ # Get All leagues from a User
  my $league_id = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/league/${league_id}",$league_id);
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
  my $sth = $dbh->prepare(qq/UPDATE Leagues SET name = $league_name_q, total_rosters = $league_total_rosters, taxi_slots = $league_taxi_slots, rec_bonus = $league_rec, bonus_rec_wr = $league_bonus_rec_wr, bonus_rec_te = $league_bonus_rec_te, bonus_rec_rb = $league_bonus_rec_rb, pass_td = $league_pass_td, pass_int = $league_pass_int, roster_positions_QB = $Positions_QB, roster_positions_RB = $Positions_RB, roster_positions_WR = $Positions_WR, roster_positions_TE = $Positions_TE, roster_positions_FLEX = $Positions_FLEX, roster_positions_SUPER_FLEX = $Positions_SUPER_FLEX, roster_positions_BN = $Positions_BN, total_players = $total_players, RookieRounds = $league_draftrounds, RookieTimeUpdate = $dtnow, RookieStatus = "$league_status", RookieDraft = $league_draftid, trade_deadline = $league_tradedl, previous_league_id = $league_previousleague WHERE LeagueID = $league_id;/);
  $sth->execute();
  $sth->finish;
  dverb("League ${league_id}\nleague_name: ${league_name}\nleague_total_rosters: ${league_total_rosters}\nleague_taxi_slots: ${league_taxi_slots}\nleague_rec: ${league_rec}\nleague_bonus_rec_wr: ${league_bonus_rec_wr}\nleague_bonus_rec_te: ${league_bonus_rec_te}\nleague_bonus_rec_rb: ${league_bonus_rec_rb}\nleague_pass_td: ${league_pass_td}\nleague_pass_int: ${league_pass_int}\nPositions_QB: ${Positions_QB}\nPositions_RB: ${Positions_RB}\nPositions_WR: ${Positions_WR}\nPositions_TE: ${Positions_TE}\nPositions_FLEX: ${Positions_FLEX}\nPositions_SUPER_FLEX: ${Positions_SUPER_FLEX}\nPositions_BN: ${Positions_BN}\ntotal_players: ${total_players}");
}

sub get_leaguedrafts{ # Gets draft slots from the league of that year
  my $league_id = shift;
  my $draftsjson = get_json("https://api.sleeper.app/v1/league/$league_id/drafts");
  foreach my $draft( @$draftsjson ) {
    next unless ($draft->{season} eq $season);
    my $draftjson = get_json("https://api.sleeper.app/v1/draft/$draft->{draft_id}");
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

sub get_leaguerosterID{
  my $league_id = shift;
  verb("Getting RosterID from league: ${league_id}");
  my $rosteridjson = get_json("https://api.sleeper.app/v1/league/$league_id/rosters",$league_id);
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO RosterID_Reference(LeagueID) VALUES (?)},{},);
  $sth->execute($league_id);
  $sth->finish;
  foreach my $roster( @$rosteridjson ) {
    my $ownerid;
    if (defined($roster->{owner_id})){ $ownerid = $roster->{owner_id} }else{ $ownerid = "0" };
    if (!(defined($roster->{owner_id}))){next;};
    my $sts = $dbh->prepare(qq/UPDATE RosterID_Reference SET RosterID$roster->{roster_id} = $ownerid WHERE LeagueID = $league_id;/);
    $sts->execute();
    $sts->finish;
  }
  my $stq = $dbh->prepare(qq/UPDATE RosterID_Reference SET LastUpdate = $dtnow WHERE LeagueID = $league_id/);
  $stq->execute();
  $stq->finish;
}

sub get_player{ # Gets the Player String from Sleeper_ID
  my $splayer_id = shift;
  return unless (looks_like_number($splayer_id));
  my $sth = $dbh->prepare(qq/SELECT first_name,last_name,fantasy_positions,team FROM Players WHERE player_id=$splayer_id/);
  $sth->execute();
  my ($qfname,$qlname,$qpos,$qteam) = $sth->fetchrow;
  $sth->finish;
  if (!(defined($qfname))){
    print "Error: the player ${splayer_id} has not been found";
    return;
  }
  $qteam = '' if (!(defined($qteam)));
  return "$qfname $qlname,$qpos,$qteam";
}

sub get_ownerid{ # Gets the owner of the RosterID
  my $sroster_id = shift;
  my $sleague_id = shift;
  return unless (looks_like_number($sroster_id));
  return unless (looks_like_number($sleague_id));
  return $sroster_id if ($sroster_id > 14);
  my $sth = $dbh->prepare(qq/SELECT RosterID${sroster_id} FROM RosterID_Reference WHERE LeagueID=${sleague_id}/);
  $sth->execute();
  my $qownerid = $sth->fetchrow;
  $sth->finish;
  return $sroster_id if (!(defined($qownerid)));
  return $qownerid;
}

sub get_trades { # Get All trades from a League
  my $league_id = shift;
  my $WeekID = shift;
  my $current_draft = undef;
  verb("Getting trades of $league_id");
  my $tradesjson = get_json("https://api.sleeper.app/v1/league/${league_id}/transactions/${WeekID}",$league_id);
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
            get_leaguedrafts($league_id) if (!exists($tradedb->{$league_id}->{drafts}));
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
                  dverb("TradeDate: ".${drafttime}->dmy('/')." NewTime: ".${newtime}->dmy('/')." and OldTime: ".${oldtime}->dmy('/'));
                  if (($drafttime > $oldtime) and ($oldtime > $newtime)){
                    dverb("Case 1: Trade is NEWER than the OldDraft || the OldDraft is NEWER than the NewDraft - Keep Old");
                  }elsif(($drafttime < $oldtime) and ($oldtime > $newtime) and ($drafttime > $newtime)){
                    dverb("Case 2: Trade is OLDER than the OldDraft || the OldDraft is NEWER than the NewDraft || The Trade is NEWER than the NewDraft - Keep Old");
                  }elsif(($drafttime < $oldtime) and ($oldtime > $newtime) and ($drafttime < $newtime)){
                    dverb("Case 3: Trade is OLDER than the OldDraft || the OldDraft is NEWER than the NewDraft || The Trade is OLDER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime > $oldtime) and ($oldtime < $newtime) and ($drafttime > $newtime)){
                    dverb("Case 4: Trade is NEWER than the OldDraft || the OldDraft is OLDER than the NewDraft || The Trade is NEWER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime > $oldtime) and ($oldtime < $newtime) and ($drafttime < $newtime)){
                    dverb("Case 5: Trade is NEWER than the OldDraft || the OldDraft is OLDER than the NewDraft || The Trade is OLDER than the NewDraft - Go New");
                    $current_draft = $leaguekeys;
                  }elsif(($drafttime < $oldtime) and ($oldtime < $newtime)){
                    dverb("Case 6: Trade is OLDER than the OldDraft || the OldDraft is OLDER than the NewDraft - Keep Old");
                  }
                }
              }
              dverb("Finish de Revision, se ha escogido ${current_draft} para el trade ".$drafttime->dmy('/')." con fecha ". $formatter->parse_datetime($tradedb->{$league_id}->{drafts}->{$current_draft}->{last_picked})->dmy('/'));
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
          dverb("Picks ${picktext}");
          $tradedb->{$league_id}->{$trade->{transaction_id}}->{draftrounds} = $tradedb->{$league_id}->{drafts}->{$current_draft}->{draftrounds} if (defined($current_draft));
          dverb("Current Rounds: ". $tradedb->{$league_id}->{drafts}->{$current_draft}->{draftrounds})if (defined($current_draft));
        }
      }
    }
  }
  update_leagueTime($league_id);
}

sub get_leagues { # Get All leagues from a User
  my $userID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/user/${userID}/leagues/nfl/${season}");
  foreach my $leagueitem ( @$leaguejson ) {
    next if (grep(/\bfree\b/i,$leagueitem->{name})); # Skip league if has Free (case insensitive) in the name
    next if (grep(/\bmock\b/i,$leagueitem->{name}));  # Skip league if has mock (case insensitive) in the name
    next unless ($leagueitem->{settings}->{type} == 2); # Only DynastyLeagues
    next unless (ref($leagueitem->{roster_positions}) eq 'ARRAY' and grep { $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }); # Only Superflex Leagues
    next unless ( ($leagueitem->{settings}->{num_teams} eq "12") || ($leagueitem->{settings}->{num_teams} eq "14") ); # Only 12/14 Player Leagues
    next unless (scalar @{ $leagueitem->{roster_positions} } > 20); # Min 20 players per team
    next unless ((grep { $_ eq "QB" or $_ eq "RB" or $_ eq "WR" or $_ eq "TE" or $_ eq "FLEX" or $_ eq "REC_FLEX" or $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }) >= 8); # Min 8 Starters
    push(@LeagueSearchList, $leagueitem->{league_id}) unless(grep(/^$leagueitem->{league_id}$/,@LeagueSearchList)); # Add them to the LeagueList unless already exists
    verb("Adding league $leagueitem->{league_id} to arraysearch");
  }
}

sub get_leaguelist{ # Get the LeagueList from the MySQL that hasn't updated in X time
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT LeagueID FROM Leagues WHERE PossibleDeleted = FALSE AND LastUpdate < $dtold OR LastUpdate IS NULL LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguelistUpdateInfo{ # Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT LeagueID FROM Leagues WHERE PossibleDeleted = FALSE AND name IS NULL LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueNameList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_CountleaguelistUpdateInfo{ # Get the LeagueList missing information from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(LeagueID) FROM Leagues WHERE PossibleDeleted = FALSE AND name IS NULL/);
  $sth->execute();
  my $pendingleagues = $sth->fetchrow;
  $sth->finish;
  return $pendingleagues;
}

sub get_leaguelistUpdateRosterID{ # Get the LeagueList without rosterID information from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT DISTINCT l.LeagueID FROM Leagues l LEFT JOIN RosterID_Reference r ON r.LeagueID = l.LeagueID WHERE r.LeagueID IS NULL AND (r.LastUpdate < $dtoldrosters OR r.LastUpdate IS NULL) LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueRosterIDList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguePendingUpdate{ # Get Number of leagues missing update
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(LeagueID) FROM Leagues WHERE PossibleDeleted = FALSE AND LastUpdate < $dtold OR LastUpdate IS NULL/);
  $sth->execute();
  my $pendingleagues = $sth->fetchrow;
  $sth->finish;
  return $pendingleagues;
}

sub get_leagueusers { # Gets all Users from a League
  my $league_id = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/league/${league_id}/users",$league_id);
  foreach my $leagueuser ( @$leaguejson ) {
    push(@UserSearchList, $leagueuser->{user_id}) unless(grep(/^$leagueuser->{user_id}$/,@UserSearchList));
  }
}

sub get_userid { # Get the UserID from a username
  my $username = shift;
  my $userjson = get_json("https://api.sleeper.app/v1/user/$username");
  return $userjson->{user_id};
}

sub get_currentstate{ #Get Current Week from SleeperAPI
  my $status_json = get_json("https://api.sleeper.app/v1/state/nfl");
  $o_currentweek = $status_json->{display_week};
}

sub insert_newleague{ # Adds a new League to the list
  my $new_league = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO Leagues(LeagueID) VALUES (?)},{},);
  $sth->execute($new_league);
  $sth->finish;
}

sub insert_searchedUser{ # Adds a new user to the searched list
  my $new_user = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO SearchedUsers(UserID,ScrapeDate) VALUES (?,?)},{},);
  $sth->execute($new_user,$dtnow);
  $sth->finish;
}

sub insert_newtrade{ # Inserts one Trades into MySQL
  my ($transactions_id,$league_id,$trans_time,$items1,$items2,$items3,$owners1,$owners2,$owners3,$draftrounds) = (@_);
  my $TradeDatabase = "Trades";
  return if ((!(defined($items1))) or (!(defined($items2))));
  my $countitems1 = () = $items1 =~ /\Q;/g;
  my $countitems2 = () = $items2 =~ /\Q;/g;
  return if (($countitems1 > $maxIteminTrade) or ($countitems2 > $maxIteminTrade));
  $TradeDatabase = "PickTrades" if ((!($items1 =~ m/.*,.*/)) and (!($items2 =~ m/.*,.*/)));
  my $dbst = $dbh->prepare(qq{INSERT IGNORE INTO $TradeDatabase(TradeID,League,Time,Items1,Items2,Items3,Items1Owner,Items2Owner,Items3Owner,DraftRounds) VALUES (?,?,?,?,?,?,?,?,?,?)},{},);
  dverb("inserting ${transactions_id} in $TradeDatabase");
  $dbst->execute($transactions_id, $league_id, $trans_time, $items1, $items2, $items3, $owner1, $owner2, $owner3, $draftrounds)or die $dbst->errstr;
  $dbst->finish;
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
        dverb("League: ${leaguehash} Transaction ${transhash} Time $$tradedb{$leaguehash}->{$transhash}->{date}");
        dverb ("Players1: ${players1}") if defined($players1);
        dverb ("Owner1: ${owner1}") if defined($owner1);
        dverb ("Players2: ${players2}") if defined($players2);
        dverb ("Owner2: ${owner2}") if defined($owner2);
        dverb ("Players3: ${players3}") if defined($players3);
        dverb ("Owner3: ${owner3}") if defined($owner3);
        dverb ("DraftRounds: ${draftrounds}") if defined($draftrounds);
        insert_newtrade($transhash,$leaguehash,$tradedb->{$leaguehash}->{$transhash}->{date},$players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds);
        ($players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds) = undef;
      }
    }
  }
}

sub update_leagueTime{ # Inserts in the MySQL the CurrentTime after updating
  my $league_id = shift;
  my $sth = $dbh->prepare(qq/UPDATE Leagues SET LastUpdate = $dtnow WHERE LeagueID = $league_id/);
  $sth->execute();
  $sth->finish;
  verb("Updating time of league ${league_id}");
}

sub update_PossibleDeleted{ # Inserts in the MySQL the Possible Delete Status
  my $league_id = shift;
  my $sth = $dbh->prepare(qq/UPDATE Leagues SET PossibleDeleted = TRUE WHERE LeagueID = $league_id/);
  $sth->execute();
  $sth->finish;
  verb("Updating Possible Deleted league ${league_id}");
}

sub update_ADP{ #Read the ADP Google Sheet and import the new ADP in the TradeStats Table
  my $yaml = YAML::Tiny->read('gapi.yaml');
  my $oauth2 = Google::RestApi::Auth::OAuth2Client->new(
    client_id => $yaml->[0]{auth}{client_id},
    client_secret => $yaml->[0]{auth}{client_secret},
    token_file => 'gapi_stored_google_access.session'
  );
  my $restapi = Google::RestApi->new(auth =>$oauth2);
  my $sheets = Google::RestApi::SheetsApi4->new(api => $restapi);
  my $spreadsheet = $sheets->open_spreadsheet(id => '1GEWqLbXcA4PXFAPfCBiG5NWBSXQ5i1apvLpo_ca6xAo');
  my $worksheet = $spreadsheet->open_worksheet(name => 'ADP_Players');
  my $ADPrange = $worksheet->range("ADP_Export");
  my $ADPvalues = $ADPrange->values();
  foreach my $PlayerADP (@$ADPvalues){
    Update_TradeStatsADP(@$PlayerADP[0],@$PlayerADP[1]);
    verb ("PlayerID: ".@$PlayerADP[0]);
    verb ("ADP: ".@$PlayerADP[1]) if (defined(@$PlayerADP[1]));
  }
}

sub Update_TradeStatsADP{ # Insert the ADP in the TradeStats file
  my $splayerid = shift;
  my $sadp = shift;
  if (!(defined($splayerid))){return;};
  if (defined($sadp)){
    my $sts = $dbh->prepare(qq/UPDATE TradeStats SET ADP = $sadp WHERE PlayerID = $splayerid;/);
    $sts->execute();
    $sts->finish;
  }else{
    my $sts = $dbh->prepare(qq/UPDATE TradeStats SET ADP = NULL WHERE PlayerID = $splayerid;/);
    $sts->execute();
    $sts->finish;
  }
}

sub updateTradeValues{ # Generate the trade count for each player in the 12 diferent months
  my $query = qq/SELECT PlayerName FROM TradeStats Where LastCount < $dtold OR LastCount IS NULL/;
  $query = qq/SELECT PlayerName FROM TradeStats/ if ($o_tradevalueslm);
  my $sth = $dbh->prepare($query);
  $sth->execute();
  if ($sth->rows>0){
    my $currentPlayerTS = 0;
    my $nextPlayerTSupdate = 0;
    my $progressPlayerTS = Term::ProgressBar->new({name  => 'Finding Player trade count data', count => $sth->rows, ETA   => 'linear', remove => 1});
    $progressPlayerTS->max_update_rate(1);
    $progressPlayerTS->message("Searching for Player trade count data for ".$sth->rows." Players\n");
    while(my $row = $sth->fetchrow_hashref) {
      update_count($row->{PlayerName},"LastM",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->now()->subtract(months => 1)),$formatter->format_datetime(DateTime->now)));
      if (!($o_tradevalueslm)){
        update_count($row->{PlayerName},"s$season",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 1)),$formatter->format_datetime(DateTime->new(year => $season+1, month => 1))));
        update_count($row->{PlayerName},"s${season}01",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 1)),$formatter->format_datetime(DateTime->new(year => $season, month => 2)))) unless (DateTime->now()->month < 1);
        update_count($row->{PlayerName},"s${season}02",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 2)),$formatter->format_datetime(DateTime->new(year => $season, month => 3)))) unless (DateTime->now()->month < 2);
        update_count($row->{PlayerName},"s${season}03",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 3)),$formatter->format_datetime(DateTime->new(year => $season, month => 4)))) unless (DateTime->now()->month < 3);
        update_count($row->{PlayerName},"s${season}04",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 4)),$formatter->format_datetime(DateTime->new(year => $season, month => 5)))) unless (DateTime->now()->month < 4);
        update_count($row->{PlayerName},"s${season}05",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 5)),$formatter->format_datetime(DateTime->new(year => $season, month => 6)))) unless (DateTime->now()->month < 5);
        update_count($row->{PlayerName},"s${season}06",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 6)),$formatter->format_datetime(DateTime->new(year => $season, month => 7)))) unless (DateTime->now()->month < 6);
        update_count($row->{PlayerName},"s${season}07",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 7)),$formatter->format_datetime(DateTime->new(year => $season, month => 8)))) unless (DateTime->now()->month < 7);
        update_count($row->{PlayerName},"s${season}08",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 8)),$formatter->format_datetime(DateTime->new(year => $season, month => 9)))) unless (DateTime->now()->month < 8);
        update_count($row->{PlayerName},"s${season}09",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 9)),$formatter->format_datetime(DateTime->new(year => $season, month => 10)))) unless (DateTime->now()->month <9 );
        update_count($row->{PlayerName},"s${season}10",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 10)),$formatter->format_datetime(DateTime->new(year => $season, month => 11)))) unless (DateTime->now()->month <10 );
        update_count($row->{PlayerName},"s${season}11",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 11)),$formatter->format_datetime(DateTime->new(year => $season, month => 12)))) unless (DateTime->now()->month < 11);
        update_count($row->{PlayerName},"s${season}12",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 12)),$formatter->format_datetime(DateTime->new(year => $season+1, month => 1)))) unless (DateTime->now()->month <12 );
        update_count($row->{PlayerName},"LastCount",$dtnow);
      }
      $currentPlayerTS++;
      $nextPlayerTSupdate = $progressPlayerTS->update($currentPlayerTS) if $currentPlayerTS > $nextPlayerTSupdate;
    }
    $progressPlayerTS->update($sth->rows) if $sth->rows >= $nextPlayerTSupdate;
  }
  $sth->finish;
}

sub get_count{ #Count number of trades for X players
  my $splayer = shift;
  my $mintime = shift;
  my $maxtime = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(t.TradeID) FROM Sleeper.Trades t WHERE ((t.Items1 like "%$splayer%") or (t.Items2 like "%$splayer%")) AND Time > ${mintime} AND Time < ${maxtime}/);
  $sth->execute();
  my $splayercount = $sth->fetchrow;
  $sth->finish;
  return $splayercount;
}

sub update_count{ #Insert in the Tradestats a value in X column
  my $splayer = shift;
  my $scolumn = shift;
  my $svalue = shift;
  my $splayerq = $dbh->quote($splayer);
  my $sth = $dbh->prepare(qq/UPDATE TradeStats SET ${scolumn} = ${svalue} WHERE PlayerName = ${splayerq}/);
  $sth->execute();
  $sth->finish;
}

sub clean_data{ #Cleaning trade Tables of wrong data
  verb("Adding Empty Trades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM Trades WHERE Items1 = "" OR Items2 = ""');
  verb("Adding Empty Picktrades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades WHERE Items1 = "" OR Items2 = ""');
  verb("Adding Picktrades with empty rounds to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades WHERE DraftRounds = 0');
  verb("Adding Duplicate Trades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM Trades GROUP BY TradeID HAVING COUNT(*) > 1');
  verb("Adding Duplicate PickTrades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades GROUP BY TradeID HAVING COUNT(*) > 1');
  verb("Adding trades reversed to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT t.TradeID FROM Sleeper.Trades t JOIN (SELECT Items1, Items2, League, count(*) as NumDuplicates FROM Trades GROUP BY Items1, Items2, League HAVING NumDuplicates > 1 ) tsum ON t.Items1 = tsum.Items1 AND t.Items2 = tsum.Items2 AND t.League = tsum.League');
  verb("Adding Picktrades reversed to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT t.TradeID FROM Sleeper.PickTrades t JOIN (SELECT Items1, Items2, League, count(*) as NumDuplicates FROM Trades GROUP BY Items1, Items2, League HAVING NumDuplicates > 1 ) tsum ON t.Items1 = tsum.Items1 AND t.Items2 = tsum.Items2 AND t.League = tsum.League');
  verb("Cleaning Trades");
  $dbh->do('DELETE FROM Trades WHERE TradeID IN (SELECT r.TradeID FROM RevertedTrades r WHERE r.TradeID IS NOT NULL)');
  verb("Cleaning Picktrades");
  $dbh->do('DELETE FROM PickTrades WHERE TradeID IN (SELECT r.TradeID FROM RevertedTrades r WHERE r.TradeID IS NOT NULL)');
  verb("Cleaning Ignored Leagues");
  $dbh->do('DELETE FROM Leagues WHERE LeagueID IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
  verb("Cleaning Trades from IngoredLeagues");
  $dbh->do('DELETE FROM Trades WHERE League IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
  verb("Cleaning PickTrades from Ignored Leagues");
  $dbh->do('DELETE FROM PickTrades WHERE League IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
}

sub export_data{ # Generate CSV and push them to the Repository
  my $repo = Git::Repository->new( work_tree => $gitrepodir);
  $repo->run( 'pull' );
  csv (out => "${gitrepodir}/Leagues.csv", sep_char => ";", headers => [qw( League_ID Name Rosters QB RB WR TE Flex SFlex BN Total_Players Start_Players Taxi_Slots Rec_Bonus Rec_RB Rec_WR Rec_TE Pass_TD Pass_Int Old_League_ID )], in => $dbh->selectall_arrayref ("SELECT LeagueID,name,total_rosters,roster_positions_QB,roster_positions_RB,roster_positions_WR,roster_positions_TE,roster_positions_FLEX,roster_positions_SUPER_FLEX,roster_positions_BN,total_players,total_players - roster_positions_BN AS Start_Players,taxi_slots,pass_td,rec_bonus,bonus_rec_te,bonus_rec_rb,bonus_rec_wr,pass_int,previous_league_id FROM Leagues"));
  csv (out => "${gitrepodir}/Trades.csv", sep_char => ";", headers => [qw( Trade_ID Time Day Items1 Items2 All_Items Items1_Owner Items2_Owner League_ID Total_Rosters Total_Players Start_Players Rec_Bonus Rec_Bonus_TE Pass_TD Old_League_ID )], in => $dbh->selectall_arrayref ("SELECT t.TradeID, t.Time,(t.Time/86400000)+25569 AS 'Day', t.Items1, t.Items2,CONCAT(t.Items1,'; ',t.Items2) AS AllItems, t.Items1Owner, t.Items2Owner, t.League, l.total_rosters, l.total_players, l.total_players - roster_positions_BN AS Start_Players, l.rec_bonus, l.bonus_rec_te, l.pass_td, l.previous_league_id FROM Trades t INNER JOIN Leagues l ON t.League = l.LeagueID ORDER BY t.Time DESC"));
  csv (out => "${gitrepodir}/PickTrades.csv", sep_char => ";", headers => [qw( Trade_ID Time Day Items1 Items2 All_Items Items1_Owner Items2_Owner League_ID Draft_Rounds Total_Rosters Total_Players Start_Players Rec_Bonus Rec_Bonus_TE Pass_TD )], in => $dbh->selectall_arrayref ("SELECT p.TradeID,p.Time,(p.time/86400000)+25569 AS 'Day',p.Items1,p.Items2,CONCAT(p.Items1,'; ',p.Items2) AS AllItems,p.Items1Owner,p.Items2Owner,p.League,p.DraftRounds,l.total_rosters,l.total_players,l.total_players - roster_positions_BN AS Start_Players,l.rec_bonus,l.bonus_rec_te,l.pass_td FROM PickTrades p INNER JOIN Leagues l ON p.League = l.LeagueID ORDER BY p.Time DESC"));
  csv (out => "${gitrepodir}/TradeCount.csv", sep_char => ";", headers => [qw( Sleeper_ID ADP Player_Name Last_Month Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec All_Year )], in => $dbh->selectall_arrayref ("SELECT t.PlayerID,t.ADP,t.PlayerName,t.LastM,t.s${season}01,t.s${season}02,t.s${season}03,t.s${season}04,t.s${season}05,t.s${season}06,t.s${season}07,t.s${season}08,t.s${season}09,t.s${season}10,t.s${season}11,t.s${season}12,t.s${season} FROM TradeStats t ORDER BY -ADP DESC"));
  my $repostatus = $repo->run( 'status' );
  if ($repostatus =~ "nothing to commit"){
    print "No new Trades exported.\n";
  }else{
    printtofile("${gitrepodir}/Date.csv",DateTime->now()->mdy("/"));
    $repo->run( add => '.' );
    $repo->run( commit => '-m', DateTime->now()->mdy("/")." Trades" );
    my $pushstatus = $repo->command ( 'push', '-u' => { origin => 'master' } );
    print "Pushed new trades to he repository.\n"
  }
}

sub export_sleeperplayers { # Get the Sleeper Player Ids in the MySQLDB
  if(!(prompt_yn("Do you want to continue"))){
    print "Ok, exiting the player database update.\n";
    exit;
  }
  my $playersjson = get_json("https://api.sleeper.app/v1/players/nfl");
  my $sth = $dbh->prepare(qq/TRUNCATE TABLE Players;/);
  $sth->execute();
  $sth->finish;
  verb("Truncated table PlayersTest");
  my $progressPlayers = Term::ProgressBar->new({name  => 'Searching Users', count => scalar(keys(%$playersjson)), ETA   => 'linear', remove => 1});
  my $currentPlayer = 0;
  my $nextPlayerupdate = 0;
  $progressPlayers->max_update_rate(1);
  $progressPlayers->message("Adding ".scalar(keys(%$playersjson))." players to the Database");
  foreach my $playerid (keys %$playersjson) {
    $currentPlayer++;
    $nextPlayerupdate = $progressPlayers->update($currentPlayer) if $currentPlayer > $nextPlayerupdate;
    my $dbst = $dbh->prepare(
      q{
        INSERT IGNORE INTO Players
          (player_id,first_name,last_name,position,team,weight,status,sport,fantasy_positions,college,practice_description,rotowire_id,active,number,height,injury_status,injury_body_part,injury_notes,practice_participation,high_school,sportradar_id,yahoo_id,years_exp,fantasy_data_id,hashtag,search_last_name,birth_city,espn_id,birth_date,search_first_name,birth_state,gsis_id,news_updated,birth_country,search_full_name,depth_chart_position,rotoworld_id,depth_chart_order,injury_start_date,stats_id,search_rank,pandascore_id,metadata,full_name,age)
        VALUES
          (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }, {},
    );
    $dbst->execute($playersjson->{$playerid}->{player_id},$playersjson->{$playerid}->{first_name},$playersjson->{$playerid}->{last_name},$playersjson->{$playerid}->{position},$playersjson->{$playerid}->{team},$playersjson->{$playerid}->{weight},$playersjson->{$playerid}->{status},$playersjson->{$playerid}->{sport},$playersjson->{$playerid}->{fantasy_positions}[0],$playersjson->{$playerid}->{college},$playersjson->{$playerid}->{practice_description},$playersjson->{$playerid}->{rotowire_id},$playersjson->{$playerid}->{active},$playersjson->{$playerid}->{number},$playersjson->{$playerid}->{height},$playersjson->{$playerid}->{injury_status},$playersjson->{$playerid}->{injury_body_part},$playersjson->{$playerid}->{injury_notes},$playersjson->{$playerid}->{practice_participation},$playersjson->{$playerid}->{high_school},$playersjson->{$playerid}->{sportradar_id},$playersjson->{$playerid}->{yahoo_id},$playersjson->{$playerid}->{years_exp},$playersjson->{$playerid}->{fantasy_data_id},$playersjson->{$playerid}->{hashtag},$playersjson->{$playerid}->{search_last_name},$playersjson->{$playerid}->{birth_city},$playersjson->{$playerid}->{espn_id},$playersjson->{$playerid}->{birth_date},$playersjson->{$playerid}->{search_first_name},$playersjson->{$playerid}->{birth_state},$playersjson->{$playerid}->{gsis_id},$playersjson->{$playerid}->{news_updated},$playersjson->{$playerid}->{birth_country},$playersjson->{$playerid}->{search_full_name},$playersjson->{$playerid}->{depth_chart_position},$playersjson->{$playerid}->{rotoworld_id},$playersjson->{$playerid}->{depth_chart_order},$playersjson->{$playerid}->{injury_start_date},$playersjson->{$playerid}->{stats_id},$playersjson->{$playerid}->{search_rank},$playersjson->{$playerid}->{pandascore_id},$playersjson->{$playerid}->{metadata},$playersjson->{$playerid}->{full_name},$playersjson->{$playerid}->{age})or die $dbst->errstr;
    $dbst->finish;
  }
  $progressPlayers->update(scalar(keys(%$playersjson))) if scalar(keys(%$playersjson)) >= $nextPlayerupdate;
}

sub get_json{ # General Function to get decoded JSON from URL
  my $url = shift;
  my $possibledeleted = shift;
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
    update_PossibleDeleted($possibledeleted) if ($possibledeleted);
    verb($response->error_as_HTML);
    return("");
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

sub prompt { # To ask for input to the user
  my ($query) = @_; # Take a prompt string as argument
  local $| = 1; # Activate autoflush to immediately show the prompt
  print $query;
  chomp(my $answer = <STDIN>);
  return $answer;
}

sub prompt_yn { # To ask Y/N to the user.
  my ($query) = @_;
  my $answer = prompt("$query (Y/N): ");
  return lc($answer) eq 'y';
}

sub verb { #Verbose print
  my $t=shift;
  print STDOUT $t,"\n" if defined($o_verb);
}

sub dverb { # Debug Verbose
  my $t=shift;
  print STDOUT $t,"\n" if defined($o_debugverb);
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
      'h'     => \$o_help,            'help'            => \$o_help,
      'm:i'   => \$o_maxleagues,      'maxleagues:i'    => \$o_maxleagues,
      'r:i'   => \$o_refreshage,      'refreshage:i'    => \$o_refreshage,
      'w:i'   => \$o_currentweek,     'currentweek:i'   => \$o_currentweek,
      's:s'   => \$o_searchleagues,   'searchleagues:s' => \$o_searchleagues,
      'd'     => \$o_updatedb,        'updateplayerdb'  => \$o_updatedb,
      'i'     => \$o_leagueinfo,      'leagueinfo'      => \$o_leagueinfo,
      'I'     => \$o_rosteridinfo,    'rosteridinfo'    => \$o_rosteridinfo,
      't'     => \$o_tradevalueslm,   'tradevalueslm'   => \$o_tradevalueslm,
      'T'     => \$o_tradevalues,     'tradevalues'     => \$o_tradevalues,
      'a'     => \$o_updateadp,       'updateadp'       => \$o_updateadp,
      'e'     => \$o_export,          'export'          => \$o_export,
      'u'     => \$o_updatetrades,    'updatetrades'    => \$o_updatetrades,
      'E'     => \$o_expandusersearch,'expandsearch'    => \$o_expandusersearch,
      'v'     => \$o_verb,            'verbose'         => \$o_verb,
      'V'     => \$o_debugverb,       'debugverbose'    => \$o_debugverb
  );
  help() if(defined($o_help));
  $o_verb = 1 if ($o_debugverb);
  help() if (!((defined($o_searchleagues))||(defined($o_updatedb))||(defined($o_leagueinfo))||(defined($o_rosteridinfo))||(defined($o_export))||(defined($o_tradevalueslm))||(defined($o_tradevalues))||(defined($o_updatetrades))));
}

sub print_usage {
  print "Usage: $0  [-s <USERMANE>] [-m <INT>] [-r <DAYS>] [-w <WEEK>] [-u] [-T] [-i] [-I] [-e] [-E] [-v] [-V] [-h]\n";
}

sub help {
  print "Search Sleeper Trades $0\n";
  print_usage();
  print <<EOT;
-s, --searchleagues <S>
    Username to find new leagues that he and his teammates are in.
-m, --maxleagues <I>
    Max number of leagues to update (to throttle) (default 5).
-r, --refreshage <I>
    How Fresh has to be the data to refresh (default 5 Days).
-w, --currentweek <I>
    Week to update transactions. (if not defined it gets the one reported from the sleeper API).
-u, --updatetrades
    Update the trades from the leagues that hasn't updated in the last refreshage days.
-t, --tradevalues
    Update the Trade Count values of all the players in the DB
-i, --leagueinfo
    Update the settings of the Leagues that have no info
-I, --rosteridinfo
    Update the RosterID settings of the Leagues that have no roster info
-e, --export
    Export CSV from tables and commit to git repository.
-E, --expandsearch
    Expand search to already added leagues.
-d, --updateplayerdb
    Export the Sleeper PlayerDB to the MySQL
-v, --verbose
    Verbose mode.
-V, --debugverbose
    Verbose Mode for Debugging (Much more verbose).
-h, --help
    Print this help message.
EOT
exit 0;
}