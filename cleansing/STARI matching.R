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

# student_year.rds -> school_year_max + sd test score -> uploaded this file to Box(Mar 4)
studentdf <- readRDS("school_year.rds", refhook = NULL)


# Jiseung
## top 10 bottom 10 course -------------
### look at test RI or DIBELS scores to see if heterogeneity in quantiles
### student_year.rds -> school_year_max + sd test score -> uploaded file to Box(Mar 4)
### df -> course dataframe, 6-8, 19-22

studentdf <- studentdf %>% 
  filter(s_grade %in% 6:8) %>%
  group_by(usi, s_grade, schoolid1, schoolyear_fall) %>%
  rowwise() %>%
  mutate(engscore = (s_dibels_ss_sd_f + s_sri_ss_sd_f) / 2) %>%
  ungroup()

n_top <- ceiling(nrow(studentdf) * 0.1)
top <- studentdf %>%
  filter(s_grade %in% c(6:8)) %>% 
  filter(schoolyear_fall %in% c(2019:2022)) %>% 
  arrange(desc(engscore)) %>%
  slice(1:n_top)

n_bottom <- ceiling(nrow(studentdf) * 0.2)
bottom<- studentdf %>%
  filter(s_grade %in% c(6:8)) %>% 
  filter(schoolyear_fall %in% c(2019:2022)) %>% 
  arrange(engscore) %>%
  slice(1:n_bottom)

# identify the difference course_name between top 10 vs bottom 20
df <- df %>%
  rename(
    usi= StudentID, 
    schoolyear_fall= year, 
    s_grade= Grade, 
    schoolid1= school_id)

bottom_10_percent <- bottom %>%
  left_join(
    df, by = c("usi", "s_grade", "schoolyear_fall", "schoolid1")
  )

bottom_title_list <- bottom_10_percent %>%
  filter(grepl("Elementary|language|english|reading|writing|speaking|speech|literature|literacy|eng|lit|lan", Title, ignore.case = TRUE)) %>%
  filter(!grepl("computer|spanish|native|latin|arabic|financial|french|Chinese|sexuality|music", Title, ignore.case = TRUE)) %>%
  filter(!grepl("Pre-AP", Title, ignore.case = FALSE)) %>%
  distinct(Title)

distinct_values <- setdiff(unique(top_title_list$Title), unique(bottom_title_list$Title))

#    'Reading Foundations MS6',
#    'Reading Foundations MS7',
#    'Reading Foundations MS8'




# STARI -----------------
## EDA - Supplementary course enrollment ------
## enrollment_results.xlsx: number of student per grade, per school, per year **who take supplementary courses**

calculate_course_enrollment_percentage <- function(df, course_name) {
  course_data <- df %>%
    filter(s_grade %in% c(6:8), grepl(course_name, Title, ignore.case = TRUE))  
  # Calculate total number of students per grade and school### not sure (I used student_year file)
  total_students <- studentdf %>%
    group_by(s_grade, schoolid1,schoolyear_fall) %>%
    summarize(total_students = n_distinct(usi))
  enrollment_counts <- course_data %>%
    group_by(s_grade, schoolid1, schoolyear_fall) %>%
    summarize(num_students = n_distinct(usi))
  enrollment_percentage <- left_join(enrollment_counts, total_students, by = c("s_grade", "schoolid1", "schoolyear_fall"))
  enrollment_percentage <- enrollment_percentage %>%
    mutate(percentage_students = (num_students / total_students) * 100)
  return(enrollment_percentage)
}

enrollment_results <- list()
for (course_name in supplemental_english_titles) {
  enrollment_results[[course_name]] <- calculate_course_enrollment_percentage(df, course_name)
}
enrollment_percentages <- bind_rows(enrollment_results, .id = "course_name")

print(length(unique(combined_df$schoolid1))) # 30 schools
print(length(unique(combined_df$course_name))) # 23 courses


write.xlsx(enrollment_percentages, file = "enrollment_results.xlsx", rowNames = FALSE)



# generated Final_df based on Supplementary course list ()
## Final_df: student info (demo School, teacher info) who takes Supplementary course

student_supple_list <- function(df, course_name) {
  course_data <- df %>%
    filter(s_grade %in% c(6:8), grepl(course_name, Title, ignore.case = TRUE))  
  student_data <- df_js_sd %>%
    group_by(s_grade, schoolid1,schoolyear_fall) 
  student_list <- left_join(student_data, course_data, by = c("usi", "s_grade", "schoolid1", "schoolyear_fall"))
  return(student_list)
}


studet_supple_list_results <- list()
for (course_name in supplemental_english_titles) {
  studet_supple_list_results[[course_name]] <- student_supple_list(df, course_name)
}
final_df <- bind_rows(studet_supple_list_results, .id = "course_name")

final_df <- final_df %>%
  select(-c("usi.y", "s_days_enrolled.y", "course_name")) 

saveRDS(final_df, file = "student_year_suppl_course.rds")



# STARI data to combined one df--------------------

working_directory <- file.path("/Users/jiseungyoo/Desktop/DCPS/data/stari")
stari_files <- list.files(working_directory, pattern = "\\.xlsx$", full.names = TRUE)

excel_data <- list()
for (file in stari_files) {
  excel_data[[file]] <- read_excel(file)
  col_names <- colnames(excel_data[[file]])
  print(col_names)
}

excel_data[[1]]$schoolid1 <- 347 #Brookland
excel_data[[2]]$schoolid1 <- 404 #Browne
excel_data[[3]]$schoolid1 <- 454 #Cardozo
excel_data[[4]]$schoolid1 <- 405 #Deal
excel_data[[5]]$schoolid1 <- 407 #Eliot
excel_data[[6]]$schoolid1 <- 413 #Hart

stari<- bind_rows(excel_data)
print(length(unique(stari$USER_NAME))) # 324 courses

stari <- stari %>%
  rename(
    usi= USER_NAME, 
    s_grade= GRADE)


saveRDS(stari, file = "stari.rds")

  
# Matching and into one df STARI 1 NON-STARI 0 --------
## final_df: 6-8 grade, school_year 19_22/ student info + course info, **who take supplementary courses**
## student_year.rds -> student_year.rds + sd test score
  
final_df<- readRDS("student_year_suppl_course.rds", refhook = NULL)
studentdfm<- readRDS("/Users/jiseungyoo/Desktop/DCPS/data/Student_Year_M.rds", refhook = NULL)


student_ids_df1 <- unique(stari$usi)
student_ids_df2 <- unique(final_df$usi)
missing_student_ids <- setdiff(student_ids_df1, student_ids_df2)
print(missing_student_ids) #9294716 -> Grade this student is in STARI but not in course_df

school_ids_df1 <- unique(stari$schoolid1)
school_ids_df2 <- unique(final_df$schoolid1)
missing_school_ids <- setdiff(school_ids_df1, school_ids_df2)
print(missing_school_ids) # all school matched

### stari 1, non intervention 0 

final_df <- final_df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
  ungroup() 

df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
  ungroup()

#confirm
student_ids_df1 <- unique(stari$usi)
student_ids_df2 <- unique(final_df$usi[final_df$stari == 1])
missing_student_ids <- setdiff(student_ids_df1, student_ids_df2)
print(missing_student_ids)#9294716 -> Grade 9



## intervention title list vs stari title list to get non-stari-intervention
## intervention by grade, school, year 
intervention_by_g_y_s <- final_df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  summarise(unique_titles = toString(unique(Title)))

stari_by_g_y_s <- final_df %>%
  filter(stari == 1) %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  summarise(unique_titles = toString(unique(Title)))

write.xlsx(intervention_by_g_y_s, file = "intervention_summaries.xlsx", rowNames = FALSE)
write.xlsx(stari_by_g_y_s, file = "stari_summaries.xlsx", rowNames = FALSE)


## intervention title list
stari_titles <- final_df %>%
  filter(stari == 1) %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  summarise(unique_titles = as.list(unique(Title)))
stari_title_list <- unlist(stari_titles$unique_titles)
stari_title_list <- unique(na.omit(stari_title_list))


combined_df <- data.frame(stari_title_list)
combined_df1 <- data.frame(supplemental_english_titles)
combined_df <- cbind.fill(combined_df, combined_df1)

write.xlsx(combined_df1, file = "intervention_list.xlsx", rowNames = FALSE)
write.xlsx(combined_df, file = "stari_list.xlsx", rowNames = FALSE)


## additional check up -> same results
## df: 6-8 grade, school_year 19_22/ student info + course info, 
df <- df %>%
  filter(s_grade %in% c(6:8)) %>% 
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
  ungroup() #4, high school students 

stari_titles_2 <- df %>%
  filter(stari == 1) %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  summarise(unique_titles = as.list(unique(Title)))
stari_title_list_2 <- unlist(stari_titles_2$unique_titles)
stari_title_list_2 <- data.frame(stari_title_list_2)
write.xlsx(stari_title_list, file = "starilist_all.xlsx")


#******************************************************************************************************

# Matching and into one df STARI course title---------------
## Stari student: STARI course 1 non intervention 0 
## Stari course: STARI course 1  non stari course  0
## Reading intervetion course : STARI course 1  other intervention 2 none intervention 0

# stari title list 10
# non stari intervention 8 OR 15
# stari_title_list
# supplemental_english_titles

# df <-  "Student Data through SY22-23 Updated.xlsx", 6-8/ 19-22

non_stari_intervention <- setdiff(supplemental_english_titles, intersect(stari_title_list, supplemental_english_titles))


df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  mutate(
    Stari_course = ifelse(Title %in% stari_title_list, 1, 0),
    Reading_intervention_course = ifelse(Title %in% stari_title_list, 1,
                                         ifelse(Title %in%non_stari_intervention, 2, 0))
  )


print_unique_count <- function(df, condition) {
  stari_number <- df %>%
    group_by(s_grade, schoolid1, schoolyear_fall) %>%
    filter({{ condition }})
  print(length(unique(stari_number$usi)))
}

# Print the unique counts for different conditions
print_unique_count(df, stari == 0)
print_unique_count(df, stari == 1)
print_unique_count(df, Stari_course == 0)
print_unique_count(df, Stari_course == 1)
print_unique_count(df, Reading_intervention_course == 0)
print_unique_count(df, Reading_intervention_course == 1)
print_unique_count(df, Reading_intervention_course == 2)

saveRDS(df, file = "courseinfo_stari_intervention.rds")


studentdf <- studentdf %>%
  select(-c("stari")) 

result<- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  left_join(studentdf, by = c("usi", "s_grade", "schoolyear_fall", "schoolid1")
  )

print(colnames(df))

saveRDS(result, file = "Student_Year_stari_19to22_6to8.rds")


## school matching--------

stari_ <- readRDS("Student_Year_stari_19to22_6to8.rds", refhook = NULL)

filtered_df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(schoolid1 %in% c(347, 404, 454, 405, 407, 413)) 

print_unique_count(filtered_df, stari == 0)
print_unique_count(filtered_df, stari == 1)
print_unique_count(filtered_df, Stari_course == 0)
print_unique_count(filtered_df, Stari_course == 1)
print_unique_count(filtered_df, Reading_intervention_course == 0)
print_unique_count(filtered_df, Reading_intervention_course == 1)
print_unique_count(filtered_df, Reading_intervention_course == 2)




## STARI teacher data processing and EDA -----

stari<- readRDS("stari.rds") # DAVID stari data from 6 schools
stari_teacher <- read_excel("STARI Teachers.xlsx") ## MS + HS teachers
print(colnames(stari_teacher))


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


teacher_named_df<- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% c(6:8)&
           schoolid1 %in% c(347, 404, 454, 405, 407, 413) &
           teacher_name %in% stari_teacher_list)
print(unique(teacher_named_df$Title))

# all courses STARI teachers teach in 6 schools
#[1] "Reading Workshop 8"          "Graded Advisory MS"          "Reading Workshop 7"          "English 7"                  
#[5] "English 8"                   "Ungraded Advisory MS"        "Reading Resource MS8"        "In Person Period Attendance"
#[9] "Language Arts 6"             "MS Study Block"              "Reading Resource MS6"        "Advisory MS"                
#[13] "Extended Literacy MS"        "Reading Support MS"          "Reading Foundations MS8"     "Reading Workshop 6"         
#[17] "Reading Resource MS7"        "Reading Foundations MS6" 

print(length(unique(teacher_named_df$usi))) #247


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

# when including HS teachers
# "Projs & Prob Solving MS"   "Middle School Support"     "MS Study Block"        


print(length(unique(teacher_name_and_stari_usi_df$usi))) #250 students take STARI teachers' courses
print(length(unique(df$usi[df$stari == 1]))) #323 students in STARI data


teacher_name_and_stari_usi <- unique(teacher_name_and_stari_usi_df$usi)
stari_usi <- unique(df$usi[df$stari == 1])
unmatched_usi <- setdiff(stari_usi, teacher_name_and_stari_usi)
print(length(unmatched_usi)) #73 (10 students, schoolyear,..)

unmatched_usi_course_name <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413) &
           usi %in% unmatched_usi)

print(unique(unmatched_usi_course_name$Title)) #hmm.. similar
print(length(unique(unmatched_usi_course_name$usi))) #63 students-> they took same course but different teacher names on data


# STARI teacher matching ------------

## stari : STARI course 1 none 0 (using USI) 
#df <- df %>%
#  group_by(s_grade, schoolid1, schoolyear_fall) %>%
#  mutate(stari = ifelse(usi %in% stari$usi, 1, 0)) %>%
#  ungroup()

# stari_course
# 1. students who take courses taught by STARI teachers / plan.A

stari_teacher_course_title<-c ("Reading Foundations MS8", "Extended Literacy MS",
                              "Reading Workshop 8" ,     "Reading Support MS",
                              "Advisory MS"       ,      "Reading Workshop 7" ,  
                              "Reading Workshop 6"  ,    "Ungraded Advisory MS" ,   "Graded Advisory MS"  )



## stari_course : STARI course 1 none 0 (using stari_teacher_course_title) 

df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413))%>%
  mutate(stari_course = ifelse(Title %in% stari_teacher_course_title, 1, 0))

print(colnames(df))

print_unique_count(df, stari == 0)
print_unique_count(df, stari == 1)
print_unique_count(df, stari_course == 0)
print_unique_count(df, stari_course == 1)




# 2. students who take courses taught by STARI teachers / plan.B

stari_teacher_course_title<-c ("Reading Foundations MS8", "Extended Literacy MS",
                              "Reading Workshop 8" ,     "Reading Support MS",
                              "Reading Workshop 7" ,    "Reading Workshop 6"    )

## stari_course : STARI course 1 none 0 (using stari_teacher_course_title) 

df <- df %>%
  group_by(s_grade, schoolid1, schoolyear_fall) %>%
  filter(s_grade %in% 6:8 &
           schoolid1 %in% c(347, 404, 454, 405, 407, 413))%>%
  mutate(stari_course = ifelse(Title %in% stari_teacher_course_title, 1, 0))

print(colnames(df))


print_unique_count <- function(df, condition) {
  stari_number <- df %>%
    group_by(s_grade, schoolid1, schoolyear_fall) %>%
    filter({{ condition }})
  print(length(unique(stari_number$usi)))
}

# Print the unique counts for different conditions
print_unique_count(df, stari == 0) # 6260
print_unique_count(df, stari == 1) # 313
print_unique_count(df, stari_course == 0) # 6573
print_unique_count(df, stari_course == 1) # 6347


saveRDS(df, file = "course_stari_teacher.rds")


