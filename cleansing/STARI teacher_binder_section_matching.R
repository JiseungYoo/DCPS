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
    schoolid1 = school_id)


saveRDS(df, file = "course_df.rds")

## STARI teacher data processing and EDA -----

df<- readRDS("course_df.rds") 
stari<- readRDS("stari.rds") # DAVID stari data from 6 schools
stari_teacher <- read_excel("STARI Teachers.xlsx") ## MS + HS teachers, used only MS teachers

#1.stari : STARI student ID - 1 none 0 (using USI) 
### stari 1, non intervention 0 


df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
  ungroup()


## teachers name processing

supplemental_english_titles <- c(
  glue("Reading Resource MS{6:8}"),
  glue("Reading Workshop {c(6:8, 'MS')}"),
  "Reading Support MS",
  "Extended Literacy MS"
)

excel_file <- file.path(working_directory, "./stari/binder_info.xlsx")
binder <- read_excel(excel_file) 

df <- df %>%
  mutate(teacher_name = Teacher %>%
           str_replace_all("[,\'-]", "") %>%  # Remove commas, apostrophes, and hyphens once
           tolower() %>%                      # Convert to lowercase
           str_split(" ") %>%                 # Split names by space
           map_chr(~ paste(sort(.x), collapse = " "))) # Sort and join names alphabetically


stari_teacher_list <- stari_teacher %>% 
  pull(Teacher) %>%
  tolower() %>%
  str_replace_all("[,'-]", "") %>%  # Remove commas, apostrophes, and hyphens
  str_split("\\s+") %>%                               # Split names by space
  map_chr(~ paste(sort(.x), collapse = " ")) %>% 
  unlist() %>%                      # Unlist the list of names
  unique()                          # Get unique names

binder_teacher_list <- binder %>% 
  pull(Teacher) %>%
  tolower() %>%
  str_replace_all("[,'-]", "") %>%  # Remove commas, apostrophes, and hyphens
  str_split("\\s+") %>%                               # Split names by space
  map_chr(~ paste(sort(.x), collapse = " ")) %>% 
  unlist() %>%                      # Unlist the list of names
  unique()                          # Get


stari_teacher_name <- c(binder_teacher_list, stari_teacher_list) %>% unique()

df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% c(6:8) &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413, 1071, 428)) %>%
  mutate(stari_teacher = ifelse(teacher_name %in% stari_teacher_name, 1, 0)) %>%
  ungroup()


print(colnames(df))

stari_teacher_section<- df %>% #df - total course enrollement data
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% c(6:8)&
           schoolid1 %in% c(347, 404, 454, 405, 407, 413, 1071, 435, 416, 428) &
           stari_teacher == 1 &                   #stari - students id from STARI DATA
           Title %in% supplemental_english_titles) %>% 
  select(usi, s_grade, schoolid1, schoolyear_fall, Title, Section,  Employee_Number, teacher_name)


stari_taking_all_students <- stari_teacher_section %>%
  select(usi, s_grade, schoolid1, schoolyear_fall, Title, Section, Employee_Number, teacher_name) %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  left_join(df, by = c("usi", "s_grade", "schoolid1", "schoolyear_fall", "Title","Section","Employee_Number", "teacher_name"))
  

stari_descriptive <- stari_taking_all_students %>%
  group_by(s_grade, schoolid1, schoolyear_fall, Title, Section, Employee_Number, teacher_name) %>%
  summarize(
    total_unique_students = n_distinct(usi),
    stari_students = n_distinct(usi[stari == 1]),
    .groups = 'drop'
  ) %>%
  mutate(
    percentage_stari_students = stari_students / total_unique_students * 100
  )

supple<-df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(
    s_grade %in% 6:8,
    schoolid1 %in% c(347, 404, 454, 405, 407, 413, 1071, 435, 416, 428),
    Title %in% supplemental_english_titles
  ) %>%
  count(Title, Section)

supple_combined <- supple  %>%
  group_by(s_grade, schoolid1, schoolyear_fall, Title, Section) %>%
  left_join(stari_descriptive, by = c("s_grade", "schoolid1", "schoolyear_fall", "Title","Section"))


updated<-stari_descriptive %>% 
  filter(
    schoolyear_fall %in% 2022) %>%
  mutate(stari_suspect = ifelse(percentage_stari_students>50, 1, 0)) %>%
  count(schoolid1, stari_suspect )



# Courses STARI teachers teach in 8 schools
# when select only MS teachers

#"Reading Workshop 8"   "Extended Literacy MS" "Reading Workshop 7"  
#"Reading Resource MS8" "Reading Resource MS7" "Reading Support MS"   
#"Reading Resource MS6" "Reading Workshop 6" "Reading Workshop MS" 
  
