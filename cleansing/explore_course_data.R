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
working_directory <- file.path("C:", "Users", "Max", "Box",
                               "DCPS-SERP Data Internal 2019")
setwd(working_directory)

#working_directory <- file.path("/Users/jiseungyoo/Desktop/DCPS/data")
#setwd(working_directory)
#getwd()
 

## choose required packages ----
c("tidyverse", "magrittr", "rlang", "glue",
  "haven", "labelled", "writexl",
  "gt", "gtsummary", "webshot2", 'readxl',
  "scales", "grid", "ggtext", "patchwork"
)  |>
purrr::walk(~require(.x, character.only = TRUE))


# Body ----

courses_student.school.year <-   
  map(
    map_vec(c(19:22), ~glue("Courses SY{.x}-{.x+1}")),
    ~file.path( working_directory, 
                "Student Data through SY22-23 Updated.xlsx") %>% 
      read_excel(sheet = .x),
  ) %>% 
  list_rbind()

titles_of_interest <- 
  courses_student.school.year %>%
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>%
  filter(grepl("Elementary|language|english|reading|writing|speaking|speech|literaure|literacy|eng|lit|lan", Title, ignore.case = TRUE))%>%
  filter(!grepl("computer|spanish|native|latin|arabic|financial|french|Chinese|sexuality|music", Title, ignore.case = TRUE))  %>%
  filter(!grepl("Pre-AP", Title, ignore.case = FALSE))  %>%
  filter(Grade %in% 6:8) %$%
  unique(Title)

courses_student.school.year %>% 
  filter(Title %in% titles_of_interest) %>% 
  select(Title, Subject_Code) %>% 
  group_by(Title) %>% 
  reframe(Subject_Code = first(Subject_Code)) %>% 
  write_xlsx("reading_intervention_list.xlsx")

courses_student.school.year %>%
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>%
  filter(Grade %in% 6:8,
         Subject_Code == "ELL") %$%
  unique(Title)
  

courses_student.school.year %>%
  mutate(Grade = ifelse(str_trim(Grade) == "K", "0", Grade) %>% parse_double()) %>%
  filter(Grade %in% 6:8) %$%
  unique(Title) %>%
  grepl("clinic", ., ignore.case = TRUE) %>% 
  sum(.)

courses_student.school.year %>%
  group_by(StudentID, Grade) %>% 
  mutate(DCRC = ifelse(Title == "Creative Writing", 1, 0)) %>% 
  reframe(DCRC = max(DCRC))
  
