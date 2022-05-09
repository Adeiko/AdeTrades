#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use LWP::UserAgent;
use HTTP::Request;
use JSON::XS 'decode_json';
use Scalar::Util qw(looks_like_number);
use List::Util qw(max);
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
use HTML::TreeBuilder;
use File::Basename;
use Data::Dumper;

my ($o_help,$o_verb,$o_debugverb,$o_log,$o_updatetrades,$o_searchleagues,$o_leagueinfo,$o_expandusersearch,$o_updatedb,$o_rosteridinfo,$o_tradevalues,$o_tradevalueslm,$o_export,$o_currentweek,$o_updateadp,$o_ktc,$o_newleaguesAge);
my ($tradedb,$transtradelist,$transpicklist,$transignorelist,$translist,$leaguehashlist,$userhashlist,$players1,$players2,$players3,$owner1,$owner2,$owner3,$draftrounds);
my (@LeagueList,@playerstemp,@LeagueSearchList,@UserSearchList,@LeagueNameList,@LeagueRosterIDList);
my %dlist;

# Default values
my $season = 2022;
my $o_refreshage = 24;
my $o_refreshagerosterids = 30;
my $o_maxleagues = 50;
my $maxIteminTrade = 5;
my $leaguecount = 0;
my $gitrepodir = "$ENV{HOME}/Repositories/AdeTrades";
my $logfile = "/var/log/crons/Sleeper_SearchTrades.log";
my $rootdir = dirname(File::Spec->rel2abs(__FILE__));

check_options(); # Check for the arguments to the script

# Database configuration
my $dbh = DBI->connect("DBI:mysql:database=Sleeper;mysql_read_default_file=$ENV{HOME}/.my.cnf;mysql_read_default_group=Sleeper",undef,undef) or die "Something went wrong ($DBI::errstr)";

# DateTime variables
my $dt = DateTime->new( year => 1970, month => 1, day => 1 );
my $formatter = DateTime::Format::Epoch->new(epoch => $dt,unit => 'milliseconds');
my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(hours => $o_refreshage)->epoch();
my $dtoldrosters = DateTime->now()->subtract(days => $o_refreshagerosterids)->epoch();

if ($o_searchleagues){ # To find new leagues
  $leaguehashlist = $dbh->selectall_hashref ("SELECT LeagueID FROM Leagues_2022","LeagueID");
  if (defined($o_newleaguesAge)){
    my $dtoldleagues = DateTime->now()->subtract(days => $o_newleaguesAge)->epoch();
    @UserSearchList = map { $_->[0] } @{ $dbh->selectall_arrayref ("SELECT UserID FROM SearchedUsers s WHERE s.ScrapeDate < $dtoldleagues OR s.ScrapeDate IS NULL LIMIT $o_maxleagues") };
  }else{
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
      my $numberleagues = get_leagues($useritem);
      $userhashlist->{$useritem} = $useritem; # Add to the Hash so if duplicated in the array do not redo.
      insert_searchedUser($useritem,$numberleagues); # Adds them to the "ignore" list.
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
  logtofile("$leaguecount new leagues (from ". scalar(@LeagueSearchList)." found) added from the query of user ${o_searchleagues}");
  $o_maxleagues = $leaguecount;
}
if ($o_leagueinfo or ($leaguecount > 0)){
  get_leaguelistUpdateInfo($o_maxleagues);
  if (scalar(@LeagueNameList) > 0){
    my $currentInfo = 0;
    my $nextInfoupdate = 0;
    my $progressInfo = Term::ProgressBar->new({name  => 'Finding League Info', count => scalar(@LeagueNameList), ETA   => 'linear', remove => 1});
    $progressInfo->max_update_rate(1);
    my $leaguepending = max(get_CountleaguelistUpdateInfo()-scalar(@LeagueNameList),0);
    $progressInfo->message("Searching for Info  for ".scalar(@LeagueNameList)." Leagues (${leaguepending} pending)\n");
    foreach my $leagueU (@LeagueNameList){
      get_leagueAllinfo($leagueU);
      $currentInfo++;
      $nextInfoupdate = $progressInfo->update($currentInfo) if $currentInfo > $nextInfoupdate;
    }
    $progressInfo->update(scalar(@LeagueNameList)) if scalar(@LeagueNameList) >= $nextInfoupdate;
    logtofile("Updated info for ".scalar(@LeagueNameList)." Leagues");
  }else{
    logtofile("No League info pending to update");
    print "No League info pending to update\n";
  }
}

if ($o_rosteridinfo or ($leaguecount > 0)){ # Scrape the relation between RosterID and UserID for leagues
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
    logtofile("Updated RosterIDs for ".scalar(@LeagueRosterIDList)." Leagues");
  }else{
    logtofile("No League RosterID info pending to update");
    print "No League RosterID info pending to update\n";
  }
}

if ($o_updatetrades or ($leaguecount > 0)){
  $transpicklist = $dbh->selectall_hashref ("SELECT TradeID FROM Trades_2022","TradeID");
  $transtradelist = $dbh->selectall_hashref ("SELECT TradeID FROM PickTrades_2022","TradeID");
  $transignorelist = $dbh->selectall_hashref ("SELECT TradeID FROM RevertedTrades","TradeID");
  $translist = {%$transpicklist, %$transtradelist, %$transignorelist}; # Get a Hash of Trades to be ignored
  get_leaguelist($o_maxleagues);
  if (scalar(@LeagueList) > 0){
    my $currentLeague = 0;
    my $next_update = 0;
    my $progress = Term::ProgressBar->new({name  => 'Searching Trades', count => scalar(@LeagueList), ETA   => 'linear', remove => 1});
    $progress->max_update_rate(1);
    my $leaguetradepending = max(get_leaguePendingUpdate()-scalar(@LeagueList),0);
    $progress->message("Searching for Trades for ".scalar(@LeagueList)." Leagues (${leaguetradepending} pending)\n");
    foreach my $leagueN (@LeagueList){
      $currentLeague++;
      get_currentstate() if (!(defined($o_currentweek)));
      get_trades($leagueN,$o_currentweek);
      $next_update = $progress->update($currentLeague) if $currentLeague > $next_update;
    }
    $progress->update(scalar(@LeagueList)) if scalar(@LeagueList) >= $next_update;
    logtofile("Searched trades for ".scalar(@LeagueList)." Leagues");
    insert_tradeHash();
    logtofile("Added to the Database trades for ".scalar(@LeagueList)." Leagues");
  }else{
    logtofile("No league trades pending to update");
    print ("No league trades pending to update\n");
  }
}

export_sleeperplayers() if ($o_updatedb); # Update the MySQL PlayerDB with Sleeper Data.
update_KTC() if ($o_ktc); # Update the KTC values
update_DevyKTC() if ($o_ktc); # Update the KTC values
updateTradeValues() if ($o_tradevalues or $o_tradevalueslm); # Update the Trade Stats using queries to the DB
update_ADP() if ($o_updateadp); # Update the ADP from Google Sheet

if ($o_export){
  clean_data();  # Clean the Database of Reversed/duplicate trades
  export_data(); # Export Data to CSV and commit
}

exit(0);

sub get_leagueAllinfo{ # Get All leagues from a User
  my $league_id = shift;
  dverb("\nSearching for league $league_id");
  my $leaguejson = get_json("https://api.sleeper.app/v1/league/${league_id}",$league_id);
  my ($league_name,$league_status,$league_draftid,$league_draftrounds,$league_average_match,$best_ball,$previous_league_id,$RookieDraft,$RookieRounds,$RookieStatus,$RookieTimeUpdate,$taxi_slots,$total_rosters,$trade_deadline);
  my ($bonus_pass_cmp_25,$bonus_pass_yd_300,$bonus_pass_yd_400,$bonus_rec_rb,$bonus_rec_te,$bonus_rec_wr,$bonus_rec_yd_100,$bonus_rec_yd_200,$bonus_rush_att_20,$bonus_rush_rec_yd_100,$bonus_rush_rec_yd_200,$bonus_rush_yd_100,$bonus_rush_yd_200,$fum,$fum_lost,$pass_2pt,$pass_att,$pass_cmp,$pass_cmp_40p,$pass_fd,$pass_inc,$pass_int,$pass_int_td,$pass_sack,$pass_td,$pass_td_40p,$pass_td_50p,$pass_yd,$rec_0_4,$rec_10_19,$rec_20_29,$rec_2pt,$rec_30_39,$rec_40p,$rec_5_9,$rec_bonus,$rec_fd,$rec_td,$rec_td_40p,$rec_td_50p,$rec_yd,$rush_2pt,$rush_40p,$rush_att,$rush_fd,$rush_td,$rush_td_40p,$rush_td_50p,$rush_yd,$sack);
  if (exists($leaguejson->{name})){ $league_name = $leaguejson->{name} }else{ next };
  if (exists($leaguejson->{total_rosters})){ $total_rosters =$leaguejson->{total_rosters} }else{ $total_rosters = 0 };
  if (exists($leaguejson->{status})){ $league_status =$leaguejson->{status} }else{ $league_status = 0 };
  if (exists($leaguejson->{previous_league_id})){ $previous_league_id =$leaguejson->{previous_league_id} }else{ $previous_league_id = 0 };
  if (exists($leaguejson->{draft_id})){ $league_draftid =$leaguejson->{draft_id} }else{ $league_draftid = 0 };
  if (exists($leaguejson->{settings}->{taxi_slots})){ $taxi_slots = $leaguejson->{settings}->{taxi_slots} }else{ $taxi_slots = 0 };
  if (exists($leaguejson->{settings}->{trade_deadline})){ $trade_deadline = $leaguejson->{settings}->{trade_deadline} }else{ $trade_deadline = 0 };
  if (exists($leaguejson->{settings}->{draft_rounds})){ $league_draftrounds = $leaguejson->{settings}->{draft_rounds} }else{ $league_draftrounds = 0 };
  if (exists($leaguejson->{settings}->{best_ball})){ $best_ball = $leaguejson->{settings}->{best_ball} }else{ $best_ball = 0 };
  if (exists($leaguejson->{settings}->{league_average_match})){ $league_average_match = $leaguejson->{settings}->{league_average_match} }else{ $league_average_match = 0 };
  if (!defined($previous_league_id)){$previous_league_id = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_pass_cmp_25})){ $bonus_pass_cmp_25 = $leaguejson->{scoring_settings}->{bonus_pass_cmp_25} }else{ $bonus_pass_cmp_25 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_pass_yd_300})){ $bonus_pass_yd_300 = $leaguejson->{scoring_settings}->{bonus_pass_yd_300} }else{ $bonus_pass_yd_300 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_pass_yd_400})){ $bonus_pass_yd_400 = $leaguejson->{scoring_settings}->{bonus_pass_yd_400} }else{ $bonus_pass_yd_400 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_rb})){ $bonus_rec_rb = $leaguejson->{scoring_settings}->{bonus_rec_rb} }else{ $bonus_rec_rb = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_te})){ $bonus_rec_te = $leaguejson->{scoring_settings}->{bonus_rec_te} }else{ $bonus_rec_te = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_wr})){ $bonus_rec_wr = $leaguejson->{scoring_settings}->{bonus_rec_wr} }else{ $bonus_rec_wr = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_yd_100})){ $bonus_rec_yd_100 = $leaguejson->{scoring_settings}->{bonus_rec_yd_100} }else{ $bonus_rec_yd_100 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_yd_200})){ $bonus_rec_yd_200 = $leaguejson->{scoring_settings}->{bonus_rec_yd_200} }else{ $bonus_rec_yd_200 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rush_att_20})){ $bonus_rush_att_20 = $leaguejson->{scoring_settings}->{bonus_rush_att_20} }else{ $bonus_rush_att_20 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rush_rec_yd_100})){ $bonus_rush_rec_yd_100 = $leaguejson->{scoring_settings}->{bonus_rush_rec_yd_100} }else{ $bonus_rush_rec_yd_100 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rush_rec_yd_200})){ $bonus_rush_rec_yd_200 = $leaguejson->{scoring_settings}->{bonus_rush_rec_yd_200} }else{ $bonus_rush_rec_yd_200 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rush_yd_100})){ $bonus_rush_yd_100 = $leaguejson->{scoring_settings}->{bonus_rush_yd_100} }else{ $bonus_rush_yd_100 = 0};
  if (exists($leaguejson->{scoring_settings}->{bonus_rush_yd_200})){ $bonus_rush_yd_200 = $leaguejson->{scoring_settings}->{bonus_rush_yd_200} }else{ $bonus_rush_yd_200 = 0};
  if (exists($leaguejson->{scoring_settings}->{fum})){ $fum = $leaguejson->{scoring_settings}->{fum} }else{ $fum = 0};
  if (exists($leaguejson->{scoring_settings}->{fum_lost})){ $fum_lost = $leaguejson->{scoring_settings}->{fum_lost} }else{ $fum_lost = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_2pt})){ $pass_2pt = $leaguejson->{scoring_settings}->{pass_2pt} }else{ $pass_2pt = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_att})){ $pass_att = $leaguejson->{scoring_settings}->{pass_att} }else{ $pass_att = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_cmp})){ $pass_cmp = $leaguejson->{scoring_settings}->{pass_cmp} }else{ $pass_cmp = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_cmp_40p})){ $pass_cmp_40p = $leaguejson->{scoring_settings}->{pass_cmp_40p} }else{ $pass_cmp_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_fd})){ $pass_fd = $leaguejson->{scoring_settings}->{pass_fd} }else{ $pass_fd = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_inc})){ $pass_inc = $leaguejson->{scoring_settings}->{pass_inc} }else{ $pass_inc = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_int})){ $pass_int = $leaguejson->{scoring_settings}->{pass_int} }else{ $pass_int = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_int_td})){ $pass_int_td = $leaguejson->{scoring_settings}->{pass_int_td} }else{ $pass_int_td = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_sack})){ $pass_sack = $leaguejson->{scoring_settings}->{pass_sack} }else{ $pass_sack = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_td})){ $pass_td = $leaguejson->{scoring_settings}->{pass_td} }else{ $pass_td = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_td_40p})){ $pass_td_40p = $leaguejson->{scoring_settings}->{pass_td_40p} }else{ $pass_td_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_td_50p})){ $pass_td_50p = $leaguejson->{scoring_settings}->{pass_td_50p} }else{ $pass_td_50p = 0};
  if (exists($leaguejson->{scoring_settings}->{pass_yd})){ $pass_yd = $leaguejson->{scoring_settings}->{pass_yd} }else{ $pass_yd = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_0_4})){ $rec_0_4 = $leaguejson->{scoring_settings}->{rec_0_4} }else{ $rec_0_4 = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_10_19})){ $rec_10_19 = $leaguejson->{scoring_settings}->{rec_10_19} }else{ $rec_10_19 = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_20_29})){ $rec_20_29 = $leaguejson->{scoring_settings}->{rec_20_29} }else{ $rec_20_29 = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_2pt})){ $rec_2pt = $leaguejson->{scoring_settings}->{rec_2pt} }else{ $rec_2pt = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_30_39})){ $rec_30_39 = $leaguejson->{scoring_settings}->{rec_30_39} }else{ $rec_30_39 = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_40p})){ $rec_40p = $leaguejson->{scoring_settings}->{rec_40p} }else{ $rec_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_5_9})){ $rec_5_9 = $leaguejson->{scoring_settings}->{rec_5_9} }else{ $rec_5_9 = 0};
  if (exists($leaguejson->{scoring_settings}->{rec})){ $rec_bonus = $leaguejson->{scoring_settings}->{rec} }else{ $rec_bonus = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_fd})){ $rec_fd = $leaguejson->{scoring_settings}->{rec_fd} }else{ $rec_fd = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_td})){ $rec_td = $leaguejson->{scoring_settings}->{rec_td} }else{ $rec_td = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_td_40p})){ $rec_td_40p = $leaguejson->{scoring_settings}->{rec_td_40p} }else{ $rec_td_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_td_50p})){ $rec_td_50p = $leaguejson->{scoring_settings}->{rec_td_50p} }else{ $rec_td_50p = 0};
  if (exists($leaguejson->{scoring_settings}->{rec_yd})){ $rec_yd = $leaguejson->{scoring_settings}->{rec_yd} }else{ $rec_yd = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_2pt})){ $rush_2pt = $leaguejson->{scoring_settings}->{rush_2pt} }else{ $rush_2pt = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_40p})){ $rush_40p = $leaguejson->{scoring_settings}->{rush_40p} }else{ $rush_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_att})){ $rush_att = $leaguejson->{scoring_settings}->{rush_att} }else{ $rush_att = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_fd})){ $rush_fd = $leaguejson->{scoring_settings}->{rush_fd} }else{ $rush_fd = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_td})){ $rush_td = $leaguejson->{scoring_settings}->{rush_td} }else{ $rush_td = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_td_40p})){ $rush_td_40p = $leaguejson->{scoring_settings}->{rush_td_40p} }else{ $rush_td_40p = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_td_50p})){ $rush_td_50p = $leaguejson->{scoring_settings}->{rush_td_50p} }else{ $rush_td_50p = 0};
  if (exists($leaguejson->{scoring_settings}->{rush_yd})){ $rush_yd = $leaguejson->{scoring_settings}->{rush_yd} }else{ $rush_yd = 0};
  if (exists($leaguejson->{scoring_settings}->{sack})){ $sack = $leaguejson->{scoring_settings}->{sack} }else{ $sack = 0};
  my $roster_positions_QB = grep { $_ eq "QB" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_RB = grep { $_ eq "RB" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_WR = grep { $_ eq "WR" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_TE = grep { $_ eq "TE" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_FLEX = grep { $_ eq "FLEX" or $_ eq "REC_FLEX" or $_ eq "WRRB_FLEX"} @{ $leaguejson->{roster_positions} };
  my $roster_positions_SUPER_FLEX = grep { $_ eq "SUPER_FLEX" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_K = grep { $_ eq "K" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_DEF = grep { $_ eq "DEF" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_LB = grep { $_ eq "LB" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_DB = grep { $_ eq "DB" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_DL = grep { $_ eq "DL" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_IDP_FLEX = grep { $_ eq "IDP_FLEX" } @{ $leaguejson->{roster_positions} };
  my $roster_positions_BN = grep { $_ eq "BN" } @{ $leaguejson->{roster_positions} };
  my $total_players = $roster_positions_QB + $roster_positions_RB + $roster_positions_WR + $roster_positions_TE + $roster_positions_FLEX + $roster_positions_SUPER_FLEX + $roster_positions_BN + $roster_positions_K + $roster_positions_DEF + $roster_positions_LB + $roster_positions_DB + $roster_positions_DL + $roster_positions_IDP_FLEX;
  my $league_name_q = $dbh->quote($league_name);
  my $sth = $dbh->prepare(qq/UPDATE Leagues_2022 SET name = $league_name_q,LastUpdate = $dtnow,RookieRounds = $league_draftrounds,RookieTimeUpdate = $dtnow,RookieStatus = "$league_status",RookieDraft = $league_draftid,best_ball = $best_ball,league_average_match = $league_average_match,trade_deadline = $trade_deadline,previous_league_id = $previous_league_id,taxi_slots = $taxi_slots,total_players = $total_players,total_rosters = $total_rosters,roster_positions_BN = $roster_positions_BN,roster_positions_DB = $roster_positions_DB,roster_positions_DEF = $roster_positions_DEF,roster_positions_DL = $roster_positions_DL,roster_positions_FLEX = $roster_positions_FLEX,roster_positions_IDP_FLEX = $roster_positions_IDP_FLEX,roster_positions_K = $roster_positions_K,roster_positions_LB = $roster_positions_LB,roster_positions_QB = $roster_positions_QB,roster_positions_RB = $roster_positions_RB,roster_positions_SUPER_FLEX = $roster_positions_SUPER_FLEX,roster_positions_TE = $roster_positions_TE,roster_positions_WR = $roster_positions_WR,bonus_pass_cmp_25 = $bonus_pass_cmp_25,bonus_pass_yd_300 = $bonus_pass_yd_300,bonus_pass_yd_400 = $bonus_pass_yd_400,bonus_rec_rb = $bonus_rec_rb,bonus_rec_te = $bonus_rec_te,bonus_rec_wr = $bonus_rec_wr,bonus_rec_yd_100 = $bonus_rec_yd_100,bonus_rec_yd_200 = $bonus_rec_yd_200,bonus_rush_att_20 = $bonus_rush_att_20,bonus_rush_rec_yd_100 = $bonus_rush_rec_yd_100,bonus_rush_rec_yd_200 = $bonus_rush_rec_yd_200,bonus_rush_yd_100 = $bonus_rush_yd_100,bonus_rush_yd_200 = $bonus_rush_yd_200,fum = $fum,fum_lost = $fum_lost,pass_2pt = $pass_2pt,pass_att = $pass_att,pass_cmp = $pass_cmp,pass_cmp_40p = $pass_cmp_40p,pass_fd = $pass_fd,pass_inc = $pass_inc,pass_int = $pass_int,pass_int_td = $pass_int_td,pass_sack = $pass_sack,pass_td = $pass_td,pass_td_40p = $pass_td_40p,pass_td_50p = $pass_td_50p,pass_yd = $pass_yd,rec_0_4 = $rec_0_4,rec_10_19 = $rec_10_19,rec_20_29 = $rec_20_29,rec_2pt = $rec_2pt,rec_30_39 = $rec_30_39,rec_40p = $rec_40p,rec_5_9 = $rec_5_9,rec_bonus = $rec_bonus,rec_fd = $rec_fd,rec_td = $rec_td,rec_td_40p = $rec_td_40p,rec_td_50p = $rec_td_50p,rec_yd = $rec_yd,rush_2pt = $rush_2pt,rush_40p = $rush_40p,rush_att = $rush_att,rush_fd = $rush_fd,rush_td = $rush_td,rush_td_40p = $rush_td_40p,rush_td_50p = $rush_td_50p,rush_yd = $rush_yd,sack = $sack WHERE LeagueID = $league_id;/);
  $sth->execute();
  $sth->finish;
  dverb("Scraped League ${league_id}");
  # dverb("League ${league_id}\nleague_name: ${league_name}\nleague_total_rosters: ${league_total_rosters}\nleague_taxi_slots: ${league_taxi_slots}\nleague_rec: ${league_rec}\nleague_bonus_rec_wr: ${league_bonus_rec_wr}\nleague_bonus_rec_te: ${league_bonus_rec_te}\nleague_bonus_rec_rb: ${league_bonus_rec_rb}\nleague_pass_td: ${league_pass_td}\nleague_pass_int: ${league_pass_int}\nPositions_QB: ${Positions_QB}\nPositions_RB: ${Positions_RB}\nPositions_WR: ${Positions_WR}\nPositions_TE: ${Positions_TE}\nPositions_FLEX: ${Positions_FLEX}\nPositions_SUPER_FLEX: ${Positions_SUPER_FLEX}\nPositions_BN: ${Positions_BN}\ntotal_players: ${total_players}");
}

sub get_leaguedrafts{ # Gets draft slots from the league of that year
  my $league_id = shift;
  my $draftsjson = get_json("https://api.sleeper.app/v1/league/$league_id/drafts");
  foreach my $draft( @$draftsjson ) {
    next unless ($draft->{season} eq $season);
    my $draftjson = get_json("https://api.sleeper.app/v1/draft/$draft->{draft_id}");
    $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{draftrounds} = $draftjson->{settings}->{rounds} if (exists( $draftjson->{settings}->{rounds}));
    $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{type} = $draftjson->{type} if (exists( $draftjson->{type}));
    $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{teams} = $draftjson->{settings}->{teams} if (exists( $draftjson->{settings}->{teams}));
    $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{reversal_round} = 0;

    if (exists( $draftjson->{settings}->{reversal_round})){
      if ($draftjson->{settings}->{reversal_round} > 0){
        $tradedb->{$league_id}->{drafts}->{$draft->{draft_id}}->{reversal_round} = $draftjson->{settings}->{reversal_round};
      }
    }
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

sub get_leaguerosterID{ # Update the MySQL RosterID reference Table
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
                }else{ # Trying to check if the draft newer or older.
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
              dverb("Have chosen ${current_draft} for the trade ".$drafttime->dmy('/')." with date ". $formatter->parse_datetime($tradedb->{$league_id}->{drafts}->{$current_draft}->{last_picked})->dmy('/'));
              ($oldtime,$newtime,$drafttime)=undef;
            }
            if (exists($tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}})){
              $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round}).".".sprintf("%02d",$tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}});
              if (($tradedb->{$league_id}->{drafts}->{$current_draft}->{type} eq "snake")&& (!($keypicks->{round}%2))){
                my $reversepick = $tradedb->{$league_id}->{drafts}->{$current_draft}->{teams} - $tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}} +1;
                $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round}).".".sprintf("%02d",$reversepick);
              }
              if (($keypicks->{round}>=$tradedb->{$league_id}->{drafts}->{$current_draft}->{reversal_round}) && (($tradedb->{$league_id}->{drafts}->{$current_draft}->{reversal_round}>0))){
                if (($tradedb->{$league_id}->{drafts}->{$current_draft}->{type} eq "snake")&& ($keypicks->{round}%2)){
                  my $reversepick = $tradedb->{$league_id}->{drafts}->{$current_draft}->{teams} - $tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}} +1;
                  $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round}).".".sprintf("%02d",$reversepick);
                }else{
                  $picktext = "$keypicks->{season}-".sprintf("%02d",$keypicks->{round}).".".sprintf("%02d",$tradedb->{$league_id}->{drafts}->{$current_draft}->{slots}->{$keypicks->{roster_id}});
                }
              }
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
  update_leagueTime($league_id); # Update the time to not scrape it again in X days
}

sub get_leagues { # Get All leagues from a User
  my $userID = shift;
  my $leaguejson = get_json("https://api.sleeper.app/v1/user/${userID}/leagues/nfl/${season}");
  my $numleagues = 0;
  # print Dumper ($leaguejson);
  foreach my $leagueitem ( @$leaguejson ) {
    next if (grep(/\bfree\b/i,$leagueitem->{name})); # Skip league if has Free (case insensitive) in the name
    next if (grep(/\bmock\b/i,$leagueitem->{name}));  # Skip league if has mock (case insensitive) in the name
    print "Leaguetype: ".$leagueitem->{settings}->{type}."\n";
    print "Teams: " . $leagueitem->{settings}->{num_teams}."\n";
    # print "Pos: " . (scalar @{ $leagueitem->{roster_positions}) ."\n";
    print "start: " . (grep { $_ eq "QB" or $_ eq "RB" or $_ eq "WR" or $_ eq "TE" or $_ eq "K" or $_ eq "FLEX" or $_ eq "REC_FLEX" or $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }) . "\n";
    next unless ($leagueitem->{settings}->{type} == 2); # Only DynastyLeagues
    next unless (ref($leagueitem->{roster_positions}) eq 'ARRAY' and grep { $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }); # Only Superflex Leagues
    next unless ( ($leagueitem->{settings}->{num_teams} eq "12") || ($leagueitem->{settings}->{num_teams} eq "14") ); # Only 12/14 Player Leagues
    next unless (scalar @{ $leagueitem->{roster_positions} } > 20); # Min 20 players per team
    next unless ((grep { $_ eq "QB" or $_ eq "RB" or $_ eq "WR" or $_ eq "TE" or $_ eq "K" or $_ eq "FLEX" or $_ eq "REC_FLEX" or $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }) >= 8); # Min 8 Starters
    push(@LeagueSearchList, $leagueitem->{league_id}) unless(grep(/^$leagueitem->{league_id}$/,@LeagueSearchList)); # Add them to the LeagueList unless already exists
    verb("Adding league $leagueitem->{league_id} to arraysearch");
    $numleagues++;
  }
  return $numleagues;
}

sub get_leaguelist{ # Get the LeagueList from the MySQL that hasn't updated in X time
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT LeagueID FROM Leagues_2022 WHERE PossibleDeleted = FALSE AND LastUpdate < $dtold OR LastUpdate IS NULL LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguelistUpdateInfo{ # Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT LeagueID FROM Leagues_2022 WHERE PossibleDeleted = FALSE AND name IS NULL LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueNameList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_CountleaguelistUpdateInfo{ # Get the LeagueList missing information from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(LeagueID) FROM Leagues_2022 WHERE PossibleDeleted = FALSE AND name IS NULL/);
  $sth->execute();
  my $pendingleagues = $sth->fetchrow;
  $sth->finish;
  return $pendingleagues;
}

sub get_leaguelistUpdateRosterID{ # Get the LeagueList without rosterID information from the MySQL
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT DISTINCT l.LeagueID FROM Leagues_2022 l LEFT JOIN RosterID_Reference r ON r.LeagueID = l.LeagueID WHERE r.LeagueID IS NULL AND (r.LastUpdate < $dtoldrosters OR r.LastUpdate IS NULL) LIMIT $leaguelimit/);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueRosterIDList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_leaguePendingUpdate{ # Get Number of leagues missing update
  my $leaguelimit = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(LeagueID) FROM Leagues_2022 WHERE PossibleDeleted = FALSE AND (LastUpdate < $dtold OR LastUpdate IS NULL)/);
  $sth->execute();
  my $pendingleagues = $sth->fetchrow;
  $sth->finish;
  if ($pendingleagues > $o_maxleagues){
    $pendingleagues = $pendingleagues;
  }else{
    $pendingleagues = 0;
  }
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
  if ($status_json->{display_week} > 0){
    $o_currentweek = $status_json->{display_week};
  }
  else{
    $o_currentweek = 1;
  }
  if ($status_json->{season_type} eq "pre"){
    $o_currentweek = 1;
  }
}

sub insert_newleague{ # Adds a new League to the list
  my $new_league = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO Leagues_2022(LeagueID) VALUES (?)},{},);
  $sth->execute($new_league);
  $sth->finish;
}

sub insert_searchedUser{ # Adds a new user to the searched list
  my $new_user = shift;
  my $league_number = shift;
  my $sth = $dbh->prepare(qq/INSERT IGNORE INTO SearchedUsers(UserID,ScrapeDate,LeagueCount) VALUES ($new_user,$dtnow,$league_number) ON DUPLICATE KEY UPDATE SearchedUsers.ScrapeDate = $dtnow,SearchedUsers.LeagueCount = $league_number;/);
  $sth->execute();
  $sth->finish;
}

sub insert_newtrade{ # Inserts one Trades into MySQL
  my ($transactions_id,$league_id,$trans_time,$items1,$items2,$items3,$owners1,$owners2,$owners3,$draftrounds) = (@_);
  my $TradeDatabase = "Trades_2022";
  return if ((!(defined($items1))) or (!(defined($items2))));
  my $countitems1 = () = $items1 =~ /\Q;/g;
  my $countitems2 = () = $items2 =~ /\Q;/g;
  return if (($countitems1 > $maxIteminTrade) or ($countitems2 > $maxIteminTrade));
  $TradeDatabase = "PickTrades_2022" if ((!($items1 =~ m/.*,.*/)) and (!($items2 =~ m/.*,.*/)));
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
  my $sth = $dbh->prepare(qq/UPDATE Leagues_2022 SET LastUpdate = $dtnow WHERE LeagueID = $league_id/);
  $sth->execute();
  $sth->finish;
  verb("Updating time of league ${league_id}");
}

sub update_PossibleDeleted{ # Inserts in the MySQL the Possible Delete Status
  my $league_id = shift;
  my $sth = $dbh->prepare(qq/UPDATE Leagues_2022 SET PossibleDeleted = TRUE WHERE LeagueID = $league_id/);
  $sth->execute();
  $sth->finish;
  verb("Updating Possible Deleted league ${league_id}");
}

sub update_ADP{ #Read the ADP Google Sheet and import the new ADP in the TradeStats Table
  my $yaml = YAML::Tiny->read("${rootdir}/gapi.yaml");
  my $oauth2 = Google::RestApi::Auth::OAuth2Client->new(
    client_id => $yaml->[0]{auth}{client_id},
    client_secret => $yaml->[0]{auth}{client_secret},
    token_file => "${rootdir}/gapi_stored_google_access.session"
  );
  my $restapi = Google::RestApi->new(auth =>$oauth2);
  my $sheets = Google::RestApi::SheetsApi4->new(api => $restapi);
  my $spreadsheet = $sheets->open_spreadsheet(id => '10iRLANRFajrQmeZvleh-BKtXbNTUDDE0rX4tOwtqd98');
  my $worksheet = $spreadsheet->open_worksheet(name => 'ADP_Players');
  my $ADPrange = $worksheet->range("ADP_Export");
  my $ADPvalues = $ADPrange->values();
  foreach my $PlayerADP (@$ADPvalues){
    Update_TradeStatsADP(@$PlayerADP[0],@$PlayerADP[1]);
    verb ("PlayerID: ".@$PlayerADP[0]);
    verb ("ADP: ".@$PlayerADP[1]) if (defined(@$PlayerADP[1]));
  }
  logtofile("Updated the ADP Database");
}

sub update_KTC{ # Load KTC values to the Database
  my $jsonktc = decode_json(get_ktcjsonvalues());
  my $dbst;

  foreach my $player( @$jsonktc ) {
    my $k_tm =  $dbh->quote($player->{team});
    my $k_id =  $dbh->quote($player->{playerID});
    my $k_pos =  $dbh->quote($player->{position});
    my $k_name = $dbh->quote($player->{playerName});
    my $k_val =  $dbh->quote($player->{superflexValues}->{value});
    $dbst = $dbh->prepare(
      qq/
        INSERT IGNORE INTO KeepTradeCut
          (player_id,player_name,position,team,value)
        VALUES
          ($k_id,$k_name,$k_pos,$k_tm,$k_val)
        ON DUPLICATE KEY UPDATE
          KeepTradeCut.value = $k_val
      /
    );
    verb ($k_tm.",".$k_id.",".$k_name.",".$k_pos.",".$k_val);
    $dbst->execute() or die $dbst->errstr;
  }
  $dbst->finish;
  logtofile("Updated the KTC NFL Database");
}

sub update_DevyKTC{ # Load KTC values to the Database
  my $jsonktc = decode_json(get_ktcdevyjsonvalues());
  my $dbst;

  foreach my $player( @$jsonktc ) {
    my $k_tm =  $dbh->quote($player->{team});
    my $k_id =  $dbh->quote($player->{playerID});
    my $k_pos =  $dbh->quote($player->{position});
    my $k_name = $dbh->quote($player->{playerName});
    my $k_val =  $dbh->quote($player->{superflexValues}->{value});
    $dbst = $dbh->prepare(
      qq/
        INSERT IGNORE INTO DevyKeepTradeCut
          (player_id,player_name,position,team,value)
        VALUES
          ($k_id,$k_name,$k_pos,$k_tm,$k_val)
        ON DUPLICATE KEY UPDATE
          DevyKeepTradeCut.value = $k_val
      /
    );
    verb ($k_tm.",".$k_id.",".$k_name.",".$k_pos.",".$k_val);
    $dbst->execute() or die $dbst->errstr;
  }
  $dbst->finish;
  logtofile("Updated the KTC Devy Database");
}

sub Update_TradeStatsADP{ # Insert the ADP in the TradeStats file
  my $splayerid = shift;
  my $sadp = shift;
  if (!(defined($splayerid))){return;};
  if (defined($sadp)){
    my $sts = $dbh->prepare(qq/UPDATE TradeStats_2022 SET ADP = $sadp WHERE PlayerID = $splayerid;/);
    $sts->execute();
    $sts->finish;
  }else{
    my $sts = $dbh->prepare(qq/UPDATE TradeStats_2022 SET ADP = NULL WHERE PlayerID = $splayerid;/);
    $sts->execute();
    $sts->finish;
  }
}

sub updateTradeValues{ # Generate the trade count for each player in the 12 diferent months
  my $query = qq/SELECT PlayerName FROM TradeStats_2022 Where LastCount < $dtold OR LastCount IS NULL/;
  $query = qq/SELECT PlayerName FROM TradeStats_2022/ if ($o_tradevalueslm);
  verb("Upgrading TradeValues");
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
        update_count($row->{PlayerName},"s${season}09",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 9)),$formatter->format_datetime(DateTime->new(year => $season, month => 10)))) unless (DateTime->now()->month < 9);
        update_count($row->{PlayerName},"s${season}10",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 10)),$formatter->format_datetime(DateTime->new(year => $season, month => 11)))) unless (DateTime->now()->month < 10);
        update_count($row->{PlayerName},"s${season}11",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 11)),$formatter->format_datetime(DateTime->new(year => $season, month => 12)))) unless (DateTime->now()->month < 11);
        update_count($row->{PlayerName},"s${season}12",get_count($row->{PlayerName},$formatter->format_datetime(DateTime->new(year => $season, month => 12)),$formatter->format_datetime(DateTime->new(year => $season+1, month => 1)))) unless (DateTime->now()->month < 12);
        update_count($row->{PlayerName},"LastCount",$dtnow);
      }
      $currentPlayerTS++;
      $nextPlayerTSupdate = $progressPlayerTS->update($currentPlayerTS) if $currentPlayerTS > $nextPlayerTSupdate;
    }
    $progressPlayerTS->update($sth->rows) if $sth->rows >= $nextPlayerTSupdate;
  }
  $sth->finish;
  logtofile("Updated the TradeStats count");
}

sub get_count{ # Count number of trades for X players
  my $splayer = shift;
  my $mintime = shift;
  my $maxtime = shift;
  my $sth = $dbh->prepare(qq/SELECT COUNT(t.TradeID) FROM Sleeper.Trades_2022 t WHERE ((t.Items1 like "%$splayer%") or (t.Items2 like "%$splayer%")) AND Time > ${mintime} AND Time < ${maxtime}/);
  $sth->execute();
  my $splayercount = $sth->fetchrow;
  $sth->finish;
  return $splayercount;
}

sub update_count{ # Insert in the Tradestats a value in X column
  my $splayer = shift;
  my $scolumn = shift;
  my $svalue = shift;
  my $splayerq = $dbh->quote($splayer);
  my $sth = $dbh->prepare(qq/UPDATE TradeStats_2022 SET ${scolumn} = ${svalue} WHERE PlayerName = ${splayerq}/);
  $sth->execute();
  $sth->finish;
}

sub clean_data{ # Cleaning trade Tables of wrong data
  verb("Adding Empty Trades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM Trades_2022 WHERE Items1 = "" OR Items2 = ""');
  verb("Adding Empty Picktrades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades_2022 WHERE Items1 = "" OR Items2 = ""');
  verb("Adding Picktrades with empty rounds to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades_2022 WHERE DraftRounds = 0');
  verb("Adding Duplicate Trades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM Trades_2022 GROUP BY TradeID HAVING COUNT(*) > 1');
  verb("Adding Duplicate PickTrades to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT TradeID FROM PickTrades_2022 GROUP BY TradeID HAVING COUNT(*) > 1');
  verb("Adding trades reversed to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT t.TradeID FROM Sleeper.Trades_2022 t JOIN (SELECT Items1, Items2, League, count(*) as NumDuplicates FROM Trades_2022 GROUP BY Items1, Items2, League HAVING NumDuplicates > 1 ) tsum ON t.Items1 = tsum.Items1 AND t.Items2 = tsum.Items2 AND t.League = tsum.League');
  verb("Adding Picktrades reversed to RevertedTrades");
  $dbh->do('INSERT IGNORE INTO RevertedTrades SELECT t.TradeID FROM Sleeper.PickTrades_2022 t JOIN (SELECT Items1, Items2, League, count(*) as NumDuplicates FROM Trades_2022 GROUP BY Items1, Items2, League HAVING NumDuplicates > 1 ) tsum ON t.Items1 = tsum.Items1 AND t.Items2 = tsum.Items2 AND t.League = tsum.League');
  verb("Cleaning Trades");
  $dbh->do('DELETE FROM Trades_2022 WHERE TradeID IN (SELECT r.TradeID FROM RevertedTrades r WHERE r.TradeID IS NOT NULL)');
  verb("Cleaning Picktrades");
  $dbh->do('DELETE FROM PickTrades_2022 WHERE TradeID IN (SELECT r.TradeID FROM RevertedTrades r WHERE r.TradeID IS NOT NULL)');
  verb("Cleaning Ignored Leagues");
  $dbh->do('DELETE FROM Leagues_2022 WHERE LeagueID IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
  verb("Cleaning Trades from IngoredLeagues");
  $dbh->do('DELETE FROM Trades_2022 WHERE League IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
  verb("Cleaning PickTrades from Ignored Leagues");
  $dbh->do('DELETE FROM PickTrades_2022 WHERE League IN (SELECT i.LeagueID FROM IgnoredLeagues i WHERE i.LeagueID IS NOT NULL)');
}

sub export_data{ # Generate CSV and push them to the Repository
  my $repo = Git::Repository->new( work_tree => $gitrepodir);
  my $repopull = $repo->run( 'pull' );
  csv (out => "${gitrepodir}/Leagues_2022.csv", sep_char => ";", headers => [qw( League_ID Name Rosters QB RB WR TE Flex SFlex BN Total_Players Start_Players Taxi_Slots Rec_Bonus Rec_RB Rec_WR Rec_TE Pass_TD Pass_Int Old_League_ID )], in => $dbh->selectall_arrayref ("SELECT LeagueID,name,total_rosters,roster_positions_QB,roster_positions_RB,roster_positions_WR,roster_positions_TE,roster_positions_FLEX,roster_positions_SUPER_FLEX,roster_positions_BN,total_players,total_players - roster_positions_BN AS Start_Players,taxi_slots,pass_td,rec_bonus,bonus_rec_te,bonus_rec_rb,bonus_rec_wr,pass_int,previous_league_id FROM Leagues_2022"));
  csv (out => "${gitrepodir}/Leagues_2022_All.csv", sep_char => ";", headers => [qw( LeagueID Name Rosters Total_Players Start_Players Taxi_Slots Best_Ball Game_Against_Median Trade_Deadline Old_League QB RB WR TE FLEX SUPER_FLEX K DEF DL LB DB IDP_FLEX BN Pass_Yards Pass_TD Pass_Int Pass_Int_TD Pass_Sack Pass_2pt Pass_First_Down Pass_Att Pass_Inc Pass_Cmp Pass_Cmp_40p Pass_TD_40p Pass_TD_50p Bonus_Pass_cmp_25 Bonus_Pass_Yards_300 Bonus_Pass_Yards_400 Rec_Yards Rec_TD Rec_Bonus Bonus_Rec_RB Bonus_Rec_WR Bonus_Rec_TE Rec_2pt Rec_FD Rec_0_4 Rec_5_9 Rec_10_19 Rec_20_29 Rec_30_39 Rec_40p Rec_TD_40p Rec_TD_50p Bonus_Rec_Yards_100 Bonus_Rec_Yards_200 Rush_Yards Rush_TD Rush_Att Rush_FD Rush_2pt Rush_40p Rush_TD_40p Rush_TD_50p Bonus_Rush_Att_20 Bonus_Rush_Rec_Yards_100 Bonus_Rush_Rec_Yards_200 Bonus_Rush_Yards_100 Bonus_Rush_Yards_200 Fumble Fumble_Lost )], in => $dbh->selectall_arrayref ("SELECT LeagueID,name,total_rosters,total_players,total_players - roster_positions_BN AS start_players,taxi_slots,best_ball,league_average_match,trade_deadline,previous_league_id,roster_positions_QB,roster_positions_RB,roster_positions_WR,roster_positions_TE,roster_positions_FLEX,roster_positions_SUPER_FLEX,roster_positions_K,roster_positions_DEF,roster_positions_DL,roster_positions_LB,roster_positions_DB,roster_positions_IDP_FLEX,roster_positions_BN,pass_yd,pass_td,pass_int,pass_int_td,pass_sack,pass_2pt,pass_fd,pass_att,pass_inc,pass_cmp,pass_cmp_40p,pass_td_40p,pass_td_50p,bonus_pass_cmp_25,bonus_pass_yd_300,bonus_pass_yd_400,rec_yd,rec_td,rec_bonus,bonus_rec_rb,bonus_rec_wr,bonus_rec_te,rec_2pt,rec_fd,rec_0_4,rec_5_9,rec_10_19,rec_20_29,rec_30_39,rec_40p,rec_td_40p,rec_td_50p,bonus_rec_yd_100,bonus_rec_yd_200,rush_yd,rush_td,rush_att,rush_fd,rush_2pt,rush_40p,rush_td_40p,rush_td_50p,bonus_rush_att_20,bonus_rush_rec_yd_100,bonus_rush_rec_yd_200,bonus_rush_yd_100,bonus_rush_yd_200,fum,fum_lost FROM Leagues_2022"));
  csv (out => "${gitrepodir}/Trades_2022.csv", sep_char => ";", headers => [qw( Trade_ID Time Day Items1 Items2 All_Items Items1_Owner Items2_Owner League_ID Total_Rosters Total_Players Start_Players Rec_Bonus Rec_Bonus_TE Pass_TD Old_League_ID )], in => $dbh->selectall_arrayref ("SELECT t.TradeID, t.Time,(t.Time/86400000)+25569 AS 'Day', t.Items1, t.Items2,CONCAT(t.Items1,'; ',t.Items2) AS AllItems, t.Items1Owner, t.Items2Owner, t.League, l.total_rosters, l.total_players, l.total_players - roster_positions_BN AS Start_Players, l.rec_bonus, l.bonus_rec_te, l.pass_td, l.previous_league_id FROM Trades_2022 t INNER JOIN Leagues_2022 l ON t.League = l.LeagueID ORDER BY t.Time DESC"));
  csv (out => "${gitrepodir}/PickTrades_2022.csv", sep_char => ";", headers => [qw( Trade_ID Time Day Items1 Items2 All_Items Items1_Owner Items2_Owner League_ID Draft_Rounds Total_Rosters Total_Players Start_Players Rec_Bonus Rec_Bonus_TE Pass_TD )], in => $dbh->selectall_arrayref ("SELECT p.TradeID,p.Time,(p.time/86400000)+25569 AS 'Day',p.Items1,p.Items2,CONCAT(p.Items1,'; ',p.Items2) AS AllItems,p.Items1Owner,p.Items2Owner,p.League,p.DraftRounds,l.total_rosters,l.total_players,l.total_players - roster_positions_BN AS Start_Players,l.rec_bonus,l.bonus_rec_te,l.pass_td FROM PickTrades_2022 p INNER JOIN Leagues_2022 l ON p.League = l.LeagueID ORDER BY p.Time DESC"));
  csv (out => "${gitrepodir}/KtcValues.csv", sep_char => ",", headers => [qw( Player_ID Sleeper_ID Player_Name Value)], in => $dbh->selectall_arrayref ("SELECT k.player_id,k.sleeper_id,k.player_name,k.value FROM KeepTradeCut k ORDER BY k.value DESC"));
  csv (out => "${gitrepodir}/DevyKtcValues.csv", sep_char => ",", headers => [qw( Player_ID Player_Name Value)], in => $dbh->selectall_arrayref ("SELECT k.player_id,k.player_name,k.value FROM DevyKeepTradeCut k ORDER BY k.value DESC"));
  csv (out => "${gitrepodir}/TradeCount_2022.csv", sep_char => ";", headers => [qw( Sleeper_ID ADP Player_Name Last_Month Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec All_Year )], in => $dbh->selectall_arrayref ("SELECT t.PlayerID,t.ADP,t.PlayerName,t.LastM,t.s${season}01,t.s${season}02,t.s${season}03,t.s${season}04,t.s${season}05,t.s${season}06,t.s${season}07,t.s${season}08,t.s${season}09,t.s${season}10,t.s${season}11,t.s${season}12,t.s${season} FROM TradeStats_2022 t ORDER BY -ADP DESC"));

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
  logtofile("Exported the CSV files");
}

sub export_sleeperplayers { # Get the Sleeper Player Ids in the MySQLDB
  if(!(prompt_yn("Do you want to continue"))){
    print "Ok, exiting the player database update.\n";
    exit;
  }
  my $playersjson = get_json("https://api.sleeper.app/v1/players/nfl") or die;
  my $sth = $dbh->prepare(qq/TRUNCATE TABLE Players;/);
  $sth->execute();
  $sth->finish;
  verb("Truncated table PlayersTest");
  my $progressPlayers = Term::ProgressBar->new({name  => 'Adding Players', count => scalar(keys(%$playersjson)), ETA   => 'linear', remove => 1});
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
  logtofile("Updated the DB with ".scalar(keys(%$playersjson))." Sleeper Players");
}

sub get_ktcjsonvalues{
  my $url = "https://keeptradecut.com/dynasty-rankings/?page=0&filters=QB|WR|RB|TE|RDP&format=2";
  my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $header = HTTP::Request->new(GET => $url);
  $header->header(accept => "text/html;");
  my $request = HTTP::Request->new('GET', $url, $header);
  my $response = $ua->request($request);
  if (!($response->is_success)){
      print "CRITICAL: Error: $url\n";
      verb($response->error_as_HTML);
      return;
  }
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($response->content);
  for ($tree->find_by_tag_name('script')) {
    my $scripttext = $_->as_HTML;
    if ($scripttext =~ /var playersArray =/) {
      my @lines = split /\n/, $scripttext;
      foreach my $line( @lines ) {
        if ($line =~ /var playersArray =/){
          $line =~  s/^.*var playersArray = //g;
          $line =~  s/;$//g;
          return $line;
        }
      }
    }
  }
}

sub get_ktcdevyjsonvalues{
  my $url = "https://keeptradecut.com/devy-rankings/?page=0&filters=QB|WR|RB|TE&format=2";
  my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  my $header = HTTP::Request->new(GET => $url);
  $header->header(accept => "text/html;");
  my $request = HTTP::Request->new('GET', $url, $header);
  my $response = $ua->request($request);
  if (!($response->is_success)){
      print "CRITICAL: Error: $url\n";
      verb($response->error_as_HTML);
      return;
  }
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($response->content);
  for ($tree->find_by_tag_name('script')) {
    my $scripttext = $_->as_HTML;
    if ($scripttext =~ /var playersArray =/) {
      my @lines = split /\n/, $scripttext;
      foreach my $line( @lines ) {
        if ($line =~ /var playersArray =/){
          $line =~  s/^.*var playersArray = //g;
          $line =~  s/;$//g;
          return $line;
        }
      }
    }
  }
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
    return();
  }
}

sub printtofile{ # Print text to file (not appending!!)
  my $filename = $_[0];
  my $text = $_[1];
  print "${text}" unless (!$o_verb);
  open(my $fh, '>', $filename);
  print $fh "${text}";
  close $fh;
}

sub appendtofile{ # Append text to file
  my $filename = $_[0];
  my $text = $_[1];
  print "${text}" unless (!$o_verb);
  open(my $fh, '>>', $filename);
  print $fh "${text}\n";
  close $fh;
}

sub logtofile {
  my $t=shift;
  verb($t);
  if(defined($o_log)) {
    open(my $FH, ">>", $logfile) or die "Can't open logfile $logfile ", $!;
    my $logline = time_now()." $t\n";
    print $FH $logline;
    close($FH);
  }
}

sub time_now {
  my ($sec,$min,$hour,$month_day,$month,$year,$wday,$yday,$isdst) = localtime(time);
  my $time_string = sprintf("%02d-%02d-%02d %02d:%02d:%02d", $month_day, $month+1, $year+1900, $hour, $min, $sec);
  return $time_string;
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

sub verb { # Verbose print
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
      'h'     => \$o_help,              'help'                => \$o_help,
      'm:i'   => \$o_maxleagues,        'maxleagues:i'        => \$o_maxleagues,
      'r:i'   => \$o_refreshage,        'refreshage:i'        => \$o_refreshage,
      'w:i'   => \$o_currentweek,       'currentweek:i'       => \$o_currentweek,
      's:s'   => \$o_searchleagues,     'searchleagues:s'     => \$o_searchleagues,
      'S:s'   => \$o_expandusersearch,  'searchleaguesexp:s'  => \$o_expandusersearch,
      'n:i'   => \$o_newleaguesAge,     'newleaguesage:i'     => \$o_newleaguesAge,
      'd'     => \$o_updatedb,          'updateplayerdb'      => \$o_updatedb,
      'i'     => \$o_leagueinfo,        'leagueinfo'          => \$o_leagueinfo,
      'I'     => \$o_rosteridinfo,      'rosteridinfo'        => \$o_rosteridinfo,
      't'     => \$o_tradevalueslm,     'tradevalueslm'       => \$o_tradevalueslm,
      'T'     => \$o_tradevalues,       'tradevalues'         => \$o_tradevalues,
      'a'     => \$o_updateadp,         'updateadp'           => \$o_updateadp,
      'k'     => \$o_ktc,               'ktcvalues'           => \$o_ktc,
      'e'     => \$o_export,            'export'              => \$o_export,
      'u'     => \$o_updatetrades,      'updatetrades'        => \$o_updatetrades,
      'l'     => \$o_log,               'log'                 => \$o_log,
      'v'     => \$o_verb,              'verbose'             => \$o_verb,
      'V'     => \$o_debugverb,         'debugverbose'        => \$o_debugverb
  );
  help() if(defined($o_help));
  $o_verb = 1 if (defined($o_debugverb));
  $o_searchleagues = $o_expandusersearch if (defined($o_expandusersearch));
  $o_searchleagues = "DBList" if (defined($o_newleaguesAge));
  help() if (!((defined($o_searchleagues))||(defined($o_updatedb))||(defined($o_newleaguesAge))||(defined($o_leagueinfo))||(defined($o_rosteridinfo))||(defined($o_export))||(defined($o_tradevalueslm))||(defined($o_updateadp))||(defined($o_tradevalues))||(defined($o_ktc))||(defined($o_updatetrades))));
}

sub print_usage {
  print "Usage: $0 [-s <USERMANE>] [-S <USERNAME>] [-m <INT>] [-r <DAYS>] [-w <WEEK>] [-u] [-t] [-T] [-i] [-I] [-a] [-e]  [-v] [-V] [-h]\n";
}

sub help {
  print "Search Sleeper Trades $0\n";
  print_usage();
  print <<EOT;
-s, --searchleagues <S>
    Username to find new leagues that he and his teammates are in.
-S, --searchleaguesexp <S>
    Username to find new leagues that he and his teammates are in Expanded to already added leagues.
-m, --maxleagues <I>
    Max number of leagues to update (to throttle) (default 5).
-r, --refreshage <I>
    How Fresh has to be the data to refresh (default 2 Days).
-w, --currentweek <I>
    Week to update transactions. (if not defined it gets the one reported from the sleeper API).
-u, --updatetrades
    Update the trades from the leagues that hasn't updated in the last refreshage days.
-t, --tradevalueslm
    Update the Trade Count values of all the players in the DB from Last Month.
-T, --tradevalues
    Update the Trade Count values of all the players in the DB.
-i, --leagueinfo
    Update the settings of the Leagues that have no info.
-I, --rosteridinfo
    Update the RosterID settings of the Leagues that have no roster info.
-a, --updateadp
    Update the ADP from the Google Sheet ADP.
-k, --ktcvalues
    Update the KTC values from the website.
-e, --export
    Export CSV from tables and commit to git repository.
-d, --updateplayerdb
    Export the Sleeper PlayerDB to the MySQL.
-v, --verbose
    Verbose mode.
-V, --debugverbose
    Verbose Mode for Debugging (Much more verbose).
-h, --help
    Print this help message.
EOT
exit 0;
}
