-- Sleeper.Sleeper definition
CREATE DATABASE `Sleeper` /*!40100 DEFAULT CHARACTER SET utf8mb4 */;

-- Sleeper.DevyKeepTradeCut definition

CREATE TABLE `DevyKeepTradeCut` (
  `player_id` bigint(200) NOT NULL,
  `player_name` varchar(200) DEFAULT NULL,
  `position` varchar(10) DEFAULT NULL,
  `team` varchar(10) DEFAULT NULL,
  `sleeper_id` bigint(200) DEFAULT NULL,
  `value` bigint(200) DEFAULT NULL,
  UNIQUE KEY `KeepTradeCut_player_id_IDX` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KeepTradeCut Values';

-- Sleeper.DraftsIgnored definition

CREATE TABLE `DraftsIgnored` (
  `DraftID` bigint(20) NOT NULL,
  `ScrapeDate` bigint(20) DEFAULT NULL,
  `DType` varchar(20) DEFAULT NULL,
  UNIQUE KEY `DraftsIgnored_UN` (`DraftID`,`DType`)
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

-- Sleeper.Leagues_2022 definition

CREATE TABLE `Leagues_2022` (
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
  `rec_bonus` decimal(3,2) DEFAULT NULL,
  `bonus_rec_te` decimal(3,2) DEFAULT NULL,
  `bonus_rec_rb` decimal(3,2) DEFAULT NULL,
  `bonus_rec_wr` decimal(3,2) DEFAULT NULL,
  `pass_int` decimal(3,1) DEFAULT NULL,
  `trade_deadline` bigint(20) DEFAULT NULL,
  `RookieDraft` bigint(20) DEFAULT NULL,
  `RookieStatus` varchar(100) DEFAULT NULL,
  `RookieRounds` bigint(20) DEFAULT NULL,
  `previous_league_id` bigint(20) DEFAULT NULL,
  `best_ball` bigint(20) DEFAULT NULL,
  `league_average_match` bigint(20) DEFAULT NULL,
  `sack` decimal(5,2) DEFAULT NULL,
  `roster_positions_DL` int(3) DEFAULT NULL,
  `roster_positions_LB` int(3) DEFAULT NULL,
  `roster_positions_DB` int(3) DEFAULT NULL,
  `roster_positions_IDP_FLEX` int(3) DEFAULT NULL,
  `roster_positions_K` int(3) DEFAULT NULL,
  `roster_positions_DEF` int(3) DEFAULT NULL,
  `bonus_pass_cmp_25` decimal(3,1) DEFAULT NULL,
  `bonus_pass_yd_300` decimal(3,1) DEFAULT NULL,
  `bonus_pass_yd_400` decimal(3,1) DEFAULT NULL,
  `bonus_rec_yd_100` decimal(3,1) DEFAULT NULL,
  `bonus_rec_yd_200` decimal(3,1) DEFAULT NULL,
  `bonus_rush_att_20` decimal(3,1) DEFAULT NULL,
  `bonus_rush_rec_yd_100` decimal(3,1) DEFAULT NULL,
  `bonus_rush_rec_yd_200` decimal(3,1) DEFAULT NULL,
  `bonus_rush_yd_100` decimal(3,1) DEFAULT NULL,
  `bonus_rush_yd_200` decimal(3,1) DEFAULT NULL,
  `fum` decimal(3,1) DEFAULT NULL,
  `fum_lost` decimal(3,1) DEFAULT NULL,
  `pass_2pt` decimal(3,1) DEFAULT NULL,
  `pass_att` decimal(4,2) DEFAULT NULL,
  `pass_cmp` decimal(4,2) DEFAULT NULL,
  `pass_cmp_40p` decimal(3,1) DEFAULT NULL,
  `pass_fd` decimal(3,1) DEFAULT NULL,
  `pass_inc` decimal(4,2) DEFAULT NULL,
  `pass_int_td` decimal(3,1) DEFAULT NULL,
  `pass_sack` decimal(3,1) DEFAULT NULL,
  `pass_td_40p` decimal(3,1) DEFAULT NULL,
  `pass_td_50p` decimal(3,1) DEFAULT NULL,
  `pass_yd` decimal(4,2) DEFAULT NULL,
  `rec_0_4` decimal(4,2) DEFAULT NULL,
  `rec_10_19` decimal(4,2) DEFAULT NULL,
  `rec_20_29` decimal(4,2) DEFAULT NULL,
  `rec_2pt` decimal(3,1) DEFAULT NULL,
  `rec_30_39` decimal(4,2) DEFAULT NULL,
  `rec_40p` decimal(3,1) DEFAULT NULL,
  `rec_5_9` decimal(4,2) DEFAULT NULL,
  `rec_fd` decimal(3,1) DEFAULT NULL,
  `rec_td` decimal(3,1) DEFAULT NULL,
  `rec_td_40p` decimal(3,1) DEFAULT NULL,
  `rec_td_50p` decimal(3,1) DEFAULT NULL,
  `rec_yd` decimal(4,2) DEFAULT NULL,
  `rush_2pt` decimal(3,1) DEFAULT NULL,
  `rush_40p` decimal(3,1) DEFAULT NULL,
  `rush_att` decimal(4,2) DEFAULT NULL,
  `rush_fd` decimal(4,2) DEFAULT NULL,
  `rush_td` decimal(3,1) DEFAULT NULL,
  `rush_td_40p` decimal(3,1) DEFAULT NULL,
  `rush_td_50p` decimal(3,1) DEFAULT NULL,
  `rush_yd` decimal(4,2) DEFAULT NULL,
  UNIQUE KEY `Leagues_LeagueID_IDX` (`LeagueID`),
  KEY `Leagues_LastUpdate_IDX` (`LastUpdate`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Sleeper League List 2022';

-- Sleeper.PickTrades_2022 definition

CREATE TABLE `PickTrades_2022` (
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
  UNIQUE KEY `PickTrades_TradeID_IDX` (`TradeID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Trades involving only Picks 2022';

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
  `LeagueCount` bigint(20) DEFAULT NULL,
  UNIQUE KEY `SearchedUsers_UserID_IDX` (`UserID`) USING BTREE,
  KEY `SearchedUsers_ScrapeDate_IDX` (`ScrapeDate`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='List of Users already Searched';

-- Sleeper.TradeStats_2022 definition

CREATE TABLE `TradeStats_2022` (
  `PlayerID` bigint(20) NOT NULL,
  `PlayerName` varchar(200) DEFAULT NULL,
  `s2022` bigint(20) DEFAULT NULL,
  `LastCount` bigint(20) DEFAULT NULL,
  `s202201` bigint(20) DEFAULT NULL,
  `s202202` bigint(20) DEFAULT NULL,
  `s202203` bigint(20) DEFAULT NULL,
  `s202204` bigint(20) DEFAULT NULL,
  `s202205` bigint(20) DEFAULT NULL,
  `s202206` bigint(20) DEFAULT NULL,
  `s202207` bigint(20) DEFAULT NULL,
  `s202208` bigint(20) DEFAULT NULL,
  `s202209` bigint(20) DEFAULT NULL,
  `s202210` bigint(20) DEFAULT NULL,
  `s202211` bigint(20) DEFAULT NULL,
  `s202212` bigint(20) DEFAULT NULL,
  `LastM` bigint(20) DEFAULT NULL,
  `ADP` bigint(20) DEFAULT NULL,
  KEY `TradeStats_PlayerID_IDX` (`PlayerID`,`PlayerName`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Sum of each player Trade Count per month 2022';

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

-- Sleeper.Trades_2022 definition

CREATE TABLE `Trades_2022` (
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
  UNIQUE KEY `Trades_TradeID_IDX` (`TradeID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT='Sleeper Trade History 2022';

-- Sleeper.UserDraftsSearched definition

CREATE TABLE `UserDraftsSearched` (
  `UserID` bigint(20) NOT NULL,
  `ScrapeDateRookie` bigint(20) DEFAULT NULL,
  `ScrapeDateStartup` bigint(20) DEFAULT NULL,
  UNIQUE KEY `UserDraftsSearched_UN` (`UserID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SearchDraft already Scraped Users';