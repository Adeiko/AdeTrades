library(nflfastR)
library(tidyverse)
library(dplyr)
library(data.table)
future::plan("multisession")
pbp_season = 2010:2021

options(scipen = 9999)
options(digits=2)
options(nflreadr.verbose = FALSE)

pbp <- nflfastR::load_pbp(pbp_season)%>%
  nflfastR::decode_player_ids()%>%
  nflfastR::add_xpass()

rosters <- data.table::as.data.table(nflfastR::fast_scraper_roster(pbp_season))
rosters <- rosters[!is.na(gsis_id), .N, by = "season,gsis_id,team,position"]
pbp <- data.table::as.data.table(pbp)
pbp <- pbp[rosters, recpos := i.position, on = .(receiver_id = gsis_id, season = season)]
pbp <- pbp[rosters, rushpos := i.position, on = .(rusher_id = gsis_id, season = season)]

pbp<- pbp %>%
  dplyr::filter(rush == 1 | pass == 1,qb_kneel==0,!is.na(epa),!is.na(posteam),season_type=="REG",!(play_type=="no_play"),dplyr::case_when(season==2021 ~ week<=17,T ~ week<=16))%>%
  dplyr::group_by(posteam,season)

team_data <- pbp %>%
  dplyr::summarize(
    #Plays
    Total_Plays = n(),
    Total_Plays_gp = round(Total_Plays/(max(week)-1),2),
    Total_Plays_Pass_per = round(sum(pass)/Total_Plays,2),
    Total_Plays_Rush_per = round(sum(rush)/Total_Plays,2),
    Total_Yards = sum(yards_gained[sack==0]),
    Total_Yards_gp = round(sum(yards_gained[sack==0])/(max(week)-1),2),
    Total_Yards_Rush_per = round(sum(rushing_yards[!is.na(rushing_yards)])/sum(yards_gained[sack==0]),2),
    Total_Yards_Pass_per = round(sum(passing_yards[!is.na(passing_yards)])/sum(yards_gained[sack==0]),2),
    Total_TD = sum(rush_touchdown,pass_touchdown),
    Total_TD_gp = round(sum(rush_touchdown,pass_touchdown)/(max(week)-1),2),
    Total_TD_Pass_per = round(sum(pass_touchdown)/sum(rush_touchdown,pass_touchdown),2),
    Total_TD_Rush_per = round(sum(rush_touchdown)/sum(rush_touchdown,pass_touchdown),2),
    Pass_Over_Expectation_Down_1_2 = round(mean(pass_oe[down<=2&!is.na(pass_oe)]),2)/100,
    Pass_Over_Expectation_Down_1_2_3 = round(mean(pass_oe[down=3&!is.na(pass_oe)]),2)/100,
    Pass_Over_Expectation_Neutral_Down_1_2_3 = round(mean(pass_oe[down=3&!is.na(pass_oe)&score_differential <= 3 & score_differential  <= 3]),2)/100,
    Pass_Over_Expectation = round(mean(pass_oe[down<=3&!is.na(pass_oe)]),2)/100,
    Total_Plays_Lead = sum(rush,pass[score_differential > 3]),
    Total_Plays_Lead_per = round(Total_Plays_Lead/Total_Plays,2),
    Rush_Plays_Lead = sum(rush[score_differential > 3]),
    Rush_Plays_Lead_per = round(Rush_Plays_Lead/Total_Plays_Lead,2),
    Pass_Plays_Lead = sum(pass[score_differential > 3]),
    Pass_Plays_Lead_per = round(Pass_Plays_Lead/Total_Plays_Lead,2),
    Total_Plays_Close = sum(rush,pass[score_differential <= 3 & score_differential  <= 3]),
    Total_Plays_Close_per = round(Total_Plays_Close/Total_Plays,2),
    Rush_Plays_Close = sum(rush[score_differential <= 3 & score_differential  <= 3]),
    Rush_Plays_Close_per = round(Rush_Plays_Close/Total_Plays_Close,2),
    Pass_Plays_Close = sum(pass[score_differential <= 3 & score_differential  <= 3]),
    Pass_Plays_Close_per = round(Pass_Plays_Close/Total_Plays_Close,2),
    Total_Plays_Trail = sum(rush,pass[score_differential < -3]),
    Total_Plays_Trail_per = round(Total_Plays_Trail/Total_Plays,2),
    Rush_Plays_Trail = sum(rush[score_differential < -3]),
    Rush_Plays_Trail_per = round(Rush_Plays_Trail/Total_Plays_Trail,2),
    Pass_Plays_Trail = sum(pass[score_differential < -3]),
    Pass_Plays_Trail_per = round(Pass_Plays_Trail/Total_Plays_Trail,2),
    #Passing
    Pass_Dropbacks = sum(pass),
    Pass_Dropbacks_gp = round(Pass_Dropbacks/(max(week)-1),2),
    Pass_Scrambles = sum(qb_scramble[!is.na(qb_scramble)]),
    Pass_Scrambles_gp = round(Pass_Scrambles/(max(week)-1),2),
    Pass_Yards_Scramble = sum(rushing_yards[qb_scramble==1&!is.na(rushing_yards)]),
    Pass_Yards_Scramble_gp = round(Pass_Yards_Scramble/(max(week)-1),2),
    Pass_Att = sum(pass_attempt),
    Pass_Att_gp = round(Pass_Att/(max(week)-1),2),
    Pass_Comp = sum(complete_pass),
    Pass_Comp_gp = round(Pass_Comp/(max(week)-1),2),
    Pass_Yards = sum(passing_yards[!is.na(passing_yards)]),
    Pass_Yards_gp = round(Pass_Yards/(max(week)-1),2),
    Pass_TD = sum(pass_touchdown),
    Pass_TD_gp = round(Pass_TD/(max(week)-1),2),
    Pass_AirYards = sum (air_yards[!is.na(air_yards)]),
    Pass_AirYards_gp = round(Pass_AirYards/(max(week)-1),2),
    Pass_CPOE = round(mean(cpoe[!is.na(cpoe)]),2)/100,
    Pass_Sacks = sum(sack),
    Pass_Sacks_gp = round(Pass_Sacks/(max(week)-1),2),
    Pass_Sack_Yards = sum(yards_gained[sack==1]),
    Pass_Sack_Yards_gp = round(Pass_Sack_Yards/(max(week)-1),2),
    Pass_throwaway = sum(pass[!is.na(air_yards)&air_yards==0]),
    Pass_throwaway_gp = round(sum(pass[!is.na(air_yards)&air_yards==0])/(max(week)-1),2),
    Pass_Throwaway_per = round(sum(pass[!is.na(air_yards)&air_yards==0])/sum(pass),2),
    #Rushing
    Rush_Att = sum(rush),
    Rush_Att_gp = round(Rush_Att/(max(week)-1),2),
    Rush_Yards = sum(rushing_yards[!is.na(rushing_yards)]),
    Rush_Yards_gp = round(Rush_Yards/(max(week)-1),2),
    Rush_TD = sum(rush_touchdown),
    Rush_TD_gp = round(Rush_TD/(max(week)-1),2),
    Rush_Att_QB = sum(rush_attempt[!is.na(rushpos)&rushpos=="QB"]),
    Rush_Att_QB_gp = round(Rush_Att_QB/(max(week)-1),2),
    Rush_Att_RB = sum(rush_attempt[!is.na(rushpos)&(rushpos=="RB"|rushpos=="FB")]),
    Rush_Att_RB_gp = round(Rush_Att_RB/(max(week)-1),2),
    Rush_Att_WR = sum(rush_attempt[!is.na(rushpos)&rushpos=="WR"]),
    Rush_Att_WR_gp = round(Rush_Att_WR/(max(week)-1),2),
    Rush_Att_TE = sum(rush_attempt[!is.na(rushpos)&rushpos=="TE"]),
    Rush_Att_TE_gp = round(Rush_Att_TE/(max(week)-1),2),
    Rush_TD_QB = sum(rush_touchdown[!is.na(rushpos)&rushpos=="QB"]),
    Rush_TD_QB_gp = round(Rush_TD_QB/(max(week)-1),2),
    Rush_TD_RB = sum(rush_touchdown[!is.na(rushpos)&(rushpos=="RB"|rushpos=="FB")]),
    Rush_TD_RB_gp = round(Rush_TD_RB/(max(week)-1),2),
    Rush_TD_WR = sum(rush_touchdown[!is.na(rushpos)&rushpos=="WR"]),
    Rush_TD_WR_gp = round(Rush_TD_WR/(max(week)-1),2),
    Rush_TD_TE = sum(rush_touchdown[!is.na(rushpos)&rushpos=="TE"]),
    Rush_TD_TE_gp = round(Rush_TD_TE/(max(week)-1),2),
    Rush_MS_QB = round(Rush_Att_QB/sum(rush_attempt),2),
    Rush_MS_RB = round(Rush_Att_RB/sum(rush_attempt),2),
    Rush_MS_WR = round(Rush_Att_WR/sum(rush_attempt),2),
    Rush_MS_TE = round(Rush_Att_TE/sum(rush_attempt),2),
    Rush_TD_MS_QB = round(Rush_TD_QB/sum(rush_touchdown),2),
    Rush_TD_MS_RB = round(Rush_TD_RB/sum(rush_touchdown),2),
    Rush_TD_MS_WR = round(Rush_TD_WR/sum(rush_touchdown),2),
    Rush_TD_MS_TE = round(Rush_TD_TE/sum(rush_touchdown),2),
    #Receptions
    Rec_YAC = sum(yards_after_catch[!is.na(yards_after_catch)]),
    Rec_YAC_gp = round(Rec_YAC/(max(week)-1),2),
    Rec_Tar = sum(pass_attempt)-sum(pass_attempt[!is.na(air_yards)&air_yards==0]),
    Rec_Tar_RB = sum(pass_attempt[!is.na(recpos)&(recpos=="RB"|recpos=="FB")]),
    Rec_Tar_RB_gp = round(Rec_Tar_RB/(max(week)-1),2),
    Rec_Rec_RB = sum(complete_pass[!is.na(recpos)&(recpos=="RB"|recpos=="FB")]),
    Rec_Rec_RB_gp = round(Rec_Rec_RB/(max(week)-1),2),
    Rec_TD_RB = sum(pass_touchdown[!is.na(recpos)&(recpos=="RB"|recpos=="FB")]),
    Rec_TD_RB_gp = round(Rec_TD_RB/(max(week)-1),2),
    Rec_Tar_WR = sum(pass_attempt[!is.na(recpos)&recpos=="WR"]),
    Rec_Tar_WR_gp = round(Rec_Tar_WR/(max(week)-1),2),
    Rec_Rec_WR = sum(complete_pass[!is.na(recpos)&recpos=="WR"]),
    Rec_Rec_WR_gp = round(Rec_Rec_WR/(max(week)-1),2),
    Rec_TD_WR = sum(pass_touchdown[!is.na(recpos)&recpos=="WR"]),
    Rec_TD_WR_gp = round(Rec_TD_WR/(max(week)-1),2),
    Rec_Tar_TE = sum(pass_attempt[!is.na(recpos)&recpos=="TE"]),
    Rec_Tar_TE_gp = round(Rec_Tar_TE/(max(week)-1),2),
    Rec_Rec_TE = sum(complete_pass[!is.na(recpos)&recpos=="TE"]),
    Rec_Rec_TE_gp = round(Rec_Rec_TE/(max(week)-1),2),
    Rec_TD_TE = sum(pass_touchdown[!is.na(recpos)&recpos=="TE"]),
    Rec_TD_TE_gp = round(Rec_TD_TE/(max(week)-1),2),
    Rec_MS_RB = round(Rec_Tar_RB/Rec_Tar,2),
    Rec_MS_WR = round(Rec_Tar_WR/Rec_Tar,2),
    Rec_MS_TE = round(Rec_Tar_TE/Rec_Tar,2),
    Rec_TD_MS_RB = round(Rec_TD_RB/sum(pass_touchdown),2),
    Rec_TD_MS_WR = round(Rec_TD_WR/sum(pass_touchdown),2),
    Rec_TD_MS_TE = round(Rec_TD_TE/sum(pass_touchdown),2),
    #Formation
    Pass_Shotgun = sum(shotgun[pass==1]),
    Pass_Shotgun = round(Pass_Shotgun/(max(week)-1),2),
    Rush_Shotgun = sum(shotgun[rush==1]),
    Rush_Shotgun = round(Rush_Shotgun/(max(week)-1),2),
    Pass_Pistol = Pass_Dropbacks-Pass_Shotgun,
    Pass_Pistol = round(Pass_Pistol/(max(week)-1),2),
    Rush_Pistol = Rush_Att-Rush_Shotgun,
    Rush_Pistol = round(Rush_Pistol/(max(week)-1),2)
  )

write.csv(team_data,paste0("TeamData.csv"), row.names = FALSE)
