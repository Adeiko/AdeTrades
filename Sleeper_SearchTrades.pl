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
use Data::Dumper;
use DBI;

my ($o_help,$o_verb,$o_player,$o_update,$o_timefilter,$o_newleagues,$o_leagueinfo);
my ($tradedb,$translist,$leaguehashlist,$players1,$players2,$players3);
my (@LeagueList,@playerstemp,@LeagueSearchList,@UserSearchList,@LeagueNameList);
my %dlist;

my $sport = "nfl";
my $season = "2021";
my $o_maxleagues = 50;
my $o_refreshage = 5;
my $o_currentweek = 1;

my $database =          "XXXXX";
my $database_hostname = "XXXXX";
my $database_port =     "XXXXX";
my $database_user =     "XXXXX";
my $database_password = "XXXXX";

check_options();

my $dtnow = DateTime->now()->epoch();
my $dtold = DateTime->now()->subtract(days => $o_refreshage)->epoch();

my $dbh = DBI->connect("DBI:mysql:database=$database;host=$database_hostname;port=$database_port", $database_user, $database_password,{PrintError => 1, RaiseError => 1}) || die  "ERROR: Error de conexion a la BBDD ${database_hostname}:${database_port} - ${database}\n";;

search_trade($o_player) if (defined($o_player));

if ($o_newleagues){
  $leaguehashlist = $dbh->selectall_hashref ("SELECT LeagueID FROM Leagues","LeagueID");
  my $newleagueuser = get_userid($o_newleagues);
  get_leagues($newleagueuser);
  foreach my $leaguesearch ( @LeagueSearchList ) { #For each league, get all users in those leagues
    next if (exists($leaguehashlist->{$leaguesearch}));
    get_leagueusers($leaguesearch);
  }
  foreach my $useritem (@UserSearchList){ #For each user in one of those leagues gets their leagues
    get_leagues($useritem);
  }
  foreach my $newleague ( @LeagueSearchList ) {
    next if (exists($leaguehashlist->{$newleague}));
    verb ("$newleague");
    insert_newleague($newleague);
  }
}

if ($o_update){
  $translist = $dbh->selectall_hashref ("SELECT TradeID FROM Trades","TradeID");
  get_leaguelist($o_maxleagues);
  foreach my $leagueN (@LeagueList){
    get_trades($leagueN,$o_currentweek);
  }
  insert_tradeHash();
}

if ($o_leagueinfo){
  get_leaguelistUpdateInfo($o_maxleagues);
  foreach my $leagueU (@LeagueNameList){
    get_leagueinfo($leagueU);
  }
}

exit;

sub get_leaguelistUpdateInfo{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT LeagueID FROM Leagues WHERE pass_td IS NULL LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueNameList,$row->{LeagueID};
  }
  $sth->finish;
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
    print $league_response->error_as_HTML;
  }
  my $leaguejson = decode_json($league_json_string);
  my ($league_name,$league_total_rosters,$league_taxi_slots,$league_rec,$league_bonus_rec_wr,$league_bonus_rec_te,$league_bonus_rec_rb,$league_pass_td,$league_pass_int);
  if (exists($leaguejson->{name})){ $league_name = $leaguejson->{name} }else{ $league_name = "NoName" };
  if (exists($leaguejson->{total_rosters})){  $league_total_rosters =$leaguejson->{total_rosters} }else{ $league_total_rosters = 0 };
  if (exists($leaguejson->{settings}->{taxi_slots})){ $league_taxi_slots = $leaguejson->{settings}->{taxi_slots} }else{ $league_taxi_slots = 0 };
  if (exists($leaguejson->{scoring_settings}->{rec})){ $league_rec = $leaguejson->{scoring_settings}->{rec} }else{ $league_rec = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_wr})){ $league_bonus_rec_wr = $leaguejson->{scoring_settings}->{bonus_rec_wr} }else{ $league_bonus_rec_wr = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_te})){ $league_bonus_rec_te = $leaguejson->{scoring_settings}->{bonus_rec_te} }else{ $league_bonus_rec_te = 0 };
  if (exists($leaguejson->{scoring_settings}->{bonus_rec_rb})){ $league_bonus_rec_rb = $leaguejson->{scoring_settings}->{bonus_rec_rb} }else{ $league_bonus_rec_rb = 0 };
  if (exists($leaguejson->{scoring_settings}->{pass_td})){ $league_pass_td = $leaguejson->{scoring_settings}->{pass_td} }else{ $league_pass_td = 0 };
  if (exists($leaguejson->{scoring_settings}->{pass_int})){ $league_pass_int = $leaguejson->{scoring_settings}->{pass_int} }else{ $league_pass_int = 0 };
  my $Positions_QB = grep { $_ eq "QB" } @{ $leaguejson->{roster_positions} };
  my $Positions_RB = grep { $_ eq "RB" } @{ $leaguejson->{roster_positions} };
  my $Positions_WR = grep { $_ eq "WR" } @{ $leaguejson->{roster_positions} };
  my $Positions_TE = grep { $_ eq "TE" } @{ $leaguejson->{roster_positions} };
  my $Positions_FLEX = grep { $_ eq "FLEX" or $_ eq "REC_FLEX"} @{ $leaguejson->{roster_positions} };
  my $Positions_SUPER_FLEX = grep { $_ eq "SUPER_FLEX" } @{ $leaguejson->{roster_positions} };
  my $Positions_BN = grep { $_ eq "BN" } @{ $leaguejson->{roster_positions} };
  my $total_players = $Positions_QB + $Positions_RB + $Positions_WR + $Positions_TE + $Positions_FLEX + $Positions_SUPER_FLEX + $Positions_BN;
  my $query = qq/UPDATE Leagues SET name = "$league_name", total_rosters = $league_total_rosters, taxi_slots = $league_taxi_slots, rec_bonus = $league_rec, bonus_rec_wr = $league_bonus_rec_wr, bonus_rec_te = $league_bonus_rec_te, bonus_rec_rb = $league_bonus_rec_rb, pass_td = $league_pass_td, pass_int = $league_pass_int, roster_positions_QB = $Positions_QB, roster_positions_RB = $Positions_RB, roster_positions_WR = $Positions_WR, roster_positions_TE = $Positions_TE, roster_positions_FLEX = $Positions_FLEX, roster_positions_SUPER_FLEX = $Positions_SUPER_FLEX, roster_positions_BN = $Positions_BN, total_players = $total_players WHERE LeagueID = $league_id;/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  $sth->finish;
  verb ("League $league_id");
  verb ("league_name: $league_name");
  verb ("league_total_rosters: $league_total_rosters");
  verb ("league_taxi_slots: $league_taxi_slots");
  verb ("league_rec: $league_rec");
  verb ("league_bonus_rec_wr: $league_bonus_rec_wr");
  verb ("league_bonus_rec_te: $league_bonus_rec_te");
  verb ("league_bonus_rec_rb: $league_bonus_rec_rb");
  verb ("league_pass_td: $league_pass_td");
  verb ("league_pass_int: $league_pass_int");
  verb ("Positions_QB: $Positions_QB");
  verb ("Positions_RB: $Positions_RB");
  verb ("Positions_WR: $Positions_WR");
  verb ("Positions_TE: $Positions_TE");
  verb ("Positions_FLEX: $Positions_FLEX");
  verb ("Positions_SUPER_FLEX: $Positions_SUPER_FLEX");
  verb ("Positions_BN: $Positions_BN");
  verb ("total_players: $total_players");
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
            if (!defined $players1){$players1 =  join("; ",@playerstemp)}elsif(!defined $players2){$players2 =  join("; ",@playerstemp)}else{$players3 =  join("; ",@playerstemp);
            }
            @playerstemp = ();
          }
        }
        verb("League: $leaguehash Transaction $transhash Time $$tradedb{$leaguehash}->{$transhash}->{date}");
        verb ("Players1: $players1") if defined($players1);
        verb ("Players2: $players2") if defined($players2);
        verb ("Players3: $players3") if defined($players3);
        insert_newtrade($transhash,$leaguehash,$tradedb->{$leaguehash}->{$transhash}->{date},$players1,$players2,$players3);
        ($players1,$players2,$players3,) = undef;
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
        if (exists( $draftjson->{slot_to_roster_id})){
          foreach my $slots( $draftjson->{slot_to_roster_id} ) {
            for my $slot (keys(%$slots)) {
              $tradedb->{$league_id}->{slots}->{$slots->{$slot}} = $slot unless ($slot eq '' );
            }
          }
        }else{
          $tradedb->{$league_id}->{slots} = "0";
        }
        return;
      }
    }
  }
  return;
}

sub search_trade{ # Searches for String in the Trade Database
  my $splayer = shift;
  print "Searching for $splayer\n\n";
  my $timefilter = "";
  if (defined($o_timefilter)) {
    my $dtfilter = DateTime->now()->subtract(days => $o_timefilter)->epoch();
    $timefilter = "Time > ${dtfilter}000 AND";
  }
  my $query = qq/
  SELECT
    Items1,
    Items2,
    from_unixtime(Time\/1000),
    League
  FROM
    Trades
  WHERE
    $timefilter
    (Items1 LIKE '%$splayer%' OR Items2 LIKE '%$splayer%')
  ORDER BY Time DESC
  LIMIT 10
  /;
  my $sth = $dbh->prepare($query);
  $sth->execute();

  while(my $row = $sth->fetchrow_hashref) {
    print "Trade on $row->{'from_unixtime(Time/1000)'} on league $row->{League}\n";
    print "User 1: \n   ".join("\n   ",split('; ',$row->{Items1}))."\n";
    print "User 2: \n   ".join("\n   ",split('; ',$row->{Items2}))."\n\n";
  }
  $sth->finish;
}

sub get_player{ # Gets the Player String from Sleeper_ID
  my $splayer_id = shift;
  return unless (looks_like_number($splayer_id));
  my $query = qq/SELECT first_name,last_name,fantasy_positions,team FROM Players WHERE player_id=$splayer_id/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  my ($qfname,$qlname,$qpos,$qteam) = $sth->fetchrow;
  $sth->finish;
  return "$qfname $qlname,$qpos,$qteam";
}

sub get_leaguelist{ #Get the LeagueList from the MySQL
  my $leaguelimit = shift;
  my $query = qq/SELECT LeagueID FROM Leagues WHERE LastUpdate < $dtold OR LastUpdate IS NULL LIMIT $leaguelimit/;
  my $sth = $dbh->prepare($query);
  $sth->execute();
  while(my $row = $sth->fetchrow_hashref) {
    push @LeagueList,$row->{LeagueID};
  }
  $sth->finish;
}

sub get_trades { #Get All trades from a League
  my $league_id = shift;
  my $WeekID = shift;
  my $league_json_string = undef;
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
    print $league_response->error_as_HTML;
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
          push @{$tradedb->{$league_id}->{$trade->{transaction_id}}->{$tradetadds->{$keyadd}}}, get_player($keyadd);
        }
      }
    }
    if (defined($trade->{draft_picks})){
      foreach my $tradetpicks( $trade->{draft_picks} ) {
        for my $keypicks (@$tradetpicks) {
          my $picktext = undef;
          if ($keypicks->{season} eq $season){
            if (!exists($tradedb->{$league_id}->{slots})){
              get_LeagueDrafts($league_id);
            }
            if (exists($tradedb->{$league_id}->{slots}->{$keypicks->{roster_id}})){
              $picktext = "$keypicks->{season}-$keypicks->{round}.$tradedb->{$league_id}->{slots}->{$keypicks->{roster_id}}";
            }else{
              $picktext = "$keypicks->{season}-$keypicks->{round}";
            }
          }else{
            $picktext = "$keypicks->{season}-$keypicks->{round}";
          }
          push @{$tradedb->{$league_id}->{$trade->{transaction_id}}->{$keypicks->{owner_id}}}, $picktext;
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

sub insert_newtrade{ #Inserts one Trades into MySQL
  my $transactions_id = shift;
  my $league_id = shift;
  my $trans_time = shift;
  my $items1 = shift;
  my $items2 = shift;
  my $items3 = shift;
  my $dbst = $dbh->prepare(
    q{
      INSERT INTO Trades
        (TradeID,League,Time,Items1,Items2,Items3)
      VALUES
        (?,?,?,?,?,?)
    }, {},
  );
  $dbst->execute($transactions_id, $league_id, $trans_time, $items1, $items2, $items3)or die $dbst->errstr; # TODO MIRAR DE MEJORAR EL ERROR
  $dbst->finish;
}

sub insert_newleague{ # Adds a new League to the list
  my $new_league = shift;
  my $sth = $dbh->prepare(q{INSERT IGNORE INTO Leagues(LeagueID) VALUES (?)},{},);
  $sth->execute($new_league);
  $sth->finish;
  verb("Inserting ${new_league}");
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
    print $league_response->error_as_HTML;
  }
  my $leaguejson = decode_json($league_json_string);
  foreach my $leagueitem ( @$leaguejson ) {
    next unless (ref($leagueitem->{roster_positions}) eq 'ARRAY' and grep { $_ eq "SUPER_FLEX" } @{ $leagueitem->{roster_positions} }); #Revisa que las ligas sean Superflex
    next unless ($leagueitem->{settings}->{type} == 2); # Revisa que las ligas sean Dynasty
    next unless ($leagueitem->{settings}->{num_teams} == 12); # Revisa que tengan 12 equipos
    push(@LeagueSearchList, $leagueitem->{league_id});
    verb("Añadiendo liga $leagueitem->{league_id}");
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
    print $league_response->error_as_HTML;
  }
  my $leaguejson = decode_json($league_json_string);
  foreach my $leagueuser ( @$leaguejson ) {
    push(@UserSearchList, $leagueuser->{"user_id"});
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
    print $user_response->error_as_HTML;
  }
  my $userjson = decode_json($user_json_string);
  return $userjson->{"user_id"};
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
      'h'     => \$o_help,            'help'            => \$o_help,
      'm:i'   => \$o_maxleagues,      'maxleagues:i'    => \$o_maxleagues,
      'r:i'   => \$o_refreshage,      'refreshage:i'    => \$o_refreshage,
      'p:s'   => \$o_player,          'player:s'        => \$o_player,
      'n:s'   => \$o_newleagues,      'newleagues:s'    => \$o_newleagues,
      'f:i'   => \$o_timefilter,      'timefilter:i'    => \$o_timefilter,
      'w:i'   => \$o_currentweek,     'currentweek:i'   => \$o_currentweek,
      'i'     => \$o_leagueinfo,      'leagueinfo'      => \$o_leagueinfo,
      'u'     => \$o_update,          'update'          => \$o_update,
      'v'     => \$o_verb,            'verbose'         => \$o_verb
  );
  if(defined($o_help)) {
    help();
    exit 0;
  }
  if ($o_update and $o_player){
    print "You must choose only one option -u or -p";
    help();
    exit 0;
  }
}

sub verb {
    my $t=shift;
    print STDOUT $t,"\n" if defined($o_verb);
}

sub print_usage {
  print "Usage: $0  [-n <USERMANE>] [-m <INT>] [-r <DAYS>] [-p <PlayerName>] [-f <DAYS>] [-w <WEEK>] [-i] [-u]  [-v] [-h]\n";
}

sub help {
  print "\nSearch Sleeper Trades $0\n";
  print_usage();
  print <<EOT;
-h, --help
    Print this help message
-u, --update
    Mode to Update
-n, --newleagues <S>
    Username to find new leagues that he and his teammates are in
-m, --maxleagues <I>
    Max number of leagues to update (to throttle) (default 5)
-r, --refreshage <I>
    How Fresh has to be the data to refresh (default 5 Days)
-p, --player <S>
    Search for trades involving <S>
-i, --leagueinfo
    Update the info of the Leagues in the MySQL
-f, --timefilter <I>
    Filter only deals made in the last <I> days
-w, --currentweek <I>
    Week to update transactions
-v, --verbose
    Verbose mode.
EOT
}

