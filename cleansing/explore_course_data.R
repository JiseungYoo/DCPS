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
working_directory <- file.path("C:", "Users", "Max", "Documents", "GitHub",
                               "DCPS")
#working_directory <- file.path("/Users/jiseungyoo/Desktop/DCPS/data")

box_directory <- file.path(working_directory, "..", "..", "..", 
                           "Box", "DCPS-SERP Data Internal 2019")

setwd(working_directory)
getwd()

#getwd()
## choose required packages ----
c("tidyverse", "magrittr", "rlang", "glue",
  "haven", "labelled", "writexl",
  "gt", "gtsummary", "webshot2", 'readxl',
  "scales", "grid", "ggtext", "patchwork"
)  |>
purrr::walk(~require(.x, character.only = TRUE))


# Body ----

## Load Data ----
excel_file <- file.path( box_directory, "Data", "Raw",
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

## initial course exploration ----
titles_of_interest <- 
  df %>%
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>%
  filter(grepl("Elementary|language|english|reading|writing|speaking|speech|literaure|literacy|eng|lit|lan", Title, ignore.case = TRUE))%>%
  filter(!grepl("computer|spanish|native|latin|arabic|financial|french|Chinese|sexuality|music", Title, ignore.case = TRUE))  %>%
  filter(!grepl("Pre-AP", Title, ignore.case = FALSE))  %>%
  filter(Grade %in% 6:8) %$%
  unique(Title)

df %>% 
  filter(Title %in% titles_of_interest) %>% 
  select(Title, Subject_Code) %>% 
  group_by(Title) %>% 
  reframe(Subject_Code = first(Subject_Code)) %>% 
  write_xlsx("reading_intervention_list.xlsx")

## Data Exploration ----  

df %>% 
  filter(Grade == 8) %>%
  count(StudentID) %>%
  # count(n) %>% view()
  ggplot(aes(n)) +
  geom_histogram()

# so it looks like there are several issues:
# 1. missing data where we have a student, but are missing course data for them?
  # there's nothing to do for this I don't think, but could revisit
# 2. Most core courses are FY but a minority of cases might use semesters or quarters?
  # this is because of the count info provided above there are like 12k 8th graders
  # but only 10k in a given core class, some of this could be due to tracking. 
  # e.g. honors vs normal, but I should check

english_course_titles <- c(glue("English {6:8}"), glue("Advanced English {6:8}"), 
  glue("Pre-AP English {6:8}"), glue("English FT {6:8}"), glue("English & Humanities {6:8}"),
  "English I", "Language, Culture and Literacy", glue("Language Arts {6:8}"),
  "English as a Second Language I", "English as a Second Language II",
  "IB MYP English II") # does Journalism count??

# here's a cool way to exploit title symmetry, but maybe unhelpful here
crossing(types = c("Resource", "Workshop", "Foundations", "Support"),
  grades = c(6:8, "MS")) %>% 
glue_data("Reading {types} {grades}")
# repeat the same procedure of filtering out courses narrowing down list of either 
# irrelevant or undocumented supplemental courses
supplemental_english_titles <- c(
  glue("Reading Resource MS{6:8}"),
  glue("Reading Workshop {c(6:8, 'MS')}"),
  "Reading Support MS",
  "Newc Engl Lit Devt MS", "Newc Oral LangDevt MS",
  "Beginning ESL MS", "Intermed ESL MS", "Advanced ESL MS",
  "Extended Literacy MS",
  "Reading Lab", "LL: Miixed-Model Reading MS7",
  glue("LL: Mixed-Model Reading MS{6:8}"),
  glue("AVID Grade {6:8}") # this isn't specifically literacy but I found their website
)


supplemental_english_titles
english_takers  <- 
  df %>% 
  filter(Grade %in% 6:8, Title %in% english_course_titles) %$%
  unique(StudentID)

unrelated_subject_codes <- 
  c("ADM", "ART", "CARR", "CTE", "EE", "FL", "MAT", "MU", "NULL", NULL, "PE",
    "SCI", "SS", "WL")

# check to see if core courses overlap (they don't)
students_with_double_core <-  
df %>%
  filter(Grade %in% 6:8, !Subject_Code %in% unrelated_subject_codes, Title %in% english_course_titles,
         Term_Code %in% c("FY", "FYCB")) %>% 
  group_by(StudentID, year) %>% 
  count(Title, Term_Code, Subject_Code,  sort = TRUE) %>% 
  count(n) %>% 
  filter(nn>1) %$%
  unique(StudentID)
  
df %>% 
  filter(StudentID %in% students_with_double_core, Title %in% english_course_titles) %>%
  group_by(StudentID, year) %>%
  add_count(StudentID) %>%
  filter(!n==1) %>% 
  reframe(Title = paste(Title, collapse = " "),
          Subject_Code = paste(Subject_Code, collapse = " "))
df %>% 
  filter(Title %in% english_course_titles) %>% 
  count(Term_Code, sort = TRUE)
  
df %>% 
  filter(!Title %in% c(english_course_titles, supplemental_english_titles),
         !Subject_Code %in% unrelated_subject_codes, Grade %in% 6:8) %>% 
  count(Title, Subject_Code, Term_Code, sort = TRUE) %>% 
  view()
# interesting student example
df %>% 
  filter(StudentID == "20049767", year == 2021,  !Subject_Code %in% unrelated_subject_codes) %>% 
  view()

df %>% 
  filter(Grade %in% 6:8) %$%
  unique(StudentID) %>% length() - 
  english_takers %>% length() 

df %>% 
  filter(Grade %in% 6:8, !Subject_Code %in% unrelated_subject_codes,
         Title %in% supplemental_english_titles) %>%
  count(Title, Subject_Code,  sort = TRUE) %>% 
  view()
## graph course taking ----

collapse_unique <- function(x, sep = "; ") {
  x <- x[!is.na(x) & x != ""]
  if(length(x) == 0) return(NA)
  x <- unique(x)
  paste(x, collapse = sep)
}


english_courses.student_year <- 
  df %>% 
  filter(Grade %in% 6:8, Title %in% c(english_course_titles, supplemental_english_titles)) %>%
  mutate(weight = case_match(Term_Code, c("FY" ,"FYCB") ~ 1,
      glue("S{1:2}") ~ .5, glue("T{1:4}")~ .25, .default = NA),
      core_title = ifelse(Title %in% english_course_titles, Title, ""),
      supp_title = ifelse(Title %in% supplemental_english_titles, Title, "")) %>% 
  group_by(StudentID, year) %>% 
  reframe(
    Grade = mean(Grade),
    weight = sum(weight, na.rm = TRUE),
    core_titles = collapse_unique(core_title), # write function with no duplication or extra separators
    supp_titles = collapse_unique(supp_title)) %>% 
  mutate(weight = ifelse(!is.na(core_titles), weight - 1,   weight))

english_courses.student_year %>% 
  ggplot(aes(weight)) + 
  geom_histogram() +
  facet_grid(rows = vars(Grade), cols = vars(year))

df %>% 
  filter(Grade %in% 6:8, !StudentID %in% english_takers) %>%
  group_by(school_id) %>% 
  count(StudentID) %>% view()
# core courses always seem to have the FY term_code
# also, there seems to be a few options for typical and honors english
# 

# look at test RI or DIBELS scores to see if heterogeneity in quantiles
# try to see if we can connect the supplemental course titles to specific literacy programs
# (stari, DC reading clinic, etc. )