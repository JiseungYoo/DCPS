# Header ---- 
#
# Script name: 
#
# Purpose of script:
#
# Author: Max Anthenelli
#
# Date Created: 2024-02-17
#  This code is free for anyone to use
# Email: anthenem@gmail.com
#
## set working directory ----
#working_directory <- file.path("C:", "Users", "Max", "Documents", "GitHub",
#                              "DCPS")

working_directory <- file.path("/Users/jiseungyoo/Desktop/DCPS/data")

box_directory <- file.path(working_directory, "..", "..", "..", 
                           "Box", "DCPS-SERP Data Internal 2019")

setwd(working_directory)

#getwd()
## choose required packages ----
c("tidyverse", "magrittr", "rlang", "glue",
  "haven", "labelled", "writexl",
  "gt", "gtsummary", "webshot2", 'readxl',
  "scales", "grid", "ggtext", "patchwork","openxlsx"
)  |>
  purrr::walk(~require(.x, character.only = TRUE))


# Body ----

## Load Data ----
excel_file <- file.path( working_directory,
                         "Student Data through SY22-23 Updated.xlsx")

courses_student.school.year <-   
  map(map_vec(c(19:22), ~glue("Courses SY{.x}-{.x+1}")),
      ~excel_file %>% read_excel(sheet = .x)) %>% 
  list_rbind() %>% 
  rename(year = courses_sy_start) %>% 
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double())

# restricting data to only look at student's main school 
df <- 
  read_excel(excel_file, sheet = "Enrollment and Attendance") %>% 
  group_by(StudentID, SchoolYearStart) %>% 
  filter(Membership_Days==max(Membership_Days)) %>% 
  reframe(Grade = min(ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double(), na.rm = TRUE),
          school_id = min(School_ID, na.rm = TRUE), 
          s_days_enrolled = max(Membership_Days)) %>% 
  rename(year = SchoolYearStart) %>%
  inner_join(courses_student.school.year, 
             join_by(StudentID, Grade, year, school_id == School),
             relationship = "one-to-many")

df <- df %>%
  rename(
    usi= StudentID, 
    s_grade= Grade,
    schoolyear_fall=year,
    schoolid1= school_id1)

## STARI teacher data processing and EDA -----

stari<- readRDS("stari.rds") # DAVID stari data from 6 schools
stari_teacher <- read_excel("STARI Teachers.xlsx") ## MS + HS teachers, used only MS teachers

#1.stari : STARI student ID - 1 none 0 (using USI) 
### stari 1, non intervention 0 


df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
  ungroup()

## teachers name processing

df$teacher_name <- df %>%
  mutate(teacher_name = str_replace(Teacher, ",", "") %>% str_split(" ") %>% map_chr(~ paste(rev(.x), collapse = " "))) %>%
  pull(teacher_name) %>%
  tolower() %>%
  gsub("'", "", .)%>%
  gsub("-", " ", .) 

stari_teacher_list <- stari_teacher %>%
  pull(Teacher) %>%
  tolower() %>%
  gsub("'", "", .) %>%
  gsub("-", " ", .) %>%
  unique() %>%
  unlist()

matched_df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(teacher_name %in% stari_teacher_list)

matched_teacher_names <- unique(matched_df$teacher_name)
unmatched_names <- setdiff(stari_teacher_list, matched_teacher_names)

if (length(unmatched_names) > 0) {
  print("Names not matched:")
  print(unmatched_names)
} else {
  print("All names in stari_teacher_list were matched.")
}


# "Teachers' names not matched" -> MS level 
#[1] "ivan rios" - Wells MS   "leah welsh" - Wells MS  "casey grimes"- Wells MS

teacher_name_and_stari_usi_df<- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% c(6:8)&
           schoolid1 %in% c(347, 404, 454, 405, 407, 413) &
           stari == 1 &                                      #stari - students id from STARI DATA
           teacher_name %in% stari_teacher_list)
print(unique(teacher_name_and_stari_usi_df$Title))


# Courses STARI teachers teach in 6 schools X STARI students take
# when select only MS teachers
#[1] "Reading Foundations MS8" "Extended Literacy MS"    "Reading Workshop 8"      "Reading Support MS"      "Advisory MS"            
#[6] "Reading Workshop 7"      "Reading Workshop 6"      "Ungraded Advisory MS"    "Graded Advisory MS"   




# STARI teacher matching ------------

# stari_course (course title  + section)
## students who take courses/section taught by STARI teachers 

stari_teacher_course_title<-c ("Reading Foundations MS8", "Extended Literacy MS",
                              "Reading Workshop 8" ,     "Reading Support MS",
                              "Reading Workshop 7" ,    "Reading Workshop 6"    )

## stari_course : STARI course 1 none 0 (using stari_teacher_course_title) 

print_unique_count <- function(df, condition) {
  stari_number <- df %>%
    group_by(s_grade, schoolid1, schoolyear_fall) %>%
    filter({{ condition }})
  print(length(unique(stari_number$usi)))
}

#Student_Year_45.rds => student_level (with standardized test score variables)
studentdf <- readRDS("Student_Year_45.rds", refhook = NULL)


stari_studentdf<- df %>%
  left_join(
    studentdf, by = c("usi", "s_grade", "schoolyear_fall", "schoolid1", "s_days_enrolled")
  )

  
title_section_df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           stari == 1 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413)) %>%
  filter(Title %in% stari_teacher_course_title) %>%
  select(s_grade, schoolid1, schoolyear_fall, Title, Section, Teacher) %>%
  distinct()



stari_section_student <- title_section_df %>%
  left_join(
    df, by = c("s_grade", "schoolyear_fall", "schoolid1", "Title", "Section")
  ) %>%
  mutate(stari_course = 2) 


## section 

stari_section_combined <- left_join(stari_studentdf, stari_section_student %>% 
                             select(usi, s_grade, schoolyear_fall, schoolid1, stari_course), 
                           by = c("usi", "s_grade", "schoolyear_fall", "schoolid1")) 


stari_section_combined <- stari_section_combined %>%
  mutate(stari_course = ifelse(stari_course %in% c(2), 1, 0))
 

------
  

stari_teacher_stats <-stari_section_combined %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413)) 


stari_0 <- stari_teacher_stats %>%
  filter(stari == 0)
stari_1 <- stari_teacher_stats %>%
  filter(stari == 1)

ggplot(data = rbind(stari_0, stari_1), aes(x = s_sri_ss_f, fill = factor(stari))) +
  geom_histogram(position = "identity", alpha = 0.5, bins = 20) +
  facet_wrap(~schoolid1) +
  labs(title = "Histogram of s_sri_ss_f Scores by STARI Status and School",
       x = "Raw Scores",
       y = "Frequency",
       fill = "STARI Status") +
  scale_fill_manual(values = c("blue", "red"), labels = c("Stari_course_section = 0", "Stari_course_section = 1")) +
  geom_segment(x=800, y=0, xend =800, yend= 10000)



stari_teacher_stats <-stari_section_combined %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413)) 

stari_0 <- stari_teacher_stats %>%
  filter(stari_course == 0)

stari_1 <- stari_teacher_stats %>%
  filter(stari_course == 1)


ggplot(data = rbind(stari_0, stari_1), aes(x = s_sri_ss_f, fill = factor(stari))) +
  geom_histogram(position = "identity", alpha = 0.5, bins = 20) +
  facet_wrap(~schoolid1) +
  labs(title = "Histogram of s_sri_ss_f Scores by STARI Status and School",
       x = "Raw Scores",
       y = "Frequency",
       fill = "STARI Status") +
  scale_fill_manual(values = c("blue", "red"), labels = c("Stari_course_section = 0", "Stari_course_section = 1")) +
  geom_segment(x=800, y=0, xend =800, yend= 10000)



filtered_data <- stari_teacher_stats %>%
  filter(stari == 1)

print(length(unique(filtered_data$usi)))
print(colnames(filtered_data))
print(length(unique(title_section_df$Section)))

stari_teacher_stats
print_unique_count(stari_teacher_stats, stari == 0) # 6260
print_unique_count(stari_teacher_stats, stari == 1) # 313
print_unique_count(stari_teacher_stats, stari_course == 0) # 6212
print_unique_count(stari_teacher_stats, stari_course == 1) # 608

library(foreign)
write.dta(df, "stari_data.dta")

df <- read.dta("stari_data.dta")

print(colnames(stari_teacher))

print(colnames(df))

summary_stats <- by(stari_teacher_stats[, -which(names(stari_teacher_stats) == "stari")], stari_teacher_stats$stari, summary)
summary_df <- do.call(rbind, summary_stats)
summary_df <- as.data.frame(summary_df)
write.xlsx(summary_df, "stari.xlsx")

summary_stats1 <- by(stari_teacher_stats[, -which(names(stari_teacher_stats) == "stari_course")], stari_teacher_stats$stari_course, summary)
summary_df1 <- do.call(rbind, summary_stats1)
summary_df1 <- as.data.frame(summary_df1)

write.xlsx(summary_df1, "stari_course.xlsx")
