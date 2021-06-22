-- Sleeper.DraftsIgnored definition

CREATE TABLE `DraftsIgnored` (
  `DraftID` bigint(20) NOT NULL,
  `ScrapeDate` bigint(20) DEFAULT NULL,
  UNIQUE KEY `DraftsIgnored_DraftID_IDX` (`DraftID`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Draft Ignored for the SleeperADP Sheet';


-- Sleeper.IgnoredLeagues definition

CREATE TABLE `IgnoredLeagues` (
  `LeagueID` bigint(20) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Deleted Leagues or unusual Leagues';


-- Sleeper.KeepTradeCut definition

CREATE TABLE `KeepTradeCut` (
  `player_id` bigint(200) NOT NULL,
  `player_name` varchar(200) DEFAULT NULL,
  `position` varchar(10) DEFAULT NULL,
  `team` varchar(10) DEFAULT NULL,
  `sleeper_id` bigint(200) DEFAULT NULL,
  `value` bigint(200) DEFAULT NULL,
  UNIQUE KEY `KeepTradeCut_player_id_IDX` (`player_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KeepTradeCut Values';


-- Sleeper.Leagues definition

CREATE TABLE `Leagues` (
  `PossibleDeleted` tinyint(1) NOT NULL DEFAULT '0',
  `LeagueID` bigint(20) DEFAULT NULL,
  `LastUpdate` bigint(20) DEFAULT NULL,
  `RookieTimeUpdate` bigint(20) DEFAULT NULL,
  `name` varchar(100) DEFAULT NULL,
  `total_rosters` int(3) DEFAULT NULL,
  `roster_positions_QB` int(3) DEFAULT NULL,
  `roster_positions_RB` int(3) DEFAULT NULL,
  `roster_positions_WR` int(3) DEFAULT NULL,
  `roster_positions_TE` int(3) DEFAULT NULL,
  `roster_positions_FLEX` int(3) DEFAULT NULL,
  `roster_positions_SUPER_FLEX` int(3) DEFAULT NULL,
  `roster_positions_BN` int(3) DEFAULT NULL,
  `total_players` int(3) DEFAULT NULL,
  `taxi_slots` int(3) DEFAULT NULL,
  `pass_td` decimal(3,1) DEFAULT NULL,
  `rec_bonus` decimal(3,1) DEFAULT NULL,
  `bonus_rec_te` decimal(3,1) DEFAULT NULL,
  `bonus_rec_rb` decimal(3,1) DEFAULT NULL,
  `bonus_rec_wr` decimal(3,1) DEFAULT NULL,
  `pass_int` decimal(3,1) DEFAULT NULL,
  `trade_deadline` bigint(20) DEFAULT NULL,
  `RookieDraft` bigint(20) DEFAULT NULL,
  `RookieStatus` varchar(100) DEFAULT NULL,
  `RookieRounds` bigint(20) DEFAULT NULL,
  `previous_league_id` bigint(20) DEFAULT NULL,
  `roster_idp` tinyint(1) DEFAULT NULL,
  UNIQUE KEY `Leagues_LeagueID_IDX` (`LeagueID`) USING BTREE,
  KEY `Leagues_LastUpdate_IDX` (`LastUpdate`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Sleeper League List';


-- Sleeper.PickTrades definition

CREATE TABLE `PickTrades` (
  `TradeID` bigint(20) NOT NULL,
  `Time` bigint(20) DEFAULT NULL,
  `League` bigint(20) DEFAULT NULL,
  `Items1` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `Items2` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `Items3` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `DraftRounds` bigint(20) DEFAULT NULL,
  `Items1Owner` bigint(20) DEFAULT NULL,
  `Items2Owner` bigint(20) DEFAULT NULL,
  `Items3Owner` bigint(20) DEFAULT NULL,
  UNIQUE KEY `PickTrades_TradeID_IDX` (`TradeID`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Trades involving only Picks';


-- Sleeper.Players definition

CREATE TABLE `Players` (
  `player_id` int(20) DEFAULT NULL,
  `first_name` varchar(30) DEFAULT NULL,
  `last_name` varchar(30) DEFAULT NULL,
  `position` varchar(6) DEFAULT NULL,
  `team` varchar(10) DEFAULT NULL,
  `weight` int(20) DEFAULT NULL,
  `status` varchar(60) DEFAULT NULL,
  `sport` varchar(8) DEFAULT NULL,
  `fantasy_positions` varchar(6) DEFAULT NULL,
  `college` varchar(30) DEFAULT NULL,
  `practice_description` varchar(50) DEFAULT NULL,
  `rotowire_id` int(20) DEFAULT NULL,
  `active` varchar(10) DEFAULT NULL,
  `number` int(20) DEFAULT NULL,
  `height` varchar(10) DEFAULT NULL,
  `injury_status` varchar(20) DEFAULT NULL,
  `injury_body_part` varchar(20) DEFAULT NULL,
  `injury_notes` varchar(200) DEFAULT NULL,
  `practice_participation` varchar(200) DEFAULT NULL,
  `high_school` varchar(100) DEFAULT NULL,
  `sportradar_id` varchar(50) DEFAULT NULL,
  `yahoo_id` int(20) DEFAULT NULL,
  `years_exp` int(20) DEFAULT NULL,
  `fantasy_data_id` int(20) DEFAULT NULL,
  `hashtag` varchar(50) DEFAULT NULL,
  `search_last_name` varchar(30) DEFAULT NULL,
  `birth_city` varchar(30) DEFAULT NULL,
  `espn_id` int(20) DEFAULT NULL,
  `birth_date` varchar(20) DEFAULT NULL,
  `search_first_name` varchar(30) DEFAULT NULL,
  `birth_state` varchar(20) DEFAULT NULL,
  `gsis_id` varchar(20) DEFAULT NULL,
  `news_updated` double DEFAULT NULL,
  `birth_country` varchar(20) DEFAULT NULL,
  `search_full_name` varchar(50) DEFAULT NULL,
  `depth_chart_position` varchar(6) DEFAULT NULL,
  `rotoworld_id` int(20) DEFAULT NULL,
  `depth_chart_order` int(50) DEFAULT NULL,
  `injury_start_date` varchar(20) DEFAULT NULL,
  `stats_id` int(20) DEFAULT NULL,
  `search_rank` int(11) DEFAULT NULL,
  `pandascore_id` varchar(11) DEFAULT NULL,
  `metadata` varchar(200) DEFAULT NULL,
  `full_name` varchar(200) DEFAULT NULL,
  `age` int(11) DEFAULT NULL,
  UNIQUE KEY `Players_player_id_IDX` (`player_id`) USING BTREE,
  KEY `Players_first_name_IDX` (`first_name`,`last_name`,`fantasy_positions`,`team`,`player_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Sleeper Player Database';


-- Sleeper.RevertedTrades definition

CREATE TABLE `RevertedTrades` (
  `TradeID` bigint(20) DEFAULT NULL,
  UNIQUE KEY `RevertedTrades_TradeID_IDX` (`TradeID`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='List of trades that have wrong data (reverted/null etc...)';


-- Sleeper.RosterID_Reference definition

CREATE TABLE `RosterID_Reference` (
  `LeagueID` bigint(20) NOT NULL,
  `LastUpdate` bigint(20) DEFAULT NULL,
  `RosterID1` bigint(20) DEFAULT NULL,
  `RosterID2` bigint(20) DEFAULT NULL,
  `RosterID3` bigint(20) DEFAULT NULL,
  `RosterID4` bigint(20) DEFAULT NULL,
  `RosterID5` bigint(20) DEFAULT NULL,
  `RosterID6` bigint(20) DEFAULT NULL,
  `RosterID7` bigint(20) DEFAULT NULL,
  `RosterID8` bigint(20) DEFAULT NULL,
  `RosterID9` bigint(20) DEFAULT NULL,
  `RosterID10` bigint(20) DEFAULT NULL,
  `RosterID11` bigint(20) DEFAULT NULL,
  `RosterID12` bigint(20) DEFAULT NULL,
  `RosterID13` bigint(20) DEFAULT NULL,
  `RosterID14` bigint(20) DEFAULT NULL,
  UNIQUE KEY `RosterID_Reference_UN` (`LeagueID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='UserID to RosterID for each League Dictionary';


-- Sleeper.SearchedUsers definition

CREATE TABLE `SearchedUsers` (
  `UserID` bigint(20) DEFAULT NULL,
  `ScrapeDate` bigint(20) DEFAULT NULL,
  UNIQUE KEY `SearchedUsers_UserID_IDX` (`UserID`) USING BTREE,
  KEY `SearchedUsers_ScrapeDate_IDX` (`ScrapeDate`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='List of Users already Searched';


-- Sleeper.TradeStats definition

CREATE TABLE `TradeStats` (
  `PlayerID` bigint(20) NOT NULL,
  `PlayerName` varchar(200) DEFAULT NULL,
  `s2021` bigint(20) DEFAULT NULL,
  `LastCount` bigint(20) DEFAULT NULL,
  `s202101` bigint(20) DEFAULT NULL,
  `s202102` bigint(20) DEFAULT NULL,
  `s202103` bigint(20) DEFAULT NULL,
  `s202104` bigint(20) DEFAULT NULL,
  `s202105` bigint(20) DEFAULT NULL,
  `s202106` bigint(20) DEFAULT NULL,
  `s202107` bigint(20) DEFAULT NULL,
  `s202108` bigint(20) DEFAULT NULL,
  `s202109` bigint(20) DEFAULT NULL,
  `s202110` bigint(20) DEFAULT NULL,
  `s202111` bigint(20) DEFAULT NULL,
  `s202112` bigint(20) DEFAULT NULL,
  `LastM` bigint(20) DEFAULT NULL,
  `ADP` bigint(20) DEFAULT NULL,
  KEY `TradeStats_PlayerID_IDX` (`PlayerID`,`PlayerName`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Sum of each player Trade Count per month';


-- Sleeper.Trades definition

CREATE TABLE `Trades` (
  `TradeID` bigint(20) NOT NULL,
  `Time` bigint(20) DEFAULT NULL,
  `League` bigint(20) DEFAULT NULL,
  `Items1` varchar(2000) COLLATE utf8mb4_bin DEFAULT NULL,
  `Items2` varchar(2000) COLLATE utf8mb4_bin DEFAULT NULL,
  `Items3` varchar(2000) COLLATE utf8mb4_bin DEFAULT NULL,
  `DraftRounds` bigint(20) DEFAULT NULL,
  `Items1Owner` bigint(20) DEFAULT NULL,
  `Items2Owner` bigint(20) DEFAULT NULL,
  `Items3Owner` bigint(20) DEFAULT NULL,
  UNIQUE KEY `Trades_TradeID_IDX` (`TradeID`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT='Sleeper Trade History';


-- Sleeper.UserDraftsSearched definition

CREATE TABLE `UserDraftsSearched` (
  `UserID` bigint(20) NOT NULL,
  `ScrapeDateRookie` bigint(20) DEFAULT NULL,
  `ScrapeDateStartup` bigint(20) DEFAULT NULL,
  UNIQUE KEY `UserDraftsSearched_UN` (`UserID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SearchDraft already Scraped Users';