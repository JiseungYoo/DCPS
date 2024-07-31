# Header ---- 
#
# Script name: 
#
# Purpose of script:
#
# Author: Max Anthenelli
#
# Date Created: 2024-01-29
# Updated: 2024-02-05
#  This code is free for anyone to use
# Email: anthenem@gmail.com
#
## set working directory ----
# working_directory <- file.path("C:", "Users", "Max", "Box", 
#                                "DCPS-SERP Data Internal 2019")

working_directory <- file.path("~","Library", "CloudStorage", "Box-Box",
                               "DCPS-SERP Data Internal 2019")

setwd(working_directory)

## choose required packages ----
c("tidyverse", "magrittr", "rlang", "glue",
  "haven", "labelled", "readxl"
) |>
  purrr::walk(~require(.x, character.only = TRUE))

# Body ----



## import data ----
excel_file <- file.path( working_directory, 
                         "Student Data through SY22-23 Updated.xlsx") 
demog_student.year <-
  read_excel(excel_file, sheet = "Demographic")

enrollment_student.school.year <- 
  read_excel(excel_file, sheet = "Enrollment and Attendance")

courses_student.school.year <-   
  map(map_vec(c(19:22), ~glue("Courses SY{.x}-{.x+1}")),
      ~excel_file %>% read_excel(sheet = .x)) %>% 
  list_rbind()

tests_student.year <- 
  read_excel(excel_file, sheet = "PARCC")

assessments_student.year <-
  read_excel(excel_file, sheet = "Formative Assessments") %>% 
  filter(Assessment_Type %in% c("DIBELS", "RI", "TRC")) 



## Determine Primary Teacher ----
mode_stat <- function(x, na.rm = TRUE) {
  if(na.rm) x = x[!is.na(x)]
  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}

primary_teacher <- 
  courses_student.school.year %>% 
  group_by(StudentID, Grade, School, courses_sy_start) %>%
  mutate(Employee_Number = ifelse(any(Subject_Code == "EE"),
                                  mode_stat(Employee_Number[Subject_Code == "EE"]), Employee_Number)) %>%
  reframe(main_teacher = mode_stat(Employee_Number)) %>% 
  ungroup() %>% 
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>% 
  rename(year = courses_sy_start, school_id = School)
# who teaches main english class? 
# how many students across grade have EE?



## clean test scores ----
assessments_student.year %<>%
  mutate(etime = case_match(Assessment_Window,
                            "BOY" ~ "f", "MOY" ~ "m", "EOY" ~ "s", .default = NULL),
         tname = ifelse(Assessment_Type == "RI", "sri", Assessment_Type)) %>%
  rename(pb = Proficiency_Level, ss = Proficiency_Score) %>%
  select(-Assessment_Window, -Assessment_Type) %>% 
  pivot_wider(names_from = c(tname, etime), 
              values_from = c(pb, ss), names_glue = "s_{tname}_{.value}_{etime}") %>% 
  select(-contains("TRC_ss")) %>% 
  mutate(across(contains("_pb_"), ~case_match(.x, 
      c("Below Basic", "Well Below Benchmark", "Far Below Proficient") ~ 1, 
      c("Basic", "Below Benchmark", "Below Proficient") ~ 2, 
      c("Proficient", "Benchmark", "At Benchmark") ~ 3, 
      c("Advanced", "Above Benchmark", "Above Proficient") ~ 4, 
      .default = NULL)), 
      across(contains("_ss_"), ~parse_integer(.x)))

## merge and reformat ----

df <- enrollment_student.school.year %>% 
  group_by(StudentID, SchoolYearStart) %>% 
  filter(Membership_Days==max(Membership_Days)) %>% 
  reframe(Grade = min(ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double(), na.rm = TRUE),
          school_id = min(School_ID, na.rm = TRUE), 
          s_days_enrolled = max(Membership_Days)) %>% 
  rename(year = SchoolYearStart) %>% 
  left_join(
    tests_student.year %>% rename(Grade = student_Grade),
    join_by(StudentID, Grade), relationship = "many-to-many") %>% 
  left_join(
    primary_teacher, join_by(StudentID, Grade, year, school_id), relationship = "many-to-many"
  ) %>% 
  left_join(demog_student.year %>% 
              mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>%
              rename(year = School_Year_Start), join_by(StudentID, Grade, year)) %>% 
  left_join(assessments_student.year %>% 
              rename(year = School_Year_Start), join_by(StudentID, Grade, year)) %>%
  mutate(s_race = case_match(Race_Ethnicity,
                             "American Indian or Alaska Native" ~ 1,
                             "Asian" ~ 2,
                             "Black or African American" ~ 3,
                             "Hispanic/Latino" ~ 4,
                             "Two or More Races" ~ 5,
                             "White" ~ 6, .default = NULL),
         s_female = case_match(Gender, "F" ~ 1, "M" ~ 0, .default = NULL),
         s_sped = case_match(SPED, "Y" ~ 1, "N" ~ 0, .default = NULL),
         s_lep = case_match(EL_Indicator, "Yes" ~ 1, "No" ~ 0, .default = NULL),
         ela_test_grade = case_when(str_starts(ela_testcode, "ELA")
                                    ~ parse_number(str_remove(math_testcode, "ELA")), .default = NULL),
         math_test_grade = case_when(str_starts(ela_testcode, "MAT")
                                     ~ parse_number(str_remove(ela_testcode, "MAT")), .default = NULL),
         employeeid = parse_number(main_teacher)) %>% 
  rename(
    usi = StudentID,
    schoolyear_fall = year,
    s_grade = Grade,
    schoolid1 = school_id,
    s_parcc_pb_ela = ela_perf_level,
    s_parcc_ss_ela = ela_scale_score,
    s_parcc_pb_math = math_perf_level,
    s_parcc_ss_math = math_scale_score,
    birthdate = Birth_Date
  ) %>% 
  select(usi, schoolyear_fall, s_grade, schoolid1, ela_test_grade, 
         s_parcc_pb_ela, s_parcc_ss_ela, math_test_grade, s_parcc_pb_math,
         s_parcc_ss_math, employeeid, s_female, s_race,
         birthdate, s_lep, s_sped, s_days_enrolled, s_DIBELS_pb_s, 
         s_DIBELS_pb_f, s_DIBELS_pb_m, s_TRC_pb_s, s_TRC_pb_f, s_TRC_pb_m,
         s_sri_pb_s, s_sri_pb_m, s_sri_pb_f, s_DIBELS_ss_s, s_DIBELS_ss_f, 
         s_DIBELS_ss_m, s_sri_ss_s, s_sri_ss_m, s_sri_ss_f)

names(df) <- str_to_lower(names(df))



## export ----

df %>%
  filter(s_grade %in% c(0:8)) %>% 
  write_dta(file.path(working_directory, "Student_level_Max.dta"))

df %>% 
  write_rds(file.path(working_directory, "Student_level_Max.rds"))




# Jiseung --- 

working_directory <- file.path("/Users/jiseungyoo/Desktop/DCPS")
setwd(working_directory)
getwd()



## Import ----


dfmax <- readRDS("Student_level_Max.rds", refhook = NULL)

courses_student.school.year <-   
  map(
    map_vec(c(19:22), ~glue("Courses SY{.x}-{.x+1}")),
    ~file.path( working_directory, 
                "Student Data through SY22-23 Updated.xlsx") %>% 
      read_excel(sheet = .x),
  ) %>% 
  list_rbind()



## Determine Language/Literacy Teacher --- 
### language_teacher matches 683. but I am gonna look up other algorithms

mode_stat <- function(x, na.rm = TRUE) {
  if(na.rm) x = x[!is.na(x)]
  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}
language_teacher <- 
  courses_student.school.year %>% 
  group_by(StudentID, Grade, School, courses_sy_start) %>%
  filter(grepl("Elementary|language|english|reading|writing|literacy", Title, ignore.case = TRUE))%>%
  filter(!grepl("computer|spanish|native|latin|arabic|financial", Title, ignore.case = TRUE))  %>%
  reframe(lan_teacher = mode_stat(Employee_Number)) %>% 
  ungroup() %>% 
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>% 
  rename(year = courses_sy_start, school_id = School)


## rename and merge ----

language_teacher<-language_teacher %>% 
  rename(
    usi = StudentID,
    schoolyear_fall = year,
    s_grade = Grade,
    schoolid1 = school_id,
    language_teacher= lan_teacher
    )


df_js <- dfmax %>% 
  left_join(
    language_teacher, join_by(usi, s_grade, schoolyear_fall, schoolid1))


df_js_sd <- df_js %>%
  group_by(schoolyear_fall, s_grade) %>%
  mutate(across(
    .cols = c(s_dibels_ss_s, s_dibels_ss_f, s_dibels_ss_m, 
              s_sri_ss_s, s_sri_ss_m, s_sri_ss_f),
    .fns = ~ scale(., center = TRUE, scale = TRUE),
    .names = "{.col}_sd"
  )) %>%
  ungroup() %>%
  rename(
    teacherid = employeeid,
    employeeid = language_teacher)%>% ### switch teacher main - language
  mutate(
      s_white = as.integer(s_race == "6"),
      s_black = as.integer(s_race == "3"),
      s_native_american = as.integer(s_race == "1"),
      s_asian = as.integer(s_race == "2"),
      s_latinx = as.integer(s_race == "4"),
      s_race_multi_other = as.integer(s_race == "5")
    ) %>%
   mutate(employeeid = as.numeric(employeeid))


df_js_sd <- df_js_sd %>%
  rename(
    s_dibels_ss_sd_s= s_dibels_ss_s_sd, 
    s_dibels_ss_sd_f= s_dibels_ss_f_sd, 
    s_dibels_ss_sd_m= s_dibels_ss_m_sd, 
    s_sri_ss_sd_s= s_sri_ss_s_sd, 
    s_sri_ss_sd_m= s_sri_ss_m_sd, 
    s_sri_ss_sd_f= s_sri_ss_f_sd,
  )
  

df_js_sd %>%
  filter(s_grade %in% c(0:8)) %>% 
  write_dta( file.path(working_directory, "student_level_js.dta"))



# Model specification

## import SERP --- 
observation_data <-
  file.path( working_directory, 
             "DCPS_Observation Data_charts_0124_js.xlsx") %>%  
  read_excel(sheet = "Data_Transposed")

observation_data <- observation_data %>%
  rename(employeeid = DCPSTeacherID)%>%
  filter(!is.na(employeeid))

observation_data$schoolyear_fall <- 2021

observation_data <- observation_data %>%
  arrange(employeeid, schoolyear_fall)

str(observation_data)



## merge: merge 1:m --- 
### //in stata 
### //Merge onto student-level data, using student-teacher links	
### tostring employeeid, replace (don't need this anymore, cuz change str to numneric already, but leave it just in case)
### //merge 1:m employeeid schoolyear_fall using "student_level_js", nogen keep(3)

merged_df <- observation_data %>%
  left_join(df_js_sd, by = c("employeeid", "schoolyear_fall"))

colnames(merged_df)

merged_df %>%
  write_rds( file.path(working_directory, "683_merged_js.rds"))


##regression

glimpse(merged_df)


### merged_df %>%
###  mutate(across(c(number_of_rotations, teach_calls_students_individual_FH, close_reading_Time, time_of_full_rotation), as.numeric))


model <- feols(
    s_dibels_ss_sd_s ~ 
      time_of_full_rotation + close_reading_Time+teach_calls_students_individual_FH + number_of_rotations+
      s_dibels_ss_sd_f + s_female + s_native_american + s_asian +
      s_black + s_latinx + s_white + s_sped + i(s_grade) + i(schoolyear_fall) | 
      schoolid1, 
    data = merged_df,
    cluster = ~ employeeid
  )

summary(model, robust = TRUE)



# OLS
model <- lm(s_dibels_ss_sd_s ~ time_of_full_rotation + close_reading_Time + teach_calls_students_individual_FH + number_of_rotations +
              s_dibels_ss_sd_f + s_female + s_native_american + s_asian +
              s_black + s_latinx + s_white + s_sped + i(s_grade) + i(schoolyear_fall),
            data = merged_df)

clustered_se <- cluster.vcov(model, ~ employeeid)

summary(model)