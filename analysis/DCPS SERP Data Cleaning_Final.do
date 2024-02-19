/* 

Program to clean and compile data from DCPS as part of partnership work with SERP.

Raw data files include:

	- TeacherFiles (a folder with the data we received from the IMPACT team, 
		including historical IMPACT data with teacher names removed and Insight survey results)
	- AllCohortIds (a list of student IDs for all students who entered kindergarten in DCPS 
		from 2012 through 2019--the base list for the rest of the files)
	- Attendance
	- Behavior (suspension data)
	- Course data (student-course matches that can be used to match students to teachers through teacher-course matches)
	- Demographics/Enrollment (yearly demographic data and student-school matches)
	- Dibels
	- i-Ready
	- PARCC
	- SRI (reading inventory)
*/
clear
set more off, perm
*set mem 1073741824

// Change working directoy
	
	// For David
	*cd "/Users/dblazar/Library/CloudStorage/Box-Box/DCPS-SERP Data Internal 2019"
	
	// Xinyi
	*cd "/Users/xinyizhong/Box/DCPS-SERP Data Internal 2019" 
	
	// For Max
	cd "C:\Users\Max\Box\DCPS-SERP Data Internal 2019"
	
// Set globals
	
	global data_raw 	"./Data/Raw/"
	global data_temp 	"./Data/Temporary/"
	global data_clean	"./Data/Clean/"
	global output		"./Output/"

// Switches
		
	global attendance		= 	0
	global test_scores		=	0
	global teachers			=	1
	global courses			=	0
	global school_climate	=	0
	global merge			=	0
	
*-------------------------------------------------------*
*	Attendance and School Enrollment (Matthew)			*
*-------------------------------------------------------*
if $attendance == 1 {
{ // ID

import excel using "$data_raw/DRT5055_AllCohortIds.xlsx", clear firstrow
	
	unique localid // unique by this variable. Often 7-digit number beginning with 9; otherwise, 10-digit number beginning with 2.
	unique usi // not unique by this variable. Generally 10-digit number
	
	duplicates tag usi, gen(temp)
	sort usi
	*bro if temp>0
	
	// NOTE: There are 7 kids who have non-unique localid's because they have two entering cohorts attached to their ID.
	
	/*
	From DCPS: 
	USI refers to the unique student identifier, IDs that OSSE assigns to students that remain the same through DCPS, 
	charter schools, etc. It’s most likely that those are the same students; we attempt to reconcile our local ids with 
	OSSE’s USIs (when students leave and return to the system, for example), but in those students’ cases it may not have happened.
	*/
}
{ // Attendance NOTE: HAVE ABOUT 10% OF DATA WITH ENROLLED DAYS OF EXACTLY 66 AND NOT SURE WHY 

// From MH: With attendance, we may need to ask the district why there could be so many students who attended 66 days, 
//	and think about how that unusually high number in the distribution of all days attended could affect any analysis we run using days attended.

import excel using "$data_raw/Attendance.xlsx", clear firstrow

	// Rename variables for consistency
	
		rename grade s_grade
		rename schoolcode schoolid
		rename membershipdays s_days_enrolled
		rename inseatabsences s_days_absent
		rename excusedabsences s_days_absent_excused
		rename unexcusedabsences s_days_absent_unexcused
		rename schoolyear schoolyear_fall
		
		drop cohort individualisa activeenrollment
	
	// Clean
		
		// 1,032 observations missing all data. Drop
			
			drop if localid==.
			
		// Schoolyear
			
			*tab schoolyear_fall, m
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
			
		// Grade level
			
			foreach g in 1 2 3 4 5 6 {
				replace s_grade = "`g'" if s_grade=="0`g'"
				}
				replace s_grade = "0" if s_grade=="K"
			
			// Multiple ways to document pre-K
				
				*tab schoolyear s_grade if regexm(s_grade, "P")
					// NOTE: PK and PS used in 2012 through 2014, while P3 and P4 used in 2015 and later.
					//	I believe PS means pre-school and is equivalent to P3,
					//	while PK means pre-K and is equivalent to P4.
					//	"Pre" and "SP" also used but only 5 total observations.
				
				replace s_grade = "-1" if s_grade=="P4" | s_grade=="PK" | s_grade=="Pre"
				replace s_grade = "-2" if s_grade=="P3" | s_grade=="PS" | s_grade=="SP"
			
			// 1 student has one observation with grade level "ZZ" but also has two years of pre-K
				
				drop if s_grade=="ZZ"
			
			// 134 observations have grade level of "UN" -- not sure what this is
				
				*tab activeenrollment if s_grade=="UN"
					// 124 of these have "activeenrollment" variable value of "N". 10 with "Y"
				*summ s_days_enrolled if s_grade=="UN"
				*gen un = s_grade=="UN"
				*bysort usi: egen ever_un = max(un)
				
				drop if s_grade=="UN"
			
			destring s_grade, replace
		
*save "$data_temp/attendance_temp", replace				
*use "$data_temp/attendance_temp", clear	
	
		// Look for enrollments in multiple schools in a given year
			
			duplicates drop
			
			// Start with duplicates by student, school, and year
				
				*duplicates tag localid schoolyear schoolid, gen(temp)
					// NOTE: 99% of observations have just one observation in a given school and year
				
				// For students who have two enrollment spells in the same school and year (with a gap in between)
				//	sum up total days enrolled, absences, etc. 
				foreach v of varlist s_days_enrolled s_days_absent s_days_absent_excused s_days_absent_unexcused {
					bysort localid schoolyear schoolid: egen `v'_sum = total(`v')
					}
				
				// 20 observations have summed days enrolled over 199 (which seems to be the max).
				// All of these students are observed in the same school twice in the same year/grade.
				//	Keep the observation with more days enrolled. 
					
					bysort localid schoolyear schoolid: egen max = max(s_days_enrolled)
					drop if s_days_enrolled_sum>199 & s_days_enrolled!=max
					
					drop max *_sum
				
				duplicates drop localid schoolyear schoolid, force
				
			// Now look for students attached to different schools in a given year	
				
				duplicates tag localid schoolyear, gen(temp)
				gen s_multiple_schools = (temp>0)
					// NOTE: 95% of observations in 1 school in a given year.
					//	10 students in four schools, 120 in three schools, and ~3,200 in two schools.
				
				// Summ up days enrolled across schools
					
				foreach v of varlist s_days_enrolled s_days_absent s_days_absent_excused s_days_absent_unexcused {
					bysort localid schoolyear: egen `v'_sum = total(`v')
					}
					
				// 67 observations have enrollment sums above 199
				//	Drop observation with lower enrollment.
						
					bysort localid schoolyear: egen max = max(s_days_enrolled)
					drop if s_days_enrolled_sum>199 & s_days_enrolled!=max
					
					// 7 students have 182 days enrolled in two schools in the same year. Clean/drop manually
						
						drop if localid==9317285 & s_grade==-1 & schoolyear==2016 // in grades -1 and 0 in the same year, but also has -1 in the year earlier
						drop if localid==20005779 & s_grade==0 & schoolyear==2016 // in grades 0 and 1 in same year, but also have 0 in the prior year
						drop if localid==20012070 & s_grade==-2 & schoolid==299 // in two schools for grade -2, but observed in one of these in next year/grade -1
						drop if localid==20015850 & s_grade==-1 // in grades -1 and 0 in the same year, which is causing the issue 
						drop if localid==20016067 & s_grade==-2 & schoolid==370 // in grades -2 in two different schools, but stays in one of these in next year
						drop if localid==20016464 & s_grade==-2 & schoolid==239 // in grades -2 in two different schools, but stays in one of these in next year
						drop if localid==20017624 & s_grade==0 & schoolid==339 // in grade 0 in two different schools, but stays in one the next year/grade
				
					drop max *_sum temp
				
			// Drop observations with very few days enrolled (fewer than 20), but keeping total number of days
			//	enrolled summed across observations.
			//	NOTE: Drop about 4K observations, and lose ~400 entire student-year observations.
				
				foreach v of varlist s_days_enrolled s_days_absent s_days_absent_excused s_days_absent_unexcused {
					bysort localid schoolyear: egen `v'_sum = total(`v')
					}
					
				***************************
				drop if s_days_enrolled<=20
				***************************
			
			// Look for grade discprencies that may be reason for multiple schools.
				
				bysort localid schoolyear: egen min_grade = min(s_grade)
				bysort localid schoolyear: egen max_grade = max(s_grade)
				gen flag = (min_grade!=max_grade)
					// NOTE: Only 25 student-year observations, 60% of which are pre-K
				replace s_grade = max_grade if flag==1
				drop min_grade max_grade flag
				
		// Finally, identify primary school, but keep others. Students have up to three schools.
			
			duplicates tag localid schoolyear, gen(temp)
			gsort localid schoolyear -s_days_enrolled
			
			drop s_days_enrolled s_days_absent s_days_absent_excused s_days_absent_unexcused
			rename *_sum *
			
			bysort localid schoolyear: gen count = _n
			reshape	wide schoolid schoolname, i(localid schoolyear) j(count)
	
	order localid usi schoolyear s_grade
	
save "$data_temp/attendance", replace

}
{ // Demographics and Enrollment

// Merge multiple files
	
	// Updated/more complete LEP information (fall 2011 to 2019)
		
		import excel using "$data_raw/Enrollment Demographics Updated 7.20.xlsx", clear firstrow
		
		rename studentid localid
		rename school_year_start schoolyear_fall
		keep usi localid schoolyear lep_flag
		destring usi, replace
		destring localid, replace
		duplicates drop
		
		tempfile lep
		save `lep'
	
	// At risk and foster care (in two separate files: 2016 to 2018, and 2019)
		
		import excel using "$data_raw/At-Risk and Foster Care SY1920.xlsx", firstrow clear

		rename OSSEAtRisk atrisk
		rename ChildandFamilyServicesAgency foster_system_flag
		rename SchoolYearStart school_year_start
		rename StudentID localid

		tempfile atrisk1920
		save `atrisk1920'

		import excel using "$data_raw/At-Risk and Foster Care SY1617 SY1718 SY1819.xlsx", clear firstrow
		append using `atrisk1920'
		
		drop cohort
		duplicates drop
		rename school_year_start schoolyear_fall
		
		tempfile atrisk_foster
		save `atrisk_foster'
		
	// Original file DCPS shared
		
		import excel using "$data_raw/DemographicsEnrollment.xlsx", clear firstrow
	
		rename schoolcode schoolid
		rename grade s_grade
		rename spedlevel s_sped
		rename lepindicator s_lep
		rename race s_race
		rename ethnicity s_ethnicity
		rename raceethnicity s_race_ethnicity
		rename gender s_gender
		rename farmsstatus s_frpl
		rename schoolyear schoolyear_fall
		
		// Get school year to be numeric
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
		
		// A couple of duplicates: 2 pre-K students in two different schools. 1 is missing localid
			drop if localid==. // drops 1 of the 2
			duplicates drop localid schoolyear, force // gets rid of 1 duplicate for other student
		
	merge 1:1 localid schoolyear using `lep', nogen keep (1 3)
		// Most merging. 3 from master not merging. An additional 4,338 students from 2011 that are not
		//	part of our sample.	 
	merge 1:1 localid schoolyear using `atrisk_foster', nogen keep(1 3)
		// 1,420 from using only. Drop these.
		//	Roughly 1/3 of observations in master merging on, most from 2016 and 2017. About half from 2018 merging.
		// 67,585 do not have atrisk; impute
	
save "$data_temp/demos_merged", replace

// Clean together

use "$data_temp/demos_merged", clear
		
	// Grade level
	
		*tab s_grade, m
		foreach g in 1 2 3 4 5 6 7 {
			replace s_grade = "`g'" if s_grade=="0`g'"
			}
			replace s_grade = "0" if s_grade=="KG"
			
		// Multiple ways to document pre-K
				
			replace s_grade = "-1" if s_grade=="P4" | s_grade=="PK" | s_grade=="PK4"
			replace s_grade = "-2" if s_grade=="P3" | s_grade=="PS" | s_grade=="PK3"
			
		// 13 observations have grade level of "UN" -- not sure what this is
				
			drop if s_grade=="UN"
			
		destring s_grade, replace
		
	// Grade repeat flag
		
		tsset localid schoolyear
		gen s_grade_tp1 = F.s_grade
		gen s_grade_tm1 = L.s_grade
		gen s_grade_repeat = (s_grade==s_grade_tm1)
		drop s_grade_t?1
		tsset, clear
			
	// Gender
		
		*tab s_gender, m
		gen s_female = (s_gender=="F")
		replace s_female = 1 if regexm(s_gender, "FEMALE|Female")
		replace s_female = . if s_gender==""
		*tab s_gender s_female, m
		drop s_gender
		
		// Look for consistency/inconsistency
			
			bysort localid: egen min = min(s_female)
			bysort localid: egen max = max(s_female)
			bysort localid: egen mode = mode(s_female), minmode
			replace s_female = mode if min!=max
			drop min max mode
		
	// Race/Ethnicity
		// NOTE: Looks like 3 race/ethnicity variables that need to be cleaned and reconciled across.
			
			// Start with s_race_ethnicity variable
				
				*tab s_race_ethnicity, m
				replace s_race_ethnicity = "Black" if regexm(s_race_ethnicity, "Black")
				replace s_race_ethnicity = "American Indian" if regexm(s_race_ethnicity, "American Indian")
				replace s_race_ethnicity = "Multi-Racial" if regexm(s_race_ethnicity, "Multi|Two or More")
				replace s_race_ethnicity = "Pacific Islander" if regexm(s_race_ethnicity, "Pacific")
				replace s_race_ethnicity = "Hispanic/Latinx" if s_race_ethnicity=="Hispanic/Latino"
					
				replace s_race_ethnicity = "Asian" if s_race_ethnicity=="Pacific Islander"
					
					// NOTE: 3% multi racial
					
			// Check against other variables
				
				*tab s_race_ethnicity s_ethnicity, m
					// NOTE: Anyone identified as Hispanic/Latinx from s_ethnicity variable
					//	also identified as such with s_race_ethnicity variable.
				*tab s_race s_race_ethnicity, m
					// This other variable is a bit of a mess, so discard.
				
				drop s_ethnicity s_race
			
			// Look for consistency/inconsistency
				
				encode s_race_ethnicity, gen(temp)
				bysort localid: egen min = min(temp)
				bysort localid: egen max = max(temp)
				bysort localid: egen mode = mode(temp), minmode
					// NOTE: ~5K out of 144K have mismatch, so pretty good!
				tab s_race_ethnicity if min!=max, m
					// NOTE: Mostly an issue with Black/Hispanic/White.
				
				replace temp = mode if min!=max
				drop min max mode s_race_ethnicity
				rename temp s_race
			
			// Create dummy variables
				
				gen s_native_american = (s_race==1)
				gen s_asian = (s_race==2)
				gen s_black = (s_race==3)
				gen s_latinx = (s_race==4)
				gen s_race_multi_other = (s_race==5)
				gen s_white = (s_race==6)
				
	// SPED
				
		*tab s_sped, m
		*tab schoolyear s_sped, m
			// NOTE: "NONE" and "NULL" only used in 2012 and 2013, where there is no missing.
		*tab s_sped spedlevelindicator, m
		*tab schoolyear spedlevelindicator, m
			// NOTE: "spedlevelindicator" variable only used in 2017.
			
		gen temp = (spedlevelindicator!="" & schoolyear==2017)
		drop spedlevelindicator
		replace temp = 1 if regexm(s_sped, "Level")
		drop s_sped
		rename temp s_sped		
			
	// LEP
		
		*tab s_lep lep_flag, m
			// Two variables seem to align, when we have coverage for both.
		drop s_lep
		rename lep_flag s_lep
		replace s_lep = "1" if regexm(s_lep, "Y")
		replace s_lep = "0" if regexm(s_lep, "N")
		destring s_lep, replace
			// NOTE: 3 missing
		
	// SES
		
		/*
		// FRPL
		/*
		FRPL of limited utility in DCPS because 87 schools are CEP meaning that all students get free meals.
		*/
			
			*tab schoolyear s_frpl, m
			replace s_frpl = "Free" if s_frpl=="FREE"
			replace s_frpl = "Paid" if s_frpl=="PAID" | s_frpl=="Pay All"
			
			rename s_frpl s_frpl_string
		*/
		
		// At Risk
		/*
		As defined by the Office of the State Superintendent of Education, “Students who are at risk are those who qualify for Temporary Assistance for 
		Needy Families (TANF), the Supplemental Nutrition Assistance Program (SNAP), have been identified as homeless during the academic year, who under
		the care of the Child and Family Services Agency (CFSA or “foster care”), and who are high school students at least one year older than the 
		expected age for their grade.”
		*/
		
			*tab schoolyear atriskindicator, m
				// Have 2014 through 2016
			*tab schoolyear atrisk, m
				// Have in 2016 through 2018
			*tab atriskindicator atrisk, m
		
		
			replace atrisk = atriskindicator if atrisk == ""
			tab atrisk, missing
			tab schoolyear_fall atrisk, missing
			// There are only yeses in 2015 and 2018; we can assume that the missings in these years are nos
			// 2012 and 2013 missing entirely
			// The 11 observations missing in 2017 and 2019, we can assume are nos
			
		
			gen s_atrisk = (atriskindicator=="YES" | atrisk=="YES")
			replace s_atrisk = . if schoolyear_fall < 2014
			
			
			// We don't have information in 2012 or 2013. So, take best guess from later years.
			//	Two options: (i) look at mode across all years in the dataset, and (ii) look at data in the first available year (i.e., 2014)
			
				bysort localid: egen atrisk_mode = mode(s_atrisk)	
				// Assigns a value of 0 or 1 depending on what the mode is for that particular student
			
			// Option 2
			// Use max here
				gen temp = s_atrisk if schoolyear==2014
				bysort localid: egen atrisk_2014 = max(temp)
				
				tab atrisk_mode atrisk_2014 if schoolyear_fall < 2014, m
				
				replace s_atrisk = 0 if schoolyear_fall < 2014 & atrisk_mode == 0 & atrisk_2014 == 0
				replace s_atrisk = 1 if schoolyear_fall < 2014 & atrisk_mode == 1 & atrisk_2014 == 1
				replace s_atrisk = atrisk_mode if schoolyear_fall < 2014 & atrisk_mode != . & atrisk_2014 == .
				replace s_atrisk = atrisk_2014 if schoolyear_fall < 2014 & atrisk_mode == . & atrisk_2014 != .
				replace s_atrisk = atrisk_2014 if schoolyear < 2014 & s_atrisk == .
				
				// Approximately 1700 student years are missing atrisk in 2012/2013
			
			drop atriskindicator atrisk
		
	// Foster system (only have for 2016 through 2018)
		
		*foster_system_flag
		
	// Get down to student-by-year dataset
	
		unique localid schoolyear
		
save "$data_temp/demographics", replace			
		
}
{ // Behavior

import excel using "$data_raw/Behavior.xlsx", clear firstrow
	
	// Rename variables for consistency
		
		rename incidentschoolid schoolid
		rename incidentschoolname schoolname
		rename gradeleveldesc s_grade
		rename suspensiondays s_num_days_susp
		gen suspension_type = "Off-Site" if regexm(actiondesc, "Off-Site|Off-site") 
		replace suspension_type = "On-Site" if regexm(actiondesc, "On-Site|On-site")
		rename schoolyear schoolyear_fall
		drop actiondesc infractiondesc infractionleveldesc date startdt enddt
		
	// Clean
		
		// Schoolyear
			
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
		
		// Grade level
			
			*tab s_grade, m
			replace s_grade = "0" if s_grade=="K"
			replace s_grade = "-1" if s_grade=="PK"
			replace s_grade = "-2" if s_grade=="PS"
			destring s_grade, replace
			
	// Collapse to student-schoolyear
		
		gen s_num_days_susp_insch = s_num_days_susp if suspension_type=="On-Site"
		gen s_num_days_susp_outsch = s_num_days_susp if suspension_type=="Off-Site"
		
		collapse (sum) s_num_days_susp_insch s_num_days_susp_outsch ///
			, by(localid usi schoolyear)
			
		gen s_num_days_susp = s_num_days_susp_insch + s_num_days_susp_outsch
	
save "$data_temp/suspensions", replace
}
}
*-------------------------------------------------------*
*	Student Test Scores	(Matthew)						*
*-------------------------------------------------------*
if $test_scores { 
{ // DIBELS (Dynamic Indicators of Basic Early Literacy - K through 5, but mostly earlier grades)

import excel using "$data_raw/DIBELS.xlsx", clear firstrow
tempfile temp
save `temp'
import excel using "$data_raw/DIBELS_MOY.xlsx", clear firstrow
destring localid, replace
destring usi, replace
destring schoolcode, replace
destring compositescore, replace
append using `temp'
	
	// Rename variables for consistency
		
		rename schoolcode schoolid
		rename grade s_grade
		rename benchmarkperiod term
		rename compositescore s_dibels_ss
		rename schoolyear schoolyear_fall
		drop schoolname
	
	// Clean
		
		drop if s_dibels_ss==. // drop 6 obs
		drop if localid==. // drop 3 obs
			// 1 student with same USI # doesn't have LOCALID, and has two scores that are same magnitude but oppositely signed
		
		// Schoolyear
			
			*tab schoolyear_fall, m
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
		
		// Grade Level
			
			replace s_grade = "0" if s_grade=="K" | s_grade=="Pre-K" // only 1 observation for pre-K
			destring s_grade, replace

		// Performance level
			
			drop if s_dibels_ss==.
			
			gen s_dibels_pb = .
			replace s_dibels_pb = 1 if compositelevel == "Well Below Benchmark"
			replace s_dibels_pb = 2 if compositelevel == "Below Benchmark"
			replace s_dibels_pb = 3 if compositelevel == "Benchmark" | compositelevel == "At Benchmark"
			replace s_dibels_pb = 4 if compositelevel == "Above Benchmark"
			drop compositelevel
		
		*count if s_dibels_ss==.
		*count if s_dibels_pb==.
		
		// Standardize scores
			
			bysort schoolyear s_grade term: center s_dibels_ss, gen(s_dibels_ss_sd) standardize
		
		// Reshape wide by term
			
			replace term = "f" if term=="BOY"
			replace term = "m" if term=="MOY"
			replace term = "s" if term=="EOY"
			
			*unique usi s_grade schoolyear_fall term
			duplicates tag usi s_grade schoolyear_fall term, gen(temp)
				// 15 students have duplicates. Take maxiumum. Exclude schoolid, as some of these students
				//	changed schools across assessment. We will get school code from other files.
				
				collapse (max) s_dibels_ss s_dibels_pb s_dibels_ss_sd, by(localid usi s_grade schoolyear term) 
				rename s_dibels* s_dibels*_
				
				reshape wide s_dibels*, i(localid usi s_grade schoolyear_fall) j(term) string
	
		// Get down to one observation per student per year (still some duplicates)
			
			duplicates tag usi schoolyear_fall, gen(temp)
				// NOTE: 49 students look to have 2 grade levels in the same school year. At this point, can drop grade level anyway.
			collapse (max) s_dibels_*, by(localid usi schoolyear) 
			
			label define dibels_bechmark 1 "Well Below Benchmark" 2 "Below Benchmark" 3 "Benchmark" 4 "Above Benchmark"
			label values s_dibels_pb_f dibels_bechmark
			label values s_dibels_pb_m dibels_bechmark
			label values s_dibels_pb_s dibels_bechmark
			
			// One usi is duplicated within the same year because of different localid. Not sure why, but force drop.
			duplicates drop usi schoolyear_fall, force
	
save "$data_temp/dibels", replace		
			
}
{ // TRC (new early literacy assessment)

/*
TRC has proficiency bands but not scaled scores. Instead, scores are book or reading levels:

PC = print conepts
RB = reading behaviors
Then, levels of A - Z
*/
			
import excel using "$data_raw/TRC1213-1920.xlsx", clear firstrow
	
	destring usi, replace
	drop if book_level==""
	rename studentid localid
	
	// Rename variables for consistency
		
		rename schoolcode schoolid
		rename grade s_grade
		rename assessment_window term
		*rename compositescore s_dibels_ss
		rename school_year_start schoolyear_fall
	
	// Clean
		
		// Schoolyear
			
			*tab schoolyear_fall, m
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
		
		// Grade Level
			
			replace s_grade = "0" if s_grade=="K" // only 1 observation for pre-K
			destring s_grade, replace

		// Performance level
			
			gen s_trc_pb = . if proficiency_level=="No Proficiency Level Established"
			replace s_trc_pb = 1 if proficiency_level == "Far Below Proficient"
			replace s_trc_pb = 2 if proficiency_level == "Below Proficient"
			replace s_trc_pb = 3 if proficiency_level == "Proficient"
			replace s_trc_pb = 4 if proficiency_level == "Above Proficient"
			drop proficiency_level
		
		// Book Level
			
			gen temp = book_level if book_level!="PC" & book_level!="RB"
			encode temp, gen(s_trc_booklevel)
			replace s_trc_booklevel = 0 if book_level=="RB"
			replace s_trc_booklevel = -1 if book_level=="PC"
			label define s_trc_booklevel -1 "Print Concepts" 0 "Reading Behaviors", add
			label values s_trc_booklevel s_trc_booklevel
			
			drop temp book_level
		
		*count if s_trc_pb==.
			// 6,528 are missing, even though the book level isn't missing.
			//	These all comes from 2012, BOY and MOY. Basically ALL BOY and MOY observations for that year.
		*count if s_trc_booklevel==.
			
		// Reshape wide by term
			
			replace term = "f" if term=="BOY"
			replace term = "m" if term=="MOY"
			replace term = "s" if term=="EOY"
			
			*unique usi s_grade schoolyear_fall term
			duplicates tag usi s_grade schoolyear_fall term, gen(temp)
				// 12 students have duplicates. Take maxiumum. Exclude schoolid, as some of these students
				//	changed schools across assessment. We will get school code from other files.
				
				collapse (max) s_trc_pb s_trc_booklevel, by(localid usi s_grade schoolyear term) 
				rename s_trc* s_trc*_
				
				reshape wide s_trc*, i(localid usi s_grade schoolyear_fall) j(term) string
	
		// Get down to one observation per student per year (still some duplicates)
			
			duplicates tag usi schoolyear_fall, gen(temp)
				// NOTE: 65 students look to have 2 grade levels in the same school year. At this point, can drop grade level anyway.
			collapse (max) s_trc_*, by(localid usi schoolyear) 
			
			// Still have one duplicate because of discrepency between usi and localid
			duplicates drop usi schoolyear, force
			
			foreach v of varlist s_trc_booklevel_f s_trc_booklevel_m s_trc_booklevel_s {
				label values `v' s_trc_booklevel
				}
			// NOTE: For some reason the code above isn't working to assign value label. Return to this!
			
			label define trc_bechmark 1 "Far Below Proficient" 2 "Below Proficient" 3 "Proficient" 4 "Above Proficient"
			label values s_trc_pb_f trc_bechmark
			label values s_trc_pb_m trc_bechmark
			label values s_trc_pb_s trc_bechmark
	
save "$data_temp/trc", replace

}
{ // (Scholastic) Reading Inventory (RI/SRI) 

/*
DCPS shared different types of files:
- SRI (for later grades)
- RI (for earlier grades) ONLY HAVE RIGHT NOW FOR 2019-20 SCHOOL YEAR 

BUT, I think the two files may be overlapping?
*/

	// Load and append across two files 
	
		// "RI" files
		
		import excel using "$data_raw/RI 2019-20 BOY StudentSummary_FINAL.xlsx", clear firstrow
		tempfile temp 
		save `temp'

		import excel using "$data_raw/RI 2019-20 MOY StudentSummary_FINAL.xlsx", clear firstrow
		append using `temp'

		// Rename variables for consistency
			
			rename schoolcode schoolid
			rename studentid localid // NOTE no usi
			rename grade s_grade 
			*accountability_flag 
			*testdate 
			rename lexile_score s_sri_ss
			rename performance_band s_sri_pb
			rename school_year_start schoolyear_fall 
			*assessment_type 
			rename assessment_window term
			
			destring schoolyear, replace
			
			drop accountability_flag testdate assessment_type
			
		tempfile ri
		save `ri'
		
		// "SRI" files
		
		import excel using "$data_raw/SRI.xlsx", clear firstrow
		
		// Rename variables for consistency
			
			rename schoolcode schoolid
			rename lexile_score s_sri_ss
			rename benchmarkperiod term
			rename grade s_grade
			rename schoolyear schoolyear_fall
			rename performance_band s_sri_pb
			
			*tab schoolyear_fall, m
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
			
		append using `ri'
	
	// Clean
		
		drop cohort
		drop usi // don't have for RI file
		
		drop if s_grade==1 // only 3 observations
		*tab schoolyear s_grade, m
			// NOTE: Only 17 observations in 2014 (grade 2 only), and 20 in 2015 (grade 3 only). 
		drop if schoolyear<=2015
		// NOTE: Also only have 2 5th graders in 2016, 3 6th graders in 2017, and 1 7th grader in 2018.
		drop if s_grade==5 & schoolyear==2016
		drop if s_grade==6 & schoolyear==2017
		drop if s_grade==7 & schoolyear==2018
		
		// Term
			
			replace term = "f" if term=="BOY"
			replace term = "m" if term=="MOY"
			replace term = "s" if term=="EOY"
			
			drop if term=="" // 66 observations
		
		// Performance level
			
			replace s_sri_pb = "1" if s_sri_pb == "Below Basic"
			replace s_sri_pb = "2" if s_sri_pb == "Basic"
			replace s_sri_pb = "3" if s_sri_pb == "Proficient"
			replace s_sri_pb = "4" if s_sri_pb == "Advanced"
			destring s_sri_pb, replace
		
		*count if s_sri_ss==.
		*count if s_sri_pb==.
		
		// Standardize scores
			
			*hist s_sri_ss
				// NOTE: Distrbution looks mostly normal, except for big spike at 0
			bysort schoolyear s_grade term: center s_sri_ss, gen(s_sri_ss_sd) standardize
			
		// Reshape wide by term
			
			duplicates drop
			*unique localid s_grade schoolyear_fall term
			*duplicates tag localid schoolyear_fall term, gen(temp)
				// No duplicates!
			
			// Don't need schoolid or grade right now, so drop that
			drop schoolid s_grade
			
			rename s_sri* s_sri*_
			
			reshape wide s_sri*, i(localid schoolyear_fall) j(term) string
	
		// Label performance bands
			
			label define sri_bechmark 1 "Below Basic" 2 "Basic" 3 "Proficient" 4 "Advanced"
			label values s_sri_pb_f sri_bechmark
			label values s_sri_pb_m sri_bechmark
			label values s_sri_pb_s sri_bechmark
	
save "$data_temp/sri", replace
	
}
{ // i-Ready (Math diagnostic assessment - K-8)

import excel using "$data_raw/i-Ready.xlsx", clear firstrow
	
	// Rename variables for consistency
	// Keeping performance band to have an indicator of on, above, or below level. There are a lot of missing points in that variable, though most all of them appear to only be missing when the test was administered in the year 2015.
	
		rename grade s_grade
		rename scalescore s_iready_ss 
	
	// Clean
		
		// Not sure why there already are duplicates, but there are a lot
			
			duplicates drop
		
		// School year and term (need to pull from the date variable)
		
			gen year = year(testdate)
			gen month = month(testdate)
			*tab year month, m
			
			gen schoolyear_fall = year if month>=8 & month<=12
			replace schoolyear_fall = year - 1 if month==5 | month==6
			
			gen term = "f" if month>=8 & month<=12
			replace term = "s" if month==5 | month==6
			
			*tab schoolyear term, m
				// NOTE: No spring 2019-20 school year, which makes sense (since this year).
				
			*drop month year testdate
			
		// Grade Level
			
			replace s_grade = "0" if s_grade=="K"
			destring s_grade, replace

		// Performance Band/Grade Level
			
			// 3 categories of performance levels, but lots of missing-ness in spring 2014 and fall 2015
			
			gen s_iready_pb = .
			replace s_iready_pb = 1 if performance_band == "Below Level" | (regexm(ongrdlvl, "Below") & performance_band=="")
			replace s_iready_pb = 2 if performance_band == "On Level" // **can't differentiate "on" from "above"... (regexm(ongrdlvl, "Below") & performance_band=="")
			replace s_iready_pb = 3 if performance_band == "Above Level"
			
			drop performance_band performancelevel
			/*
			// At/Below Grade Level Categoriees Vary by Year
			//	2014-2017: 2+ grade levels below, 1 grade level below, on/above grade level
			//	2018-2019: 3+ grade levels below, 2 grade levels below, 1 grade level below, on level early, on level mid/late
			gen s_iready_gl = .
			replace s_iready_gl = 1 if ongrdlvl == "3+ Grade Levels Below"
			replace s_iready_gl = 2 if ongrdlvl == "On Level"
			replace s_iready_gl = 3 if ongrdlvl == "Above Level"
			destring s_iready_pb, replace
			drop performance_band
			*/
			drop ongrdlvl
		
		*count if s_iready_ss==.
		*count if s_iready_pb==.
			// 5,885 students missing performance bands but have scaled scores.
			//	Fall from 2015 and spring 2014.
		*tab schoolyear term if s_iready_pb==., m
		
		// Standardize scores
			
			bysort schoolyear s_grade term: center s_iready_ss, gen(s_iready_ss_sd) standardize
		
		// Reshape wide by term
			
			drop s_grade testdate year month cohort
			rename s_iready* s_iready*_
			reshape wide s_iready_ss_ s_iready_pb_ s_iready_ss_sd_, i(localid usi schoolyear) j(term) string
		
		// NOTE: Unique by student-year at this point
		
		// Label performance bands
		
			label define iready_bechmark 1 "Below Level" 2 "On Level" 3 "Above Level"
			label values s_iready_pb_f iready_bechmark
			label values s_iready_pb_s iready_bechmark
	
	// Make sure unique by usi schoolyear
		
		duplicates drop usi schoolyear, force // not dropping anyone, which is good
		
save "$data_temp/iready", replace
}
{ // PARCC (high-stakes test in grades 3-8...we have through 6th grade for some)

import excel using "$data_raw/PARCC.xlsx", clear firstrow
*import excel using "$data_raw/Old/PARCC_121619.xlsx", clear firstrow
	// Rename variables for consistency
		
		rename schoolcode schoolid
		drop schoolid
		rename schoolyear schoolyear_fall
		rename ela_testcode ela_test_grade
		rename ela_scale_score s_parcc_ss_ela
		rename ela_perf_level s_parcc_pb_ela
		rename math_testcode math_test_grade
		rename math_scale_score s_parcc_ss_math
		rename math_perf_level s_parcc_pb_math
		
	// Clean
		
		// Schoolyear
			
			*tab schoolyear_fall, m
			tostring schoolyear_fall, replace
			foreach y in 2012 2013 2014 2015 2016 2017 2018 2019 {
				replace schoolyear_fall = "`y'" if regexm(schoolyear_fall, "`y'")
				}
			destring schoolyear_fall, replace
			
			// 4 observations in 2014 -- drop these
				
				drop if schoolyear==2014
		
		// Merge in demos to look at score ranges for subgroups
		
			destring localid, replace
			destring usi, replace
			merge m:1 localid schoolyear using "$data_temp/demographics", keep(1 3) keepusing(s_lep s_sped) nogen
				// NOTE: 429 observations in PARCC data not in demos file. But, majority (25,372) merging.
	
		// Test form
			
			*tab ela_test_grade, m
			foreach g in 3 4 {
				replace ela_test_grade = "`g'" if regexm(ela_test_grade, "`g'")
				}
			destring ela_test_grade, replace
			replace ela_test_grade = 6 if ela_test_grade==7 // just one student, and can't standardize score with just one observation
				// NOTE: 1 just missing ELA test grade. But 3rd grade in math
			replace ela_test_grade = 3 if ela_test_grade==.
				
			*tab math_test_grade, m
			foreach g in 3 4 {
				replace math_test_grade = "`g'" if regexm(math_test_grade, "`g'")
				}
			replace math_test_grade = "6" if math_test_grade=="7" // just one student, and can't standardize score with just one observation
			replace math_test_grade = "" if math_test_grade=="Algebra I" // three students have this math test, but scores are missing/
			destring math_test_grade, replace
				// NOTE: 3 missing math test grade, but all grade 6 in ELA
			replace math_test_grade = ela_test_grade if math_test_grade==.
				
		// Look at valid/invalid scores
			
			*tab ela_assessment, m
				// NOTE: 98% have "valid score".
				//	526 have "test score taken", and scores/performance bands are missing.
				//	22 more have "incomplete test" and score here also missing.
				//	A handful have invalidated score, some that still have scores
				//	1 has missing value here, but invalidated score in math
			replace ela_assessment = "Invalidated Score" if ela_assessment==""
			foreach v of varlist s_parcc_pb_ela s_parcc_ss_ela {
				replace `v' = "" if ela_assessment=="Invalidated Score"
				}
			
			*tab math_assessment, m
				// NOTE: 97.6% valid score.
				//	550 have test not taken, and scores blank
				//	39 have incomplete test, and score blank
				//	25 have invalidated score
			foreach v of varlist s_parcc_pb_math s_parcc_ss_math {
				replace `v' = "" if math_assessment=="Invalidated Score"
				}	
		
		// Destring scaled scores and performance bands
			
			foreach v of varlist s_parcc_pb_ela s_parcc_ss_ela s_parcc_pb_math s_parcc_ss_math {
				replace `v' = "" if `v'=="."
				destring `v', replace
				}
			
			*summ s_parcc_ss_ela, detail 
			*count if s_parcc_ss_ela>850 & s_parcc_ss_ela!=. // 171 have scores above 850, which should be maximum
			*summ s_parcc_ss_math, detail
			*count if s_parcc_ss_math>850 & s_parcc_ss_math!=. // 169 have scores above 850, which should be maximum
					
		// Look for why some students (n = 68) have scores above 850 (which should be highest score on all tests)
			
			*bro if (s_parcc_ss_ela>850 & s_parcc_ss_ela!=.) | (s_parcc_ss_math>850 & s_parcc_ss_math!=.)
			*tab schoolyear_fall s_sped if (s_parcc_ss_ela>850 & s_parcc_ss_ela!=.) | (s_parcc_ss_math>850 & s_parcc_ss_math!=.), m
				// NOTE: All have SPED indicator. BUT, not all students with SPED indicator have scores above 850.
				//	Looks like it is an issue in 2015 and 2016, but not in later years. 
			
			foreach v of varlist s_parcc_ss_ela s_parcc_ss_math {
				replace `v' = . if `v'>850
				}
		
		// Look at some missingness issues
		
			*count if s_parcc_ss_ela==.  // 751 missing
			*count if s_parcc_pb_ela==. // 580 missing
			*count if s_parcc_ss_math==. // 783 missing
			*count if s_parcc_pb_math==. // 614 missing
			
			drop if s_parcc_ss_ela==. & s_parcc_ss_math==. // 726 observations, across school years
		
		// Standardize scores
			
			bysort schoolyear ela_test_grade: center s_parcc_ss_ela, gen(s_parcc_ss_ela_sd) standardize
			bysort schoolyear math_test_grade: center s_parcc_ss_math, gen(s_parcc_ss_math_sd) standardize
		
		// Get down to one test score per year
			
			*unique localid schoolyear_fall // No duplicates!
			/*
			duplicates tag localid schoolyear_fall, gen(temp)

			collapse (max) s_parcc_ss_ela s_parcc_pb_ela s_parcc_ss_ela_sd ///
				s_parcc_ss_math s_parcc_pb_math s_parcc_ss_math_sd ///
				, by(localid usi schoolyear) 
			*/
			
		// Clean up performance levels
			
			label define parcc_bechmark 1 "Did Not Yet Meet Expectations" 2 "Partially Met Expectations" 3 "Approached Expectations" 4 "Met Expectations" 5 "Exceeded Expectations"
			label values s_parcc_pb_ela parcc_bechmark
			label values s_parcc_pb_math parcc_bechmark
	
save "$data_temp/parcc", replace

}
}
*-------------------------------------------------------*
*	Teacher Observation/Evaluation Data (Xinyi/Marissa)	*
*-------------------------------------------------------*
if $teachers { 	
{ // Append IMPACT files by year (these exclude demos)
{ 	// 2009-10 to 2014-15: use Teaching and Learing Framework (with some differences in 2009-10)

// 2009-2010 & 2010-2011 are in one spreadsheet
//	Also have 2011-12 here -- as well as in separate spreadsheet. Pull off teacher demos here for 2011-12, as
//		have more information than in the other spreadsheet.
	
	// Excel file take a long time to open, so save as a Stata file first
	*import excel using "$data_raw/IMPACT/2009-10 and 2010-11/(UNMASKED) 2012-06-11 UVA Data Request 09-10, 10-11, 11-12_edited", clear cellrange(A2:AEG4838) firstrow
	*save "$data_raw/IMPACT/2009-10 and 2010-11/(UNMASKED) 2012-06-11 UVA Data Request 09-10, 10-11, 11-12_edited", replace
	use "$data_raw/IMPACT/2009-10 and 2010-11/(UNMASKED) 2012-06-11 UVA Data Request 09-10, 10-11, 11-12_edited", clear
	
	// For now, focus on the variables that we care most about
		
		// Keep variables most consistent with other years
		keep id employeeid sch1id* sch2id* schoolid* schtype* grade* subject* pov* ///
			gender* race* hiredate* optin* impactplus* /// step ward cluster union not found
			group_impact* tchr_impact* adjscore* adjrating* ///
			consequence* origconseq* terminated* impactplus* yrsservcred* bonus* step* /// birthdate not found
			tlf* appeal* origscore* origrating* iva* ivaread* ivamath* ///
			farm* teachexp* ed_* score_* rating_* appeal*
				// vars in the last line don't appear in other years, but might be useful, so kept them
		rename schtype_sch1_* schtype_*
		
		// Drop some variables we don't need right now
		drop ivamath_g?_1011 ivamathlikely_1011 ivamathactual_1011 ivamathdiff_1011 ///
			ivareadlikely_1011 ivareadactual_1011 ivareaddiff_1011 ///
			sch?id* sch*1112 /// sch1id_1112 schoolid_1112 sch2id_1112 schoolid_sch2_1112 schtype_sch1_1112 ///
			group_impact_1112 group_impact		
		
		// Drop 2009-10 TLF scores, as fairly different from other TLF years, AND only need TLF as outcome measure
		//	in years subsequent to initial IMPACT ratings
		gen prname_0910 = "TLF" if tlf_0910!="N/A"
		gen prname_1011 = "TLF" if tlf_1011!="N/A"
		drop tlf*0910
		
		// Three scores/ratings in 2010, and I think numbering of years may be off
		drop score_* rating_*
	
	// Reshape
		
		rename *_0910 *_9910 // need to change, as reshaping makes "0910" "910"
		
		unab vars: *_*
		// local stubs
		foreach var of local vars {
			qui: local stub = substr("`var'",1,length("`var'")-4)
			qui: local stubs : list stubs | stub 
			}
		/* Question: purpose of the list command?*/
		
		qui: reshape long `stubs' , i(employeeid id) j(schoolyear_fall)

		qui: rename *_ *

		replace schoolyear_fall = 2009 if schoolyear_fall == 9910
		replace schoolyear_fall = 2010 if schoolyear_fall == 1011
		replace schoolyear_fall = 2011 if schoolyear_fall == 1112
	
	// There are 2,440 observations (~1,200 per school year) where almost all variables are "N/A": drop
	//	Dropping these gets us down to a similar number of teachers as in other years (~3.6K)	
		
		drop if group_impact=="N/A"
	
	// Clean vars causing appending issues 
		
		replace employeeid = "." if employeeid == ""|employeeid == "N/A"
		drop if employeeid == "Not Real Employee - Fake"
		destring employeeid, replace
			
		rename grade gradep 
		rename subject subjectp
			
		foreach v in adjscore origscore bonus yrsservcred iva ivaread ivamath {
			qui: replace `v' = "." if `v' == "N/A" | `v' == ""
			qui: destring `v', replace
			}
	
	// Pull off demos to clean separately, and then drop 2011-12
		
		preserve
			keep employeeid id schoolyear hiredate step teachexp teachexp_dcps race gender ed
			replace step = "" if step=="N/A"
			destring step, replace
			save "$data_temp/teacher_demos_091011", replace
		restore
		*drop hiredate race gender ed step teachexp teachexp_dcps 
		drop if schoolyear==2011
	
	// Merge in rater information (only need for 2010-11!)
	
		tempfile temp
		save `temp'
		
		import excel using "$data_raw/IMPACT/2009-10 and 2010-11/(UNMASKED) 2012-11-19 Assessor and Assessment Date Information 0910, 1011_edited", clear sheet("2010-11") cellrange(A2:AO3484) firstrow
		keep id raterid_* obsdate_* // employeeid 
		gen schoolyear_fall = 2010
		
		foreach v in raterid_1p raterid_2p raterid_3p raterid_1m raterid_2m { // employeeid 
			replace `v'= "" if `v'=="N/A"
			destring `v', replace
			}
		foreach v of varlist obsdate_1p obsdate_3p {
			gen temp = date(`v', "MDY")
			drop `v' 
			rename temp `v'
			}
		format obsdate* %td
		
		merge 1:1 id schoolyear using `temp', nogen keep(2 3)
			// NOTE: No merges from 2009 because set up that way.
			//	5 observations in rater file not in main file. Drop these.
			//	111 observations from 2010 don't have rater information, but most of these have "N/A" for TLF scores. Keep.
	
	// Initial cleaning/renaming of observations
		
		rename tlf* pr*
		rename pr*all* pr**
		foreach v of varlist pr* {
			qui: replace `v' = "" if `v'=="N/A"
			qui: destring `v', replace
			}
		
		// For master educator, looks like number of cycles are off
		//	In observation score file, have 1m and 3m; but in rater file have 1m and 2m.
		//	Change cycle 3 to 2.
		rename *3m *2m
			//NOTE: Could 3m mean one master cycle for sch2? There should be only 3 admin cycles as well
			
		// Create pr name variables to match other years
		foreach n in 1p 2p 3p 4p 5p 1m 2m {
			qui: gen prname_`n' = "TLF" if pr_`n'!=.
			}
			
	// Initial cleaning of IMPACT decision variables	
		
		replace appeal = "Yes" if appeal=="yes"
		
		// In 2009, have "terminated" variables, but not giving much more than consequence
		*tab terminatedreason terminated, m
		*tab consequence terminated if schoolyear==2009, m
		*tab terminatedreason consequence if schoolyear==2009, m
		drop terminated*
		
		// In 2010, have consequence and original consequence, with 6 people that originally were separated
		//	but seems like appealled
		*tab consequence origconseq, m 
		drop origconseq
		
		// IMPACTplus
		*tab bonus if impactplus=="Yes", m // 583 with bonus; 93 missing bonus amount but say "yes" to impactplus
		replace consequence = "IMPACTplus" if impactplus=="Yes"
		*drop impactplus*
		
		// Service credit
		drop stepbump* 
			// step bump only happens after two years of highly effective rating, so these variables can't be
			//	for 2009. And, have years of service credit for 2010 in this file and 2011 in a separate file.
		
		// Step
			// NOTE: I believe that step is likely to be the same in the first couple of years of IMPACT.
			//	So, probably fine that have just one variable here (rather than by year).
		replace step = "" if step=="N/A"
		destring step, replace
		
	save "$data_temp/teacher_impact_scores_09-10", replace
	
// 2011-12
	
	import excel using "$data_raw/IMPACT/SY 11-12 IMPACT Data_edited", clear cellrange(A2:GJ3454) firstrow 
	
	gen schoolyear_fall = 2011
	order schoolyear_fall
	
	keep schoolyear_fall id employeeid sch1id sch2id schoolid* schtype gradep subjectp ///
		birthdate gender race startdate step ward cluster optin union ///
		group_impact tchr_impact pov adjscore adjrating consequence yrsservcred bonus /// lift not found
		pr* appeal origscore origrating iva ivaread ivamath 
	
	// Clean variables that create append issues across school years
	
	 // destring: employeeid, ward, cluster
		replace employeeid = "." if employeeid == ""|employeeid == "N/A"
		drop if employeeid == "Not Real Employee - Fake"
		
		replace ward = "." if ward=="N/A"
		replace cluster = "." if cluster=="N/A"
		
		foreach v in employeeid ward cluster {
			destring `v', replace
		}
	
	// tostring: appeal, adjscore, optin
		tostring appeal, replace
		replace appeal = "" if appeal =="."
	
		tostring adjscore, replace
		tostring startdate, replace
		tostring optin, replace
		
	save "$data_temp/teacher_impact_scores_11", replace
	
// 2012-13

	import excel using "$data_raw/IMPACT/SY 12-13 IMPACT Data_edited", clear cellrange(A2:JA3400) firstrow 
	
	gen schoolyear_fall = 2012
	order schoolyear_fall
	
	// For now, focus on the variables that we care most about
		
		keep schoolyear_fall id employeeid sch1id sch2id schoolid* schtype gradep subjectp ///
			birthdate gender race startdate step ward cluster optin union ///
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcps* obsdate* appeal origscore origrating iva ivaread ivamath
	
	// Clean up appeal/original score -- looks like no appeals here?!?
		
		foreach v in appeal origrating {
			tostring `v', replace
			replace `v' = "" if `v'=="."
			}
	
	// Clean up ward, which is creating append issues across school years
		
		replace ward = "." if ward=="N/A"
		destring ward, replace
		//NOTE: We also see ward==0 or "." in other years; not sure if these mean the same as "N/A".
	
	// Clean up rater ID
		
		*bro dcps*
		foreach v of varlist dcpsid_1p dcpsid_3p dcpsid_1m dcpsid_2m {
			replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
			destring `v', replace
			}
		rename dcpsid_* raterid_*
		format obsdate* %td
		
	*tempfile 2012
	*save `2012'
	save "$data_temp/teacher_impact_scores_12", replace
	
// 2013-14 

	import excel using "$data_raw/IMPACT/SY 13-14 IMPACT Data_edited", clear cellrange(A2:IS3492) firstrow 
	
	gen schoolyear_fall = 2013
	order schoolyear_fall	 

		keep schoolyear_fall id employeeid sch1id sch2id schoolid* schtype gradep subjectp ///
			birthdate gender race startdate step ward cluster optin union ///
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcps* obsdate* appeal origscore origrating iva ivaread ivamath
	
	// Clean up pr7formal, which is creating append issues across school years
		destring pr7formal, replace
	
	// Clean up rater ID
		
		*bro dcps*
		foreach v of varlist dcpsid_1p dcpsid_3p dcpsid_1m dcpsid_2m {
			replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
			destring `v', replace
			}
		rename dcpsid_* raterid_*
		format obsdate* %td
		
	*tempfile 2013
	*save `2013'
	save "$data_temp/teacher_impact_scores_13", replace
	
// 2014-15 

	import excel using "$data_raw/IMPACT/SY 14-15 IMPACT Data_edited", clear cellrange(A2:IM3690) firstrow 
	
	gen schoolyear_fall = 2014
	order schoolyear_fall	 
	
	// For now, focus on the variables that we care most about
	
		keep schoolyear_fall id employeeid sch1id sch2id schoolid* schtype gradep subjectp ///
			birthdate gender race startdate step ward cluster optin union ///
			group_impact lift pov adjscore adjrating consequence yrsservcred bonus /// tchr_impact /// variable tchr_impact consequence not found
			pr* dcps* obsdate* appeal origscore origrating iva ivaread ivamath

	// Since all observations have lift values, assume that they are all teachers.
		gen tchr_impact = "teacher" 
	
	// For now, drop variables that are missing all values and creating append issues
		drop gender race startdate
	
	// Clean up cluster, which is creating append issues across school years
		
		gen temp = .
		forvalues c = 1/9 {
			replace temp = `c' if regexm(cluster, "`c'")
			}
		// NOTE: We also see "Central Office" here.
		drop cluster
		rename temp cluster
	
	// Clean up rater ID
		
		*bro dcps*
		foreach v of varlist dcpsid_1m dcpsid_2m {
			replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
			destring `v', replace
			}
		rename dcpsid_* raterid_*
		format obsdate* %td
	
	*tempfile 2014
	*save `2014'
	save "$data_temp/teacher_impact_scores_14", replace
	
// 2015-16

	import excel using "$data_raw/IMPACT/SY 15-16 IMPACT Data_edited", clear cellrange(A2:IR6959) firstrow
	
	gen schoolyear_fall = 2015
	order schoolyear_fall
	
	// For now, focus on the variables that we care most about
		
		keep schoolyear_fall id employeeid sch1id sch2id schoolid* gradep subjectp /// schtype
			ward cluster optin union /// birthdate gender race startdate step 
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcps* obsdate* appeal inscore inrating iva // ivaread ivamath
	
	// Rename original ratings variables
	
		rename inscore origscore
		rename inrating origrating
	
	// Clean up rater ID (all clean!)
		
		rename dcpsid_* raterid_*
		format obsdate* %td
	
	*tempfile 2015
	*save `2015'
	save "$data_temp/teacher_impact_scores_15", replace

// Append all and finalize

	clear
	foreach y in 11 12 13 14 15 {
		append using "$data_temp/teacher_impact_scores_`y'" // `20`y''
		}
	replace adjscore = "" if adjscore=="No Score"
	destring adjscore, replace
		
	append using "$data_temp/teacher_impact_scores_09-10"
					
	// Clean PR
		
		// Clean pr? and pr?formal
			foreach s in 1 2 3 4 5 6 7 8 9 {
				replace pr`s'formal = pr`s' if pr`s'formal==.
				drop pr`s'
				rename pr`s'formal pr`s'
			}
			
			drop pr10* //NOTE: TLF doesn't have a 10th standard but other rubrics do
			
		// Clean PR names
		rename (pr_?p pr_?m) (pr_?p_avg pr_?m_avg)
		
		rename (pr1 pr2 pr3 pr4 pr5 pr6 pr7 pr8 pr9) (lead_lessons_avg explain_clearly_avg engage_all_levels_avg provide_ways_avg check_understanding_avg respond_understanding_avg develop_understanding_avg maximize_time_avg build_classroom_avg) 
		
		rename (pr1_?p pr2_?p pr3_?p pr4_?p pr5_?p pr6_?p pr7_?p pr8_?p pr9_?p) (lead_lessons_?p explain_clearly_?p engage_all_levels_?p provide_ways_?p check_understanding_?p respond_understanding_?p develop_understanding_?p maximize_time_?p build_classroom_?p)
		
		rename (pr1_?m pr2_?m pr3_?m pr4_?m pr5_?m pr6_?m pr7_?m pr8_?m pr9_?m) (lead_lessons_?m explain_clearly_?m engage_all_levels_?m provide_ways_?m check_understanding_?m respond_understanding_?m develop_understanding_?m maximize_time_?m build_classroom_?m)
			
		/*
		// Clean TLF names (2009)
		
		rename (tlf1 tlf2 tlf3 tlf4 tlf5a tlf5b tlf5c tlf6 tlf7 tlf8 tlf9a tlf9b tlf9c) (y09focus_objectives_avg y09deliver_clearly_avg y09engage_learning_avg y09target_styles_avg y09check_understanding_avg y09respond_misunderstanding_avg y09probe_understanding_avg y09maximize_time_avg y09invest_learning_avg y09interact_students_avg y09student_behavior_avg y09reinforce_behavior_avg y09address_behavior_avg)
		
		rename (tlf1_?p tlf2_?p tlf3_?p tlf4_?p tlf5a_?p tlf5b_?p tlf5c_?p tlf6_?p tlf7_?p tlf8_?p tlf9a_?p tlf9b_?p tlf9c_?p) (y09focus_objectives_?p y09deliver_clearly_?p y09engage_learning_?p y09target_styles_?p y09check_understanding_?p y09respond_misunderstanding_?p y09probe_understanding_?p y09maximize_time_?p y09invest_learning_?p y09interact_students_?p y09student_behavior_?p y09reinforce_behavior_?p y09address_behavior_?p)
		
		rename (tlf1_?m tlf2_?m tlf3_?m tlf4_?m tlf5a_?m tlf5b_?m tlf5c_?m tlf6_?m tlf7_?m tlf8_?m tlf9a_?m tlf9b_?m tlf9c_?m) (y09focus_objectives_?m y09deliver_clearly_?m y09engage_learning_?m y09target_styles_?m y09check_understanding_?m y09respond_misunderstanding_?m y09probe_understanding_?m y09maximize_time_?m y09invest_learning_?m y09interact_students_?m y09student_behavior_?m y09reinforce_behavior_?m y09address_behavior_?m)
		
		*NOTE: probably can match 2009 rubrics with TLF of the other years; 
		*2009 does have a tlf5 and tlf9, which should be the average of the substandards.
		
		drop tlf?_allm tlf??_allm tlf?_allp tlf??_allp 
		*NOTE: drop these for now because we don't have equivalent data in other years.
		*/
	
	save "$data_temp/teacher_impact_scores_09-15", replace
}
{ 	// 2016-17 to 2019-20: use Essential Practices	

// 2016-17
	
	import excel using "$data_raw/IMPACT/SY 16-17 IMPACT Data_edited", clear cellrange(A2:GC7015) firstrow
	
	gen schoolyear_fall = 2016
	order schoolyear_fall
	
	// For now, focus on the variables that we care most about
	
		keep schoolyear_fall id employeeid sch1id sch2id schoolid* gradep subjectp /// schtype
			birthdate gender race startdate step ward cluster optin union ///
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcpsid_* iva ivaread ivamath // obsdate*
			
	// For now, drop variables that are missing all values and creating append issues
		drop gender race startdate

	// Clean up cluster, which is creating append issues across school years
		
		gen temp = .
		forvalues c = 1/9 {
			replace temp = `c' if regexm(cluster, "`c'")
			}
		// NOTE: We also see "Central Office" and "Cluster X" and not sure what these are.
		drop cluster
		rename temp cluster
	
	// Clean up rater ID
		
		*bro dcps*
		foreach v of varlist dcpsid_1p dcpsid_2p dcpsid_4p dcpsid_6p {
			replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
			destring `v', replace
			}
		rename dcpsid_* raterid_*
	
	*tempfile 2016
	*save `2016'
	save "$data_temp/teacher_impact_scores_16", replace
	
// 2017-18
	
	import excel using "$data_raw/IMPACT/SY 17-18 IMPACT Data_edited", clear cellrange(A2:FV6914) firstrow
	
	gen schoolyear_fall = 2017
	order schoolyear_fall
	
	// For now, focus on the variables that we care most about
		
		keep schoolyear_fall id employeeid sch1id sch2id schoolid* gradep subjectp /// schtype
			ward cluster optin union /// birthdate gender race startdate step 
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcpsid_* iva ivaread ivamath // obsdate*
		
		// variables schtype birthdate gender race startdate step not found
	
	// Clean up rater ID
		
		*bro dcps*
		foreach v of varlist dcpsid_1p dcpsid_2p {
			replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
			destring `v', replace
			}
		rename dcpsid_* raterid_*
			
	*tempfile 2017
	*save `2017'
	save "$data_temp/teacher_impact_scores_17", replace
	
// 2018-19

	import excel using "$data_raw/IMPACT/SY 18-19 IMPACT Data_edited", clear cellrange(A2:FO7313) firstrow

	gen schoolyear_fall = 2018
	order schoolyear_fall

	// For now, focus on the variables that we care most about
		
		keep schoolyear_fall employeeid schoolid* gradep subjectp /// id sch1id sch2id schtype
			ward cluster optin union /// birthdate gender race startdate step 
			group_impact tchr_impact lift pov adjscore adjrating consequence yrsservcred bonus /// 
			pr* dcpsid_* iva ivaread ivamath // obsdate*
		  
		// variables not found: id sch1id schtype birthdate gender race startdate step not found
		
	// Clean up cluster, which is creating append issues across school years
		
		gen temp = .
		forvalues c = 1/9 {
			replace temp = `c' if regexm(cluster, "`c'")
			}
		// NOTE: We also see "Central Office" and "Cluster X" and not sure what these are.
		drop cluster
		rename temp cluster
	
	// Clean up rater ID (already clean!)
		
		rename dcpsid_* raterid_*
			
	*tempfile 2018
	*save `2018'
	save "$data_temp/teacher_impact_scores_18", replace

// 2019-20 

	import excel using "$data_raw/IMPACT/SY 19-20 IMPACT Data_edited", clear cellrange(A2:FF7565) firstrow
	
	gen schoolyear_fall = 2019
	order schoolyear_fall

	// For now, focus on the variables that we care most about
		
		keep schoolyear_fall employeeid schoolid* gradep subjectp /// id sch1id sch2id schtype 
			ward cluster union /// birthdate gender race startdate step optin
			group_impact tchr_impact lift pov adjscore adjrating consequence /// yrsservcred bonus /// 
			pr* dcpsid_* iva ivaread ivamath // obsdate*
		  
		// variables not found: id sch1id schtype birthdate gender race startdate step yrsservcred bonus optin
		
	// Clean up cluster, which is creating append issues across school years
		
		gen temp = .
		forvalues c = 1/9 {
			replace temp = `c' if regexm(cluster, "`c'")
			}
		// NOTE: We also see "Central Office" and "Cluster X" and not sure what these are.
		drop cluster
		rename temp cluster
		
	// Clean up prname_*p, which is creating append issues across school years
	
		tostring prname_1p prname_2p prname_3p prname_4p prname_5p prname_6p, replace
	
	// Clean up rater ID (already clean!)
		
		rename dcpsid_* raterid_*
		
	*tempfile 2019
	*save `2019'
	save "$data_temp/teacher_impact_scores_19", replace
	
// Append 16-19 and clean PR names	
	
	clear
	foreach y in 16 17 18 19{
		append using "$data_temp/teacher_impact_scores_`y'" // `20`y''
		}
		
	replace adjscore = "" if adjscore=="No Score"
	destring adjscore, replace
	
	//clean PR names
		drop pr6* pr7* pr8* pr9* pr10* 
			//NOTE: EP only has 5 standards but other rubrics have more
		
		rename pr_?p pr_?p_avg
			
		rename (pr1 pr2 pr3 pr4 pr5) (cultivate_community_avg rigorous_content_avg lead_exp_avg maximize_ownership_avg respond_evidence_avg) 
		
		rename (pr1_?p pr2_?p pr3_?p pr4_?p pr5_?p) (cultivate_community_?p rigorous_content_?p lead_exp_?p maximize_ownership_?p respond_evidence_?p)
		
		replace prname = pr_name if mi(prname)
		drop pr_name
			
	save "$data_temp/teacher_impact_scores_16-19", replace
	
}	
{	// Raters

// 2009-10 (unique by id)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 Assessor and Assessment Date Information 0910, 1011_V2.xlsx", clear firstrow sheet("2009-10")
	rename UniqueID id
	rename DCPSEID employeeid
	drop if employeeid=="Not Real Employee - Fake"
	replace employeeid = "" if employeeid=="N/A"
	destring employeeid, replace
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	rename AB obsdate_4p
	rename AH obsdate_5p
	rename AN obsdate_6p
	foreach v of varlist obsdate_1p obsdate_3p obsdate_1m obsdate_2m {
		gen temp = date(`v', "MDY")
		drop `v' 
		rename temp `v'
		}
	format obsdate* %td
	
	rename H raterid_1p
	rename N raterid_2p
	rename T raterid_3p
	rename Z raterid_4p
	rename AF raterid_5p
	rename AL raterid_6p
	rename MECycle?AssessorIDDCPSID raterid_?m
	foreach v of varlist raterid_1p raterid_2p raterid_3p raterid_5p raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	rename I raterrace_1p
	rename O raterrace_2p
	rename U raterrace_3p
	rename AA raterrace_4p
	rename AG raterrace_5p
	rename AM raterrace_6p
	rename MECycle?AssessorIDRaceEt raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2009
	
	save "$data_temp/teacher_impact_raters_09-10", replace
	
// 2010-11 (unique by id)

	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 Assessor and Assessment Date Information 0910, 1011_V2.xlsx", clear firstrow sheet("2010-11")
	rename UniqueID id
	rename DCPSEID employeeid
	drop if employeeid=="Not Real Employee - Fake"
	replace employeeid = "" if employeeid=="N/A"
	destring employeeid, replace
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	rename AB obsdate_4p
	rename AH obsdate_5p
	*rename AN obsdate_6p // no round 6?
	foreach v of varlist obsdate_1p obsdate_3p {
		gen temp = date(`v', "MDY")
		drop `v' 
		rename temp `v'
		}
	format obsdate* %td
	
	rename H raterid_1p
	rename N raterid_2p
	rename T raterid_3p
	rename Z raterid_4p
	rename AF raterid_5p
	*rename AL raterid_6p
	rename MECycle?AssessorIDDCPSID raterid_?m
	foreach v of varlist raterid_1p raterid_2p raterid_3p raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	rename I raterrace_1p
	rename O raterrace_2p
	rename U raterrace_3p
	rename AA raterrace_4p
	rename AG raterrace_5p
	*rename AM raterrace_6p
	rename MECycle?AssessorIDRaceEt raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2010
	
	save "$data_temp/teacher_impact_raters_10-11", replace
	
// 2011-12 (unique by id; no race information this year)
		
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 Assessor and Assessment Date Information 1112_V2.xlsx", clear firstrow
	rename UniqueID id
	rename DCPSEID employeeid
	drop if employeeid=="Not Real Employee - Fake"
	replace employeeid = "" if employeeid=="N/A"
	destring employeeid, replace
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	rename X obsdate_4p
	rename AC obsdate_5p
	rename AH obsdate_6p
	foreach v of varlist obsdate_1p obsdate_3p obsdate_1m obsdate_2m {
		gen temp = date(`v', "MDY")
		drop `v' 
		rename temp `v'
		}
	format obsdate* %td
	
	rename H raterid_1p
	rename M raterid_2p
	rename R raterid_3p
	rename W raterid_4p
	rename AB raterid_5p
	rename AG raterid_6p
	rename MECycle?AssessorIDDCPSID raterid_?m
	foreach v of varlist raterid_1p raterid_2p raterid_3p raterid_5p raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	/*
	rename I raterrace_1p
	rename O raterrace_2p
	rename U raterrace_3p
	rename MECycle?AssessorIDRaceEt raterrace_?m
	*/
	keep id employeeid rater* obs*	
	gen schoolyear_fall = 2011
	
	save "$data_temp/teacher_impact_raters_11-12", replace
	
// 2012-13 (unique by id)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 2012-2013 IMPACT Teacher Data for UVA (January 2014 Update) for upload_v2.xlsx", clear firstrow cellrange(A3:JI3401)
	rename UniqueID id
	rename DCPSEID employeeid
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	rename II obsdate_4p
	rename IO obsdate_5p
	rename IU obsdate_6p
	format obsdate* %td
	
	rename HO raterid_1p
	rename HU raterid_2p
	rename IA raterid_3p
	rename IG raterid_4p
	rename IM raterid_5p
	rename IS raterid_6p
	rename MECycle?AssessorIDDCPSID raterid_?m
	foreach v of varlist raterid_1p raterid_3p raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	rename HP raterrace_1p
	rename HV raterrace_2p
	rename IB raterrace_3p
	rename IH raterrace_4p
	rename IN raterrace_5p
	rename IT raterrace_6p
	rename MECycle?AssessorIDRaceEt raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2012
	
	save "$data_temp/teacher_impact_raters_12-13", replace
	
// 2013-14 (unique by id)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 2013-2014 IMPACT Data (De-Identified)_v2.xlsx", clear firstrow
	rename UniqueEmployeeID id
	rename DCPSEmployeeID  employeeid
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	rename IA obsdate_4p
	rename IG obsdate_5p
	rename IM obsdate_6p
	format obsdate* %td
	
	rename HG raterid_1p
	rename HM raterid_2p
	rename PrincipalCycle3FormalAsses raterid_3p
	rename PrincipalCycle4FormalAsses raterid_4p
	rename PrincipalCycle5FormalAsses raterid_5p
	rename PrincipalCycle6FormalAsses raterid_6p
	rename MECycle?AssessorIDDCPSID raterid_?m
	foreach v of varlist raterid_1p raterid_3p raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	rename HH raterrace_1p
	rename HN raterrace_2p
	rename HT raterrace_3p
	rename HZ raterrace_4p
	rename IF raterrace_5p
	rename IL raterrace_6p
	rename MECycle?AssessorIDRaceEt raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2013
	
	save "$data_temp/teacher_impact_raters_13-14", replace
	
// 2014-15 (unique by id)

	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 2014-15 IMPACT Teacher Data_De-Identified_v2.xlsx", clear firstrow
	rename UniqueUVATeacherID id
	rename DCPSEID employeeid
	
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename PrincipalCycle?School2Cycl obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	format obsdate* %td
	
	rename UniqueAssessorIDCycle?D raterid_?p
	rename UniqueAssessorIDME?DCPS raterid_?m
	foreach v of varlist raterid_?m {
		replace `v' = "" if `v'=="N/A"
		destring `v', replace
		}
	
	rename UniqueAssessorIDCycle?R raterrace_?p
	rename UniqueAssessorIDCycle?Ra raterrace_?p
	rename UniqueAssessorIDME?Race raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2014
	
	save "$data_temp/teacher_impact_raters_14-15", replace
	
// 2015-16 (unique by id, after dropping 8 duplicates)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 SY15-16 IMPACT Data for UVA (De-ID)_V2.xlsx", clear firstrow cellrange(A2:JA6959)
	rename UVAID id
	rename DCPSEID employeeid
	
	rename PrincipalCycle4School2Cycl obsdate_4p
	rename IC obsdate_5p
	rename IM obsdate_6p
	rename PrincipalCycle?ObservationDa obsdate_?p
	rename MECycle?ObservationDate obsdate_?m
	format obsdate* %td
	
	rename PrincipalCycle?AssessorDCP raterid_?p
	rename MECycle?AssessorDCPSID raterid_?m
	
	rename PrincipalCycle?AssessorRac raterrace_?p
	rename PrincipalCycle?AssessorRa raterrace_?p
	rename MECycle?AssessorRaceEthni raterrace_?m
	
	keep id employeeid rater* obs*
	gen schoolyear_fall = 2015
	
	bysort id: gen temp = _N // 7 teachers duplicated
	drop if temp==2 & obsdate_1p==.
	drop temp
	duplicates drop id, force // just drops 1 observation
	
	save "$data_temp/teacher_impact_raters_15-16", replace
		
// 2016-17 (unique by id; no date)
		
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 SY 16-17 IMPACT Data for UVA (De-Identified)_v2.xlsx", clear firstrow cellrange(A2:GI7015)
	rename UVAID id
	rename DCPSEID employeeid
	
	rename School1Cycle?AssessorIDD raterid_?p
	foreach v of varlist raterid* {
		replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
		destring `v', replace
		}

	rename School1Cycle?AssessorRace raterrace_?p
	
	keep id employeeid rater* // obs*
	gen schoolyear_fall = 2016
	
	save "$data_temp/teacher_impact_raters_16-17", replace

// 2017-18 (unique by id; no date)

	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 SY 17-18 Teacher IMPACT data for UVA (De-ID)_v2.xlsx", clear firstrow cellrange(A2:GB6914)
	rename UVAID id
	rename DCPSEID employeeid
	
	rename School1Cycle?AssessorIDD raterid_?p
	foreach v of varlist raterid* {
		replace `v' = "" if `v'=="N/A" | `v'=="Not Real Employee - Fake"
		destring `v', replace
		}

	rename School1Cycle?AssessorRace raterrace_?p
	rename School1Cycle3AssessorIDR raterrace_3p
	
	keep id employeeid rater* // obs*
	gen schoolyear_fall = 2017
	
	save "$data_temp/teacher_impact_raters_17-18", replace

// 2018-19 (unique by employeeid, no id; no date)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 Full SY 18-19 IMPACT Data_v2.xlsx", clear firstrow
	rename StaffMemberDCPSEID employeeid
	drop if employeeid==.
	
	rename School1Cycle?AssessorDC raterid_?p
	rename School1Cycle?AssessorRa raterrace_?p
	
	keep employeeid rater* // obs*
	gen schoolyear_fall = 2018
	
	save "$data_temp/teacher_impact_raters_18-19", replace

// 2019-20 (unique by employeeid, no id; no date)
	
	import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/2021-10-29 Full SY 19-20 IMPACT Data (pre-Appeals and IMPACT+)_v2.xlsx", clear firstrow
	rename StaffMemberDCPSEID employeeid
	drop if employeeid==.
	
	rename School1Cycle?AssessorDC raterid_?p
	rename School1Cycle?AssessorRa raterrace_?p
	drop rater*_3p // Covid cut off data collection by the spring
	
	keep employeeid rater* // obs*
	gen schoolyear_fall = 2019
	
	save "$data_temp/teacher_impact_raters_19-20", replace
	
// Append and clean together
	
	use "$data_temp/teacher_impact_raters_09-10", clear
	forvalues y = 10/19 {
		local z = `y' + 1
		qui: append using "$data_temp/teacher_impact_raters_`y'-`z'"
		}
	
	drop if employeeid<0
	order id employeeid schoolyear
	
	// Fill in id/employeeid if can
		
		bysort id: egen temp = mode(employeeid)
		replace employeeid = temp if employeeid==. & temp!=.
		drop temp
		
		bysort employeeid: egen temp = mode(id)
		replace id = temp if id==. & temp!=.
		drop temp
	
	// Reshape long
		
		preserve
		keep if schoolyear>=2018
		drop *_?m *_4p *_5p *_6p
		forvalues p = 1/3 {
			rename *_`p'p *`p'
			}
		reshape long raterid raterrace obsdate, i(employeeid schoolyear_fall) j(lesson)
		tempfile temp
		save `temp'
		restore
		
		keep if schoolyear<=2017
		rename *_1m *7
		rename *_2m *8
		forvalues p = 1/6 {
			rename *_`p'p *`p'
			}
		reshape long raterid raterrace obsdate, i(id schoolyear_fall) j(lesson)
		
		append using `temp'
		drop if raterid==.
	
	// Clean rater race/ethnicity
		
		replace raterrace = "" if raterrace=="Not Reported"
		encode raterrace, gen(temp)
		bysort raterid: egen mode = mode(temp)
		replace temp = mode if temp==. & mode!=.
		drop mode raterrace
		rename temp raterrace
	
	// Reshape wide again
		
		preserve
		keep if schoolyear>=2018
		reshape wide raterid raterrace obsdate, i(employeeid schoolyear_fall) j(lesson)
		tempfile temp
		save `temp'
		restore
		
		keep if schoolyear<=2017
		reshape wide raterid raterrace obsdate, i(id schoolyear_fall) j(lesson)
		append using `temp'
		order id employeeid
		
		rename raterid? raterid_?p
		rename raterid_7p raterid_1m
		rename raterid_8p raterid_2m
		
		rename raterrace? raterrace_?p
		rename raterrace_7p raterrace_1m
		rename raterrace_8p raterrace_2m
		
		rename obsdate? obsdate_?p
		rename obsdate_7p obsdate_1m
		rename obsdate_8p obsdate_2m
	
save "$data_temp/teacher_impact_raters", replace	
	
}
{	// IMPACTPlus opt in

import excel using "$data_raw/IMPACT/New from IMPACT Team 10.29/IMPACTplus_AllYears_DBlazer_Request_10.25.xlsx", clear cellrange(A7:AT6985) firstrow
	
	rename EID employeeid
	drop if employeeid<0
	rename EverOptedIntoIMPACTplus ever_optin
	rename OptinYear year_optin
	
	rename B decision_2009
	rename C bonus_offer_2009
	rename D decision_2010
	rename E bonus_offer_2010
	rename F credit_offer_2010
	rename G decision_2011
	rename H bonus_offer_2011
	rename I credit_offer_2011
	rename J decision_2012
	rename K bonus_offer_2012
	rename L credit_offer_2012
	rename M decision_2013
	rename N bonus_offer_2013
	rename O credit_offer_2013
	rename P decision_2014
	rename Q bonus_offer_2014
	rename R credit_offer_2014
	*rename S union_2014
	rename T decision_2015
	rename U bonus_offer_2015
	rename V credit_offer_2015
	*rename W union_2015
	rename X decision_2016
	rename Y bonus_offer_2016
	rename Z credit_offer_2016
	*rename AA union_2016
	rename AB decision_2017
	rename AC bonus_offer_2017
	rename AD credit_offer_2017
	*rename AE union_2017
	rename AF decision_2018
	rename AG bonus_offer_2018
	rename AH credit_offer_2018
	*rename AI union_2018
	rename AJ decision_2019
	rename AK bonus_offer_2019
	rename AL credit_offer_2019
	*rename AM union_2019
	rename AN decision_2020
	rename AO bonus_offer_2020
	rename AP credit_offer_2020
	*rename AQ union_2020
	
	keep employeeid decision* *offer* *_optin
	
	replace ever_optin = "1" if ever_optin=="yes"
	replace ever_optin = "0" if ever_optin=="no"
	destring ever_optin, replace
	
	split year_optin, parse("-")
	destring year_optin1, replace
	drop year_optin year_optin2
	rename year_optin1 year_optin
	
	reshape long decision_ bonus_offer_ credit_offer_, i(employeeid) j(schoolyear_fall)
	rename decision_ optin_decision
	rename *offer_ *offer
	
	replace optin_decision = "Autos" if optin_decision=="" & schoolyear>year_optin
	drop if optin_decision==""
	
save "$data_temp/teacher_impact_optin", replace

}
{ 	// Append all years and save to facilitate cleaning of years altogether

use "$data_temp/teacher_impact_scores_16-19", clear
append using "$data_temp/teacher_impact_scores_09-15"

// Merge in rater information
	
	preserve
	keep if schoolyear>=2018
	merge 1:m employeeid schoolyear using "$data_temp/teacher_impact_raters", nogen keep(1 3)
		// 318 from master not in rater
	tempfile temp
	save `temp'
	restore
	
	keep if schoolyear<=2017
	bysort id schoolyear: gen temp = _N
	drop if temp==2 & tchr_impact=="Non-Teacher"
	drop temp
	merge 1:m id schoolyear using "$data_temp/teacher_impact_raters", nogen keep(1 3)
		// ~3K in master not in rater, including 1.1K from 2011, ~750 each from 2016 and 2017.
		//	Someting odd about 2011
	
	append using `temp'

// Merge in optin information

	merge m:1 employeeid schoolyear using "$data_temp/teacher_impact_optin", nogen keep(1 3)
		// 547 unique teachers in using file not in master. 108 of these have opt-in year of 2009.
		// ~22K observations from master are not in the using file. 
		//	Some of these are non-teachers, but a sizeable chunk are teachers in WTU.
	
// Clean
			
	drop sch1id sch2id birthdate // step 
		// sch1id & sch2id is UVA school id
	duplicates drop // none dropped
	order id employeeid schoolyear_fall schoolid schtype // id missing in 2018 & 2019
	
	// For now, keep teachers only
		
		*tab schoolyear tchr_impact, m
			// Have "non-teacher" in 2015 and "no" in 2016 onward. 
			//	2009 and 2010 have mostly "N/A", plus a couple of instructional coaches and other WTTU (union) members.
			//		Drop the latter, but keep all "N/A"s. Counts about match the number of teachers in other years.
		
		replace tchr_impact = "Teacher" if tchr_impact=="N/A" & schoolyear<=2010
		gen teacher = (tchr_impact=="Teacher" | tchr_impact=="teacher" | tchr_impact=="yes" )
		*bysort employeeid: egen ever_teacher = max(teacher)
		
		keep if teacher==1
		drop tchr_impact teacher
			
		*tab tchr_impact group_impact if schoolyear < 2010 
		// The result is consistent with later years where group 1-7 are teachers)
		// IMPACT groups 6 and up also shouldn't be teachers, so drop those. 
		//	Group 6 is shared teachers; group 7 is home/hospital teachers.
		//	Above that includes professional staff (e.g., student support professionals, library staff, counselors, social workers, etc.) 
		//	These folks also shouldn't have TLF scores.
		//	And, will clean the group_impact variable more below.
			
			replace group_impact = subinstr(group_impact, "Group ", "", 1)
			foreach g in 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 {
				drop if group_impact=="`g'"
				}
			drop if group_impact=="a"
			// NOTE: Drops ~525 observations, about half from group 6, and another 75 from group 7.
			
		// Can also drop people without TLF or EP as rubric
			
			replace prname = prname_1p if prname==""
			replace prname = prname_2p if prname==""
			replace prname = prname_3p if prname==""
			replace prname = "TLF" if regexm(prname, "TLF")
			replace prname = "EP" if regexm(prname, "EP")
			drop if prname!="TLF" & prname!="EP"
			
			*tab group_impact if prname!="TLF" & prname!="EP", m // mostly group 3 (special education)
			*tab subjectp if prname!="TLF" & prname!="EP", m sort // mostly autism and special education
		
	// Clean up teacher IDs
		//	In 2018 and 2019, only have employeeid...but in 09, 10, and 11 have a fair amount of missingness in employeeid.
		//	Other years have strong coverage of both id and employeeid.
		
		*tab schoolyear if employeeid==., m // mostly in 09, 10, and 11
		*tab schoolyear if id==., m // everyone missing id in 18 and 19
		
		bysort employeeid: egen temp = mode(id)
		replace id = temp if id==.
		drop temp
			// Still have ~600 missing in 18 and ~1,000 missing in 19
		bysort id: egen temp = mode(employeeid)
		replace employeeid = temp if employeeid==. // doesn't do anything
		drop temp
		
		gen impute_id = (id==. & employeeid!=.)
		replace id = employeeid if id==.
		gen impute_employeeid = (employeeid==. & id!=.)
		replace employeeid = id if employeeid==.
	
	// Background information
	
		// School information
			
			// IDs
			
				*count if schoolid != schoolid_sch1 & !mi(schoolid) & !mi(schoolid_sch1)
					// schoolid is alwasy the same with schoolid_sch1, so use schoolid as school ID variable
				
				replace schoolid = schoolid_sch1 if mi(schoolid)
				drop schoolid_sch1 schoolid_sch2
				
				// Also have 230 obs (mostly from 2010) with missing schoolid
				
					tsset id schoolyear
					sort id schoolyear
					gen schoolid_tm1 = L.schoolid
					gen schoolid_tp1 = F.schoolid
					gen schoolid_tp2 = F.schoolid_tp1
					tsset, clear
					bysort id: egen schoolid_mode = mode(schoolid)
					
					replace schoolid = schoolid_tp1 if schoolid==. & schoolid_tm1==schoolid_tp1 & schoolid_tp1!=.
					replace schoolid = schoolid_tp1 if schoolid==. & schoolid_tp1==schoolid_tp2 & schoolid_tm1==.
					replace schoolid = schoolid_mode if schoolid==.
					
					// Down to just ~25 missing schoolid, most of which are missing either employeeid, grade/subject, or rating
					drop if schoolid==.
					
					drop schoolid_tm1 schoolid_tp1 schoolid_tp2 schoolid_mode
				
				// There are 483 observations from 8 schools and 124 unique teachers where schoolid is negative
				// 	-111, -1001, -1002, -1003, and -10004
				// 	Seems to indicate a specialized program rather than a school
				//	Keep for now
					/*
					gen temp = (schoolid<0)
					bysort id: egen ever_neg = max(temp)
					sort id schoolyear schoolid
					bro id schoolyear schoolid schtype if ever_neg==1
					drop temp ever_neg
					
					tab schtype if schoolid<0, m
					tab gradep if schoolid<0, m sort
					tab subjectp if schoolid<0, m sort
				
					drop if schoolid<0
					*/
					
			// School type (missing in 2015 onward)
			//	Mostly early childhood (EC), elementary (ES), middle (MS), or high (HS)
			//	5 special education schools, with ~300 observations and ~125 unique teachers
			//	7 codes for "program", all but one of which have negative schoolid. ~480 observations and 140 teachers.
				
				encode schtype, gen(temp1)
				bysort schoolid: egen temp2 = mode(temp1), minmode
				replace temp1 = temp2
				drop schtype temp2
				rename temp1 schtype
				order schtype, after(schoolid)
			
			// Cluster/Ward
			//	All missing in 2009 and 2010, as well as some missing in other years
			//	120 have cluster and ward of 0 -- these are programs, with negative schoolid
				
				foreach v of varlist cluster ward {
					bysort schoolid: egen temp = mode(`v'), minmode
					replace `v' = temp if `v'==.
					drop temp
					}
			
			// School Poverty indicator has some missingness (schoolids 436 and 6000)
				
				rename pov sch_pov
				order sch_pov, after(schtype)
				replace sch_pov = "High" if schoolid==436 & sch_pov=="0"
				replace sch_pov = "High" if schoolid==433 & sch_pov=="N/A"
				replace sch_pov = "High" if sch_pov == "High Poverty"
				replace sch_pov = "High" if sch_pov=="yes"
				replace sch_pov = "Low" if sch_pov == "Low Poverty"
				replace sch_pov = "Low" if sch_pov=="no"
				replace sch_pov = "" if sch_pov=="N/A" | sch_pov=="0"
				
				rename sch_pov sch_pov_high
				replace sch_pov_high = "1" if sch_pov_high=="High"
				replace sch_pov_high = "0" if sch_pov_high=="Low"
				destring sch_pov_high, replace
				
				// Have a lot of missingness, including in 2009 and 2010 when the data was not available
					
					preserve
						keep schoolyear schoolid sch_pov_high
						duplicates drop schoolyear schoolid, force
						bysort schoolid: egen min = min(sch_pov_high)
						bysort schoolid: egen max = max(sch_pov_high)
						replace sch_pov_high = max if sch_pov_high==. & max==min
						// Just 30 without this data, most where all years are missing
						//	For just a couple, missing in 2009 and/or 2010 because switched
						//		from low to high over time. Use low here.
						replace sch_pov_high = min if sch_pov_high==.
						drop min max
						tempfile temp
						save `temp'
					restore
					drop sch_pov_high
					merge m:1 schoolyear schoolid using `temp', nogen
					
				// sch_pov_high doesn't seem to match well with farm_percent (which is classroom-level FARM)
					/*
					replace farm_percent = "." if farm_percent == "N/A"
					destring farm_percent, replace
					gen farm_pov = 1 if farm_percent >= .6 & !mi(farm_percent)
					replace farm_pov = 0 if farm_percent <.6 & !mi(farm_percent)
					replace farm_pov = . if mi(farm_pov)
					*order schoolid schoolyear sch_pov_high farm_pov farm_percent
					// Some inconsistency within some schools in a schooyear
					bys schoolid: egen temp = mode(farm_pov)
					replace farm_pov = temp
					
					tab sch_pov_high farm_pov, m
				
					drop farm_percent 
					*/
				
		// Grade
		
			replace gradep = lower(gradep)
			gen t_teach_k = regexm(gradep, "kinde|ece-k")
			replace t_teach_k = 1 if gradep=="k"
			gen t_teach_pk = regexm(gradep, "pre-k|pk|prek|preschool|ps") //preschool?
			replace t_teach_pk = 1 if gradep=="ece"
			gen t_teach_g1 = regex(gradep, "1st")
			replace t_teach_g1 = 1 if gradep=="1"
			gen t_teach_g2 = regexm(gradep, "2nd")
			replace t_teach_g2 = 1 if gradep=="2"
			gen t_teach_g3 = regexm(gradep, "3rd")
			replace t_teach_g3 = 1 if gradep=="3"
			foreach g in 4 5 6 7 8 9 10 11 12 {
				gen t_teach_g`g' = regexm(gradep, "`g'")
				}
				
			// Check for teachers teaching multiple grades (which we expect they do)
			egen t_num_grades = rowtotal(t_teach_k - t_teach_g12)
			
			// NOTE: 23% of data have no grade levels. 41% of these have "n/a" for grade variable.
			//	(Most of) the rest have "multiple" grades and we don't know which ones.
			
		// Subject
			
			replace subjectp = strrtrim(strltrim(stritrim(lower(subjectp))))
			gen subject_ela = regexm(subjectp, "all subjects|general education|elementary|english|humanities|ela|read 180|reading|writing|honor eng|honors eng|engl lit|rdg workshop|literacy|ap eng lit|vocabulary development")
			gen subject_math = regexm(subjectp, "all subjects|general education|elementary|math|algebra|geometry|statistics|calculus|trigonometry")
			gen subject_sci = regexm(subjectp, "all subjects|general education|elementary|science|biology|chemistry|engineering|geography|physics|anatomy|mechanics|computer|engrng")
			gen subject_sst = regexm(subjectp, "all subjects|general education|elementary|humanities|history|social studies|politics|government|soc studies")
			gen subject_art = regexm(subjectp, "art|music|culture|drawing|dance|choir|orchestra|piano|band|dramatics")
			gen subject_ece = regexm(subjectp, "early childhood|tools of the mind")
			gen subject_sped = regexm(subjectp, "special education|autism|self-contained")
			gen subject_ell = regexm(subjectp, "ell|esl|dual language|engl lang sc")
			gen subject_cte = regexm(subjectp, "cte|career and technical education")
			gen subject_health = regexm(subjectp, "health|physical education|human sexuality|phys ed")
			replace subject_health = 1 if subjectp=="pe"
			gen subject_foreignlang = regexm(subjectp, "world language|foreign language|spanish|chinese|french")
			
			// NOTE: Figure out what Tools of the Mind is.
			//	Also have a number of teachers with "Multiple Subjects". We could see what grade level they work in. If in early elementary
			//	we might infer that they teach all subjects.
			
			egen t_num_subjects = rowtotal(subject_*)
				// NOTE: 81% with 0 subjects have n/a, multiple subjects, other 
		
	// IMPACT scores and rating
		
		// Appeal
			
			replace appeal = "1" if appeal=="Yes"
			replace appeal = "0" if appeal=="N/A" | appeal==""
			destring appeal, replace
		
		// IMPACT score
			
			// Use original score if there is one
			rename origscore score
			replace score = adjscore if score==.
				
			// NOTE: 83 observations missing score...also missing original rating.
			//	8 observations have score below 100 and out of range. 
			
				replace score = 100 if score<100
				replace adjscore = 100 if adjscore<100
			
		// IMPACT rating (link between score and rating varies across years...in 2012-13 DCPS added Developing group)
			
			// Use original rating if there is one
			rename origrating rating
			replace rating = "" if rating=="N/A" | rating=="No Rating"
			
			// In 2011, ratings have "no consequence" with them. Use that information before cleaning more.
				replace consequence = "No Consequences" if regexm(rating, "No Consequences")
				replace rating = subinstr(rating, " - No Consequences", "", 1)
				replace adjrating = subinstr(adjrating, " - No Consequences", "", 1)
				replace adjrating = "" if adjrating=="No Rating"
			
			replace rating = adjrating if rating==""
				
			replace rating = "1" if regexm(rating, "Ineffective")
			replace rating = "2" if regexm(rating, "Minimally Effective")
			replace rating = "3" if regexm(rating, "Developing") // Only used starting in 2012
			replace rating = "5" if regexm(rating, "Highly Effective")
			replace rating = "4" if regexm(rating, "Effective")
			destring rating, replace
			label define rating 1 "Ineffective" 2 "Minimally Effective" 3 "Developing" 4 "Effective" 5 "Highly Effective"
			label values rating rating
				// NOTE: the percentage of teachers rated as highly effective increases across the years; the percentage of teachers
				//	rated as minimally effective/developing decreases
				
	// % of score based on observation
		
		// Group 1 (pull from guidebooks and Dee/Wyckoff)
		gen per_score_obs = 0.35 if group_impact=="1" & schoolyear<=2011
		replace per_score_obs = 0.4 if group_impact=="1" & schoolyear>=2012 & schoolyear<=2013
		replace per_score_obs = 0.75 if group_impact=="1" & schoolyear>=2014 & schoolyear<=2015
		replace per_score_obs = 0.30 if group_impact=="1" & schoolyear>=2016
		replace per_score_obs = 0.25 if group_impact=="1a"
		
		// Group 2 (pull from guidebooks and Dee/Wyckoff)
		replace per_score_obs = 0.75 if regexm(group_impact, "2") & schoolyear<=2015
		replace per_score_obs = 0.65 if group_impact=="2" & schoolyear>=2016
		replace per_score_obs = 0.75 if (group_impact=="2a" | group_impact=="2b") & schoolyear>=2016
		replace per_score_obs = 0.75 if (group_impact=="2a" | group_impact=="2b") & schoolyear>=2016
		replace per_score_obs = 0.45 if group_impact=="2c"
		replace per_score_obs = 0.55 if group_impact=="2d" | group_impact=="2e"
		
		// Group 3 (don't have guidebooks here in earliest years...so use same as later years)
		replace per_score_obs = 0.65 if group_impact=="3" | group_impact=="3b"
		replace per_score_obs = 0.55 if group_impact=="3a" | group_impact=="3c"
		replace per_score_obs = 0.75 if group_impact=="3d"
		replace per_score_obs = 0.45 if group_impact=="3e" | group_impact=="3f"
		
		// Groups 4 and 5 (don't have guidebooks here in earliest years...so use same as later years
		replace per_score_obs = 0.75 if group_impact=="4"
		replace per_score_obs = 0.85 if group_impact=="5"
	
	// Group
		
		*tab group_impact, m sort
		*tab group_impact schoolyear, m
			// NOTE: 46% group 2 (no value-added)
			//	15% group 3 (usually SPED)
			//	13% group 1 (with individual value-added)
		
		// Generally, teachers with IVA (but test scores not always used in some years)
		replace group_impact = "1" if group_impact=="1a" 
			// 43 LEAP teachers in 2017 and 2018
		// Generally, teachers withOUT IVA
		replace group_impact = "2" if regexm(group_impact, "2") 
			// 2a = ECE: starts in 2011 as ECE with ~500 per year
			// 2b = grade 1-2 and small group/intervention: starts in 2016 with ~500 per year
			// 2c = LEAP in same grades: ~50 per year
			// 2d = LEAP grade 1-2 and small group/intervention: starts in 2017 with ~30 per year
			// 2e = ECE LEAP: starts in 2017 with <10 per year
		// Special Education
		replace group_impact = "3" if regexm(group_impact, "3")
			// group definitions change across years to include autism, self-contained, ECE, etc.
		// ELL (distinction between itinerant and non-itinerant teachers...but not sure exactly what that means)
		replace group_impact = "4" if regexm(group_impact, "4|5")
			// 5 = itinerant: all years but ~10 per year
		
		destring group_impact, replace
		label define group 1 "Reading/Math Teachers in Tested Grades" 2 "Genderal Education Teachers in Non-Tested Grades/Subjects" 3 "Special Education" 4 "English Language Learners"
		label values group_impact group
	
	// Consequence: really what we care about here is separation and step hold 
	//	No data from 2009 (did they have consequences in that first year???)
		
		// Clean categories
		
			*tab consequence rating, m
			replace consequence = "No Consequences" if ///
				regexm(consequence, "No Consequences|No Negative|0|N/A|Not Receiving|Not receiving|Letter from the Chancellor|Notice of Minimally Effective|Reinstatement|Twice Below Effective|Once Developing|Once Minimally Effective")
				// 1 person from 2010 has letter from chancellor, with minimally effective rating
				// 8 teachers in 2010 and 2011 have "notice of minimally effective" with minimally effective rating that year
				// 3 teachers in 2010 have "reinstatement" with minimally effective rating in that year
				// 2 teachers have from 2013 and 2015 have "twice below effective" with developing rating in that year
				// 4 teachers from 2013 and 2015 have "Once Minimally Effective" with minimally effective in that year
				// 25 teachers from 2013 onward have "twice developing" with developing rating in that year
			replace consequence = "No Consequences" if consequence=="" & rating>=4 & rating!=.
				// Vast majority of missingness have effective rating
			replace consequence = "Separation" if regexm(consequence, "Delayed Separation|Separation|No Rating")
				// 1 person has "no rating" and is ineffective
			replace consequence = "Bonus" if regexm(consequence, "IMPACTplus")
				// all IMPACTplus have rating of effective
			replace consequence = "Bonus" if bonus>0 & bonus!=.
			replace consequence = "Step Hold" if regexm(consequence, "Step")
		
			// NOTE: Only 26 missing, which includes about half with Developing Rating and half with no rating
		
		// Create dummies for separation and step hold
			
			gen separation = (consequence=="Separation")
			gen stephold = (consequence=="Step Hold")
		
	// Lift (only started in 2012)
		//	09 through 11 are all missing. Was LIFT applicable those years?
		//	1 teacher missing, and a couple of "LIFT TBD"
		
		*tab schoolyear lift, m
			// No Expert in 2012 or 2013. Fewer Advanced in these years relative to later years.
			// Missing lift from 09-11
		
		replace lift = "" if lift=="LIFT TBD"
		replace lift = "1" if lift=="Teacher"
		replace lift = "2" if lift=="Established"
		replace lift = "3" if lift=="Advanced"
		replace lift = "4" if lift=="Distinguished"
		replace lift = "5" if lift=="Expert"
		destring lift, replace
		
		label define lift 1 "Teacher" 2 "Established Teacher" 3 "Advanced Teacher" 4 "Distinguished Teacher" 5 "Expert Teacher"
		label values lift lift
	
	// Bonus Offered
		
		*tab bonus rating, m
		*tab schoolyear if bonus==. & rating==5, m
		
		replace bonus = 0 if bonus==. & rating<=4
		replace bonus_offer = bonus if bonus_offer==.
		
		// There are ~1.6K teachers who got HE but are missing bonus. Are these 0s? It could be that they 
		//	got a bonus the previous year (or previous years) and so weren't eligible to get it again???
	
	// Service Credit Offered
	// 	Should be based on school poverty rate (only get if above 60%) and lift stage (2 years for advanced, and 5 years for distinguished or expert). 
		
		*tab schoolyear yrsservcred, m
		// NOTE: Missing all of 2009 and 2019
		// In 2014, no missing, and everyone without 2 or 5 is 0.
		// In 2012, 2013, 2017, and 2018, no 0s.
		// In 2015 and 2016, have some 0s as well as a lot of missings.
		
		*tab schoolyear yrsservcred, m
		*tab yrsservcred sch_pov, m
		*tab lift yrsservcred, m
			// Not aligning as above. See 2 years credit mostly for Established, and some for Advanced.
		*bysort schoolyear: tab lift yrsservcred, m
		
		replace yrsservcred = 0 if yrsservcred == . & schoolyear!=2019 & schoolyear!=2009
		replace credit_offer = yrsservcred if credit_offer==.
		
	// Opt-in to IMPACTPlus
		
		replace optin_decision = optin if optin_decision==""
		
		gen temp = "New Opt In" if year_optin==schoolyear | optin_decision=="Yes"
		
		gen flag = (temp=="New Opt In")
		sort id schoolyear
		bysort id: gen count = sum(flag)
		replace temp = "Already Opted In" if temp=="" & (year_optin<schoolyear | count==1)
		drop flag count
		replace temp = "Already Opted In" if temp=="" & optin_decision=="Autos"
		
		replace temp = "No" if temp=="" & regexm(optin_decision, "No")
		replace temp = "No" if temp=="" & adjrating=="Highly Effective"
		
		replace temp = "Not Eligible" if temp=="" & optin_decision=="N/A"
		replace temp = "Not Eligible" if temp=="" & schoolyear<=2011 & adjrating!="Highly Effective"
		
		// Still have 33% of observations with no value for optin, all of which missing for ever and year optin variables. 
		//	Assume not eligible?
		replace temp = "Not Eligible" if temp==""
	
		drop *optin*
		rename temp impactplus_optin
	
// Finally, get down to teacher-year file
	
	*unique id schoolyear 
	*unique employeeid schoolyear if employeeid!=.
	*duplicates tag employeeid schoolyear, gen(dup)
	*tab dup if employeeid!=.
	// 1 employeeid (54706) has duplicates in 2009, 10, and 11. But has different id. 
	drop if id==3452 & schoolyear<=2011

save "$data_temp/teacher_impact_scores", replace
}
}
{ // Next, clean demos from HR file and merge in IMPACT scores

/* Append files first
// Append files

	// Pull demos off of other original IMPACT files from 2009 through 2013 (these should all be teachers)
		
		foreach y in 11 12 13 {
			use "$data_temp/teacher_impact_scores_`y'", clear
			keep id employeeid schoolyear_fall gender race startdate step birthdate
			rename startdate hiredate
			gen data = 1
			tempfile `y'
			save ``y''
			}
		clear
		foreach y in 11 12 13 {
			append using ``y''
			}
		
		append using "$data_temp/teacher_demos_091011"
		replace data = 2 if data==.
		
		// Drop duplicates from 2011 (since have two different files heres)
		//	Want birthdate from impact file, and ed from demos file
			
			sort id schoolyear
			bysort id schoolyear: egen temp = mode(birthdate)
			replace birthdate = temp if birthdate==.
			drop temp
		
			bysort id schoolyear: egen temp = max(step)
			replace step = temp if step==.
			drop temp
			
			duplicates tag id schoolyear, gen(dupes)
			drop if dupes==1 & data==1
			drop dupes data
		
		// Drop a couple of odd/non-teacher observations
		
			drop if gender=="not a teacher" // 1 person from 2010; same data in other variables
			drop if gender=="not applicable" // 160 people from 2009; same data in other variables
				// NOTE: roughly 1K observations have "N/A" for a bunch of variables; keeping for now.
			
		tempfile 0913
		save `0913'
		
	// Append to the other years, which come in a different HR file (don't have 2019)

		foreach y in 14 15 16 17 18 {
			local z = `y' + 1
			import excel using "$data_raw/IMPACT/HR Teacher Demographics_edited", clear sheet("`y'-`z'") firstrow 
			gen schoolyear_fall = 2000 + `y'
			tempfile `y'
			save ``y''
			}
		clear
		foreach y in 14 15 16 17 18 {
			append using ``y''
			}
		order employeeid schoolyear
		
		rename hire_date hiredate
		drop if hiredate=="test" 
		rename t_* *
		duplicates drop
		
		// Limit to teachers by merging to IMPACT data
		tempfile temp
		save `temp'
		use "$data_temp/teacher_impact_scores", clear
		keep if schoolyear>=2014 & schoolyear<2019
		drop if employeeid==.
		keep employeeid id schoolyear // impute_id
		merge 1:m employeeid schoolyear using `temp', nogen keep(3)
			// NOTE: ~5K per year (and ~3.5K in 2018) in HR but not in IMPACT. Assume not teachers.
			//	Only 343 in IMPACT not in HR.
			//	Left with about ~4K per year, which is expected.
		
		// NOTE: There are around 6% of data that are duplicates, where it seems like IDs are off.
		//	Wait to address until combine with the other years.
			
	append using `0913'
	duplicates drop
	
	save "$data_temp/hr_demos", replace
*/

use "$data_temp/hr_demos", clear
merge m:1 id schoolyear using "$data_temp/teacher_impact_scores", nogen keep(2 3)
	// ~1K people in demos only, all from 2009 through 2013. Drop these.
	// ~4.6K have scores but not demos. BUT, ~4.1K are from 2019, when we know we don't have demos.
drop if gender=="not a teacher" | race=="not a teacher" // 1 observation
drop if gender=="not applicable" | race=="not applicable" // 138 observations, all from 2009
	
	// First clean up time-invariant variables
	
		// Gender (5% missing, exluding 2019)
				
			gen female = (gender=="F")
			replace female = . if gender=="" | gender=="Not Reported" | gender=="N/A"
			drop gender
				
		// Race (14% missing, excluding 2019)
			
			replace race = "" if regexm(race, "0|Missing|N/A|Not Reported|Not Hispanic in Puerto Rico")
			replace race = "Black" if regexm(race,"Black")
			replace race = "White" if regexm(race,"White")
			replace race = "Native American" if regexm(race,"American Indian")
			replace race = "Hispanic" if race=="Hispanic" | race=="Hispanic/Latino"
			replace race = "Asian" if regexm(race, "Asian|Chinese|Filipino|Indian|Korean|Native Hawaiian")
			gen temp = 1 if race=="Asian"
			replace temp = 2 if race=="Black"
			replace temp = 3 if race=="Hispanic"
			replace temp = 4 if race=="Native American"
			replace temp = 5 if race=="White"
			labmask temp, values(race)
			drop race
			rename temp race
			
		// Hire date
			
			replace hiredate = "" if regexm(hiredate, "Cannot|Missing|Not|N/A")
			// 1 person has hire date of 1899. Assume this is 1999, so change.	
			replace hiredate = "12/31/1999" if hiredate=="12/31/1899"
			replace hiredate = stritrim(strltrim(strrtrim(hiredate)))
			
			// Some additional cleaning based on findings below
			replace hiredate = "8/9/2015" if hiredate=="8/10/2015" & employeeid==87925 & id==7290
			
			gen hire_date = date(hiredate, "MDY")
			format hire_date %td
		
	// Address duplicates within a given year
		
		sort id schoolyear
		duplicates tag id schoolyear, gen(dupes)
			// NOTE: Most duplicates are in 2014. None in 2009 through 2013, or 2017; and 2 in 2018.
			
		// Duplicates are driven primarily by multiple steps. 
		//	So take observation with larger step IF hire year is the same.
			
			foreach v of varlist step hire_date {
				bysort id schoolyear: egen min_`v' = min(`v')
				bysort id schoolyear: egen max_`v' = max(`v')
				}
			format min_hire_date %td
			format max_hire_date %td
			
			drop if dupes>0 & step!=max_step & min_hire_date==max_hire_date
		
		drop dupes
		duplicates tag id schoolyear, gen(dupes)
		
		*unique id if dupes>0 // 143 unique ids are attached to duplicates
		
		// Keep observation that has the modal hire date within id
			
			bysort id: egen mode_hire_date = mode(hire_date)
			format mode_hire_date %td
			
			drop if dupes>0 & hire_date!=mode_hire_date
		
		drop dupes
		duplicates tag id schoolyear, gen(dupes)
		
		// Go back to redo step one above
			
			drop min_* max_*
			foreach v of varlist step hire_date {
				bysort id schoolyear: egen min_`v' = min(`v')
				bysort id schoolyear: egen max_`v' = max(`v')
				}
			format min_hire_date %td
			format max_hire_date %td
			
			drop if dupes>0 & step!=max_step & min_hire_date==max_hire_date
		
		drop dupes min_* max_* mode_*
		
	// Create consistency within time-invariant variables across years: in general take modal value
		
		foreach v of varlist female race hire_date birthdate {
			qui: bysort id: egen num_`v' = nvals(`v')
			qui: bysort id: egen mode_`v' = mode(`v')
			*tab num_`v', m
			qui: replace `v' = mode_`v' if num_`v'>1
			drop num_`v' mode_`v'
			}
		
		gen gender_missing = (female==.)
		gen male = (female==0)
		replace female = 0 if female==.
		order male gender_missing, after(female)
		*egen temp = rowtotal(female male gender_missing)
		
		gen race_missing = (race==.)
		gen asian = (race==1)
		gen black = (race==2)
		gen hispanic = (race==3)
		gen nativeam = (race==4)
		gen white = (race==5)
		order black white hispanic asian nativeam race_missing, after(race)
		*egen temp = rowtotal(black white hispanic asian nativeam race_missing)
		
	// Clean up time-varying variables: age, education, experience
		
		// Age
			
			gen age = schoolyear - year(birthdate) if month(birthdate)<9
			replace age = schoolyear - year(birthdate) - 1 if month(birthdate)>=9
			replace age = . if age<20
			/*
			gen temp = (age==.)
			bysort id: egen num_miss = total(temp)
			bysort id: gen num = _N
			sort id schoolyear
			bro id schoolyear num_miss num 
			pwcorr num num_miss if num_miss>0
			*/
			gen age_missing = (age==.)
			gen age_20to30 = (age>=20 & age<=30)
			gen age_31to45 = (age>=31 & age<=45)
			gen age_46to60 = (age>=46 & age<=60)
			gen age_61plus = (age>=61 & age!=.)
			*egen temp = rowtotal(age_missing age_20to30 age_31to45 age_46to60 age_61plus)
			
		// Education
		//	Education can be time-varying...but since so much missing, just capture if ever have MA
			
			gen degree_ma = (regexm(ed, "MA"))
			replace degree_ma = . if ed==""
			bysort id: egen temp = max(degree_ma)
			replace degree_ma = temp if degree_ma==.
			drop temp
			gen degree_noma = (degree_ma==0)
			gen degree_missing = (degree_ma==.)
			replace degree_ma = 0 if degree_ma==.
			*egen temp = rowtotal(degree_ma degree_noma degree_missing)
		
		// Experience
		//	We have a couple of different variables we can use to get experience:
		//	(i) 	teachexp (but only in first three years, and generally have categorical data)
		//	(ii) 	hire date (but could be hired in DCPS for teaching or another position)
		//	(iii) 	step (but this is for salary and does not advance one step per year)
		//	Prioritize hire data, and fill in with other variable data as needed
			
			// Start by cleaning up actual experience variables (only in 2009 through 2011)
				
				replace teachexp = "" if regexm(teachexp, "/")
				replace teachexp = "10-14 years" if teachexp=="10- 14 years"
			
			// Clean step
				
				// 106 instances where it is 0, which doesn't make sense
					
					tsset id schoolyear
					sort id schoolyear
					gen step_tm1 = L.step
					gen step_tp1 = F.step
					tsset, clear
					
					replace step = step_tm1 if step==0 & step_tm1==step_tp1
					
					replace step = 1 if step==0 & year(hire_date)==schoolyear
				
			// Impute step (vast majority missing in 2009 and 2010) 
			
				// Start with modal step by experience
				
					bysort teachexp: egen temp = mode(step) if schoolyear<=2010
					replace step = temp if step==. & teachexp!="" & schoolyear<=2010
					drop temp
				
				// Use modal step by person
				
					bysort id: egen temp = mode(step)
					replace step = temp if step==.
					drop temp
				
			// Create proxy experience measure based on hire date first, and then step
				
				gen temp = date(hiredate, "MDY")
				replace hire_date = temp if hire_date==.
				drop temp
				
				gen exp_hire = schoolyear - year(hire_date) + 1
				replace exp_hire = 1 if exp_hire<=0
				
				replace exp_hire = step if exp_hire==.
				replace exp_hire = 1 if exp_hire==. & teachexp=="1 year"
				replace exp_hire = 1 if exp_hire==. & (teachexp_dcps=="none" | teachexp_dcps=="N/A")
				
				// NOTE: ~230 missing, with ~135 from 2009
			
			// Create dummy variables: 0-3 years, 4-9 years, 10+ years
				
				gen exp_0to3 = (exp_hire<=3)
				gen exp_4to9 = (exp_hire>=4 & exp_hire<=9)
				gen exp_10plus = (exp_hire>=10 & exp_hire!=.)
				gen exp_missing = (exp_hire==.)
				*egen temp = rowtotal(exp_0to3 exp_4to9 exp_10plus exp_missing)
			
			drop step_tm1 step_tp1 hiredate teachexp teachexp_dcps
	
	// Finalize
	foreach v of varlist female - exp_missing {
		rename `v' t_`v'
		}
			
*save "$data_temp/teacher_demos", replace				
save "$data_temp/teacher_year", replace	
}
}
*-------------------------------------------------------*
*	Course Data to Link Teachers-Students (Noel/Xinyi)	*
*-------------------------------------------------------*
if $courses {
{ // Clean up files by year before appending

// 2012
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2012.csv", clear comma				
	
	// Rename variables to match across years
		rename schoolyear_start schoolyear_fall
		rename school_code schoolid
		rename studentid localid
		destring usi, force replace
		tostring staff_id, replace // staff_id is string in other years e.g. "stfX2000046320" "NULL"
		keep schoolyear usi localid schoolid subject_area_code staff_id employeeid course_title
		
	save "$data_temp/courses_2012.dta", replace

// 2013
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2013.csv", clear comma
	
		rename SCHOOLYEAR schoolyear_fall
		rename studentid localid
		rename school_code schoolid
		tostring staff_id, replace // staff_id is string in other years e.g. "stfX2000046320" "NULL"
		keep schoolyear usi localid schoolid subject_area_code staff_id employeeid course_title
		
	save "$data_temp/courses_2013.dta", replace
	
// 2014
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2014.csv", clear comma
		
		rename Pupil_number localid
		rename school_year schoolyear_fall
		rename employee_number employeeid
		rename subject_code subject_area_code
		rename teacher_id staff_id
		rename title course_title
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code staff_id employeeid course_title // usi not found
		
	save "$data_temp/courses_2014.dta", replace

// 2015
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2015.csv", clear comma
		
		rename Pupil_number localid
		rename school_year schoolyear_fall
		rename employee_number employeeid
		rename teacher_id staff_id
		rename subject_code subject_area_code
		rename title course_title
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code staff_id employeeid course_title // usi not found
		
	save "$data_temp/courses_2015.dta", replace
		
// 2016
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2016.csv", clear comma
		
		rename Pupil_number localid
		rename school_year schoolyear_fall
		rename employee_number employeeid
		rename teacher_id staff_id
		rename subject_code subject_area_code
		rename title course_title
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code staff_id employeeid course_title // usi not found
		
	save "$data_temp/courses_2016.dta", replace
		
// 2017
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2017.csv", clear comma
		
		gen schoolyear_fall = 2017
		rename pupil_number localid
		rename employee_number employeeid
		rename teacher_id staff_id
		rename subject_code subject_area_code
		rename title course_title
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code staff_id employeeid course_title // usi not found
	
	save "$data_temp/courses_2017.dta", replace
		
// 2018 (NOTE: no subject area code), and no title
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2018.csv", clear comma
		
		rename studentid localid
		rename school_year schoolyear_fall
		rename teacher_emp_num employeeid 
		*rename teacher_id staff_id // DON'T SEEM TO HAVE THIS VARIABLE
		rename course_code subject_area_code // Course code, not subject area
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code employeeid // staff_id usi not found // no course_title
		
	save "$data_temp/courses_2018.dta", replace
		
// 2019
	
	insheet using "$data_raw/Course Data/Teacher-Student-Course Match_2019.csv", clear comma
		
		rename studentid localid
		rename school_year schoolyear_fall
		rename teacher_emp_num employeeid 
		*rename teacher_id staff_id // DON'T SEEM TO HAVE THIS VARIABLE
		rename course_code subject_area_code // Not exactly subject area
		rename school schoolid
		keep schoolyear localid schoolid subject_area_code employeeid // staff_id usi not found // no course_title
	
	save "$data_temp/courses_2019.dta", replace
	
// Append by year

	use "$data_temp/courses_2012.dta", clear
	forvalues y = 13/19 {
		append using "$data_temp/courses_20`y'.dta"
		}
		
		// NOTE: Sample size in 2014, 2018, and 2019 is lower than in other years

save "$data_temp/courses.dta", replace		
}
{ // Clean to identify primary reading teacher

use "$data_temp/courses.dta", clear

	drop usi
	duplicates drop
		
// Merge in student grade level to limit only to students that we care about.
//	Full course file also includes all courses for all grade levels.
	
	rename schoolid schoolid_coursefile
	merge m:1 localid schoolyear using "$data_temp/attendance", keepusing(s_grade schoolid*) keep(2 3) // nogen
	
	bysort localid schoolyear: gen first_obs = _n
	*tab _merge if first_obs==1, m
		// 91% of student-year observations in attendance file in the course file.
		//	9% of student-years in attendance file not in courses. Who are these students?
	*tab s_grade _merge if first_obs==1, m
		// A lot of the missingness is for preK and K
	*tab schoolyear _merge, m
		// Most of non-merges from 2014, 2018, and 2019
		// NOTE: 5% of observations in demos file not in coure file.
	*tab s_grade schoolyear if _merge==2, m
		// Most of preK missing is from 2014 and some 2018; most K missing is from 2018 and 2019...which is a problem.
	
	// Is missing driven by some schools?
		
		/*
		bysort schoolid schoolyear: gen sch_num_stu = _N
		bysort schoolid s_grade schoolyear: gen sch_grade_num_stu = _N
		gen miss = (_merge==2)
		bysort schoolid s_grade schoolyear: egen sch_grade_num_stu_miss = total(miss)
		drop miss sch_num_stu sch_grade_num_stu sch_grade_num_stu_miss
		*/
	
	drop if _merge==2
	drop _merge first_obs
		
// Further restrict to grades K through 3. Even though attendance (and other data) follows kids through later grades,
//	we are interested in characteristics of teachers/teaching for K through 3. We could then link these characteristics
//	to later student outcomes.
	
	keep if s_grade>=0 & s_grade<=3	

// Clean up employeeid variable
		
	replace employeeid = "" if employeeid=="NULL"
	replace staff_id = "" if staff_id=="NULL"
	replace employeeid = staff_id if employeeid==""
	drop staff_id // Not the right variable for merging to IMPACT data
	replace employeeid = "" if employeeid=="7/20/80"
	replace employeeid = subinstr(employeeid, "z", "", 3)
	destring employeeid, replace		
	
	// NOTE: 1.5K observations out of ~115K missing employeeid
	
	/*
	gen miss_tid = (employeeid==.)
	gen have_tid = (employeeid!=.)
	bysort localid schoolyear: gen num_obs = _N
	bysort localid schoolyear: gen count = _n
	bysort localid schoolyear: egen total_miss_tid = total(miss_tid)
	bysort localid schoolyear: egen total_have_tid = total(have_tid)
	
	*tab total_miss_tid, m
		// 94% of observations not missing
	*tab total_miss_tid if count==1, m
	*tab num_obs total_miss_tid if count==1, m
	tab num_obs total_have_tid if count==1, m
	tab schoolyear s_grade if employeeid==., m
		// Mostly K in 2018 and 2019.
	*/
	
	drop if employeeid==.

// Merge in IMPACT data file to use subject from that file, and also get tecahers' schools.
		
	merge m:1 employeeid schoolyear using "$data_temp/teacher_year", ///
		keepusing(subjectp subject_* schoolid) keep(1 3) // nogen
		// About 2/3 of observation in course data not merging onto the IMPACT data. But, most of this is
		//	from 2019, since we don't have any 2019 IMPACT data yet.
		// Now we have 2019 data. About 1/5 of observation in course data not merging onto the IMPACT data. 40% of this is from 2013 & 2015.
	
	rename schoolid schoolid_impact
		// schoolid_coursefile is not always the same with schoolid1 or schoolid_impact
	
	// For now, drop 2019 data for easier cleaning and looking for missingness. Add back in once have 2019 IMPACT data.
	*********************
	*drop if schoolyear==2019
	*********************
	
	bysort localid schoolyear: gen first_obs = _n
		
		*tab _merge if first_obs==1, m
		*tab schoolyear _merge if first_obs==1, m
			// Missing all of 2019
			//	Also have about 2K students in 2015 through 2018 not attached to a teacher.	
		*tab schoolyear s_grade if _merge==1 & schoolyear!=2019 & first_obs==1, m
			// More missingness in K and grade 1. ~1.5K kindergarteners from 2018 missing.
		*tab subject_area_code if _merge==1 & schoolyear!=2019, m sort
			// 43% of missing are EE. 25% missing course, and ~22% have "OT" or "OTH". The rest have "Z" in subject area code.
		
	*tab subjectp, m sort
			// 40% all subjects, 29% missing, 5% general education
	
	drop first_obs _merge

// Narrow in on reading teachers/classes, which is the focus of this study.
//	Goal is to identify one primary reading teacher per student-year.
	
	*tab course_title, m sort
		// 33% of observations missing this, all from 2018 and 2019 when we didn't get this variable.
	*tab subject_area_code, m sort
		// 61% of observations have "EE" or "Elementary Education". 
		//	In 2018, we have different course codes, where "AB" prefix is most common and seems to describe 
		//	core elementary classes. That code also shows up in other years.
		
	// Get rid of summer and after-school classes we know are not of interest
		
		drop if regexm(course_title, "Summer|After")

	// Clean up and limit based on subject area code
		
		*tab subject_area_code, m sort
		replace subject_area_code = "EE" if subject_area_code=="Elementary Education"
		replace subject_area_code = "EE" if regexm(subject_area_code, "EE0")
		replace subject_area_code = "EE" if regexm(subject_area_code, "AB") & schoolyear==2018 // Only have AB identifiers in 2018
		replace subject_area_code = "EE" if regexm(subject_area_code, "AB") // also looks like AB references core classes in other years
		gen ee = (subject_area_code=="EE")
			// 87% of observations are now "EE"
		
	// How about homeroom? If we have a homeroom observation for a student, do we also have another observation in that
	//	same year?
		
		/*
		gen homeroom = (regexm(course_title, "Homeroom"))
		gen not_homeroom = (homeroom==0)
		bysort localid schoolyear: egen ever_homeroom = max(homeroom)
		bysort localid schoolyear: egen ever_not_homeroom = max(not_homeroom)
			
			// About half of students who have homeroom also have not homeroom in the same year.
			//	But, of course, the other half don't.
			// Are the teachers who teach homeroom also the ones who teach the other classes?
		
		gen temp = employeeid if homeroom==1
		bysort localid schoolyear: egen tid_homeroom = mode(temp)
		drop temp
		gen temp = employeeid if homeroom==0
		bysort localid schoolyear: egen tid_not_homeroom = mode(temp)
		drop temp
		
		count if ever_homeroom==1 & ever_not_homeroom==1
		count if tid_homeroom==tid_not_homeroom & ever_homeroom==1 & ever_not_homeroom==1
		*/
		
	// Drop duplicate student-teacher matches, keeping EE courses
			
		bysort localid schoolyear employeeid: gen num_matches = _N
			// 91% just one match. 2% have 4...could be four core classes.
		
		bysort localid schoolyear employeeid: egen ever_ee = max(ee)
		*tab num_matches ever_ee, m
			// 94K observations have just one student-teacher match, of which 83K are labeled as EE
			//	5.8K have two student-teacher matches, and most are EE
		drop if num_matches>1 & ever_ee==1 & ee==0
		
		drop num_matches
		bysort localid schoolyear employeeid: gen num_matches = _N
		
		*tab subject_area_code if num_matches>1, m sort
			// Plurarlity (15)% have "OT"
		*tab course_title if num_matches>1, m sort
			// 84% missing course title
		*tab schoolyear s_grade if num_matches>1, m
			// Most of the duplicates are K in 2019
		
		duplicates drop localid schoolyear employeeid, force
		
		drop num_matches ever_ee // ee

/*
// Temporarily saving file since takes a while to load and clean up till this point
********************************************
save "$data_temp/courses_temp.dta", replace	
use "$data_temp/courses_temp.dta", clear
********************************************
*/
	
	// Narrow in on primary teacher, if have more than one in a given year
		
		// Take ELA teacher based on IMPACT data, if 
		
			duplicates tag localid schoolyear, gen(dupes)
			bysort localid schoolyear: egen num_ela = total(subject_ela)
			drop if dupes>0 & num_ela>0 & subject_ela==0
			drop dupes num_ela
			
			// 18% of observations do not have subject_ela checked off (77% do).
			//	6% missing this information, because doesn't have IMPACT data.
				
			*tab s_grade subject_ela, m
				// Looks like some departmentalization by 3rd grade
			*tab subjectp if subject_ela==0, m sort
				// 26% math, 25% "tools of the mind", 12% math/science, 6% special education, 6% Montessori
			
			***********************
			*RETURN TO THIS, AS IT SEEMS ODD THAT SUBJECTS AREN'T CHECKED OFF AS ELA WHEN STUDENTS ONLY HAVE ONE
			*TEACHER THAT YEAR
			***********************
			
			drop subjectp - subject_foreignlang
			
		// Take teacher with "EE"/"Elementary Education"
			
			duplicates tag localid schoolyear, gen(dupes)
			bysort localid schoolyear: egen num_ee = total(ee)
				// 92% have 1 EE obs
			drop if dupes>0 & num_ee>0 & ee==0
			drop dupes ee num_ee
		
		// Look for speciaized special education classes
		//	508 observations have "Elementary Grade Sped Mixed" as course title, all from 2015.
		//	214 have "Elementary Special Ed Mixed", 121 from 2016 and 93 from 2017
			
			duplicates tag localid schoolyear, gen(dupes)
				// Down to 1.7% duplicates
			*tab course_title if dupes>0
			gen sped_mixed = (course_title=="Elementary Grade Sped Mixed" | course_title=="Elementary Special Ed Mixed")
			*tab schoolid_coursefile if sped_mixed==1, m
				// ~60% have unique/different school IDs of 5972 or 5995
			bysort localid schoolyear: egen num_sped_mixed = total(sped_mixed)
			drop if dupes>0 & num_sped_mixed>0 & sped_mixed==1
			
			// Now have 256 observations with this code. Got rid of most from 2015, but none from 2016 or 2017.
			
			*drop if course_title=="Elementary Grade Sped Mixed"
			
			drop dupes sped_mixed num_sped_mixed
	
		// A couple of lingering duplicates have inconsistencies in grade level of course and grade level from attendance data
				
			duplicates tag localid schoolyear, gen(dupes)
			
			gen course_grade = 0 if course_title=="Elementary Grade K"
			forvalues g = 1/3 {
				replace course_grade = `g' if course_title=="Elementary Grade `g'"
				}
			
			drop if dupes>0 & course_grade!=s_grade
			drop dupes course_grade
			
		// Look at discrepencies between school codes
		//	1,460 observations have discrepencies between course school and attendance school
		//	Of these, 492 observations have course school ID that aligns with the secondary school listed in the attendance file.
		//	921 observations don't have a secondary school.
		//	Not really clear which is the "correct" school. Probably best to stick with decision rule in attendance file:
		//		assign school with more days enrolled as the primary school.
		
			*count if schoolid_course!=schoolid1
			*count if schoolid_course!=schoolid1 & schoolid_course==schoolid2
			*count if schoolid_course!=schoolid1 & schoolid2==.
			
			duplicates tag localid schoolyear, gen(dupes)
			bysort localid schoolyear: egen min_course_sch = min(schoolid_course)
			bysort localid schoolyear: egen max_course_sch = max(schoolid_course)
			*order dupes schoolyear localid schoolyear schoolid_course schoolid_impact schoolid? min_* max_*
			
			drop if dupes>0 & schoolid_course!=schoolid1 & (schoolid_course==schoolid2 | schoolid_course==schoolid3)
			
			drop dupes min_course_sch max_course_sch
			
			*count if schoolid_course!=schoolid1
			*count if schoolid_course!=schoolid1 & schoolid_course==schoolid2
				// NOTE: 1.3K still have a discrepency with school IDs across datasets. 421 look like got the "wrong" school\
				//	from the attendance file.
				//	Can clean this up once merge everything together.
				
		// At this point, only 8 observations have duplicates. Drop at random.
			
			duplicates drop localid schoolyear, force
	
	/* May need to reshape at some point
		reshape wide employeeid , i(localid schoolyear_fall s_grade) j(num)
		rename employeeid1 emoloyeeid
	*/
	
save "$data_temp/teacher_student_links", replace
}
}
*-------------------------------------------------------*
*	School Climate Survey (Xinyi/Semi)					*
*-------------------------------------------------------*
if $school_climate {
{ // Student Satisfaction Index (all years)

// Append all years, which are different tabs of the excel file
	
	forvalues y = 13/16 {
		import excel using "$data_raw/Panorama and Stakeholder Surveys/SY1213 through SY1617 Student Satisfaction Index by School.xlsx" ///
			, clear firstrow sheet("Spring_20`y'")
		gen schoolyear_fall = 20`y' - 1
		tempfile `y'
		save ``y''
		}
	// Load 2017 separately because need to convert some variables to numeric
		import excel using "$data_raw/Panorama and Stakeholder Surveys/SY1213 through SY1617 Student Satisfaction Index by School.xlsx" ///
			, clear firstrow sheet("Spring_2017")
		foreach v in 1 2 {
			replace Answer`v'Respondents = "0" if Answer`v'Respondents=="null"
			destring Answer`v'Respondents, gen(temp)
			drop Answer`v'Respondents
			rename temp Answer`v'Respondents
			}
		gen schoolyear_fall = 2016
		tempfile 17
		save `17'
		
	forvalues y = 13/17 {
		append using ``y''
		}
	duplicates drop
	
	replace SchoolID = SchoolCode if SchoolID=="" & SchoolCode!=""
	drop SchoolCode
	destring SchoolID, replace
	
	// 2018 and 2019 also have SSI
	tempfile temp
	save `temp'
	
	use "$data_temp/student survey 2018 and 2019", clear
	keep if Survey=="Student Satisfaction Index"
	drop ReportType Survey
	drop if QuestionText=="Topic Total" | QuestionText=="Student Satisfaction Index (SSI)"
	drop PercentFavorable TotalRespondents Topics Answer5Text Answer5Respondents AnswerMode
	duplicates drop
	
	append using `temp'
	
// Clean
	
	// School name/ID
		
		rename SchoolID schoolid
		drop SchoolName
		order schoolid schoolyear
	
	// Item response
		
		rename Answer1Respondents strongdisagree 
		rename Answer2Respondents disagree
		rename Answer3Respondents agree
		rename Answer4Respondents strongagree
		drop Answer?Text
		egen total = rowtotal(strongdisagree disagree agree strongagree)
	
	// Item text (need to clean for reshaping to work)
		
		drop Question
		replace QuestionText = strrtrim(strltrim(stritrim(QuestionText)))
		replace QuestionText = subinstr(QuestionText,".","",1)
		replace QuestionText = "My school is clean and well maintained" if QuestionText=="My school is clean and well-maintained"
		replace QuestionText = "We have enough teaching materials (like books, photocopies and calculators) for all students" if QuestionText=="We have enough teaching materials (like books, photocopies, and calculators) for all"
		
		replace QuestionText = "maintaincontrol" if regexm(QuestionText, "Adults maintain con")
		replace QuestionText = "enjoyclass" if regexm(QuestionText, "I enjoy the activit")
		replace QuestionText = "feelsafe" if regexm(QuestionText, "I feel safe at my")
		replace QuestionText = "likeschool" if regexm(QuestionText, "I like my school")
		replace QuestionText = "recommendschool" if regexm(QuestionText, "I would recommend")
		replace QuestionText = "familywelcome" if regexm(QuestionText, "My family is welcome")
		replace QuestionText = "schoolcalm" if regexm(QuestionText, "My school is calm")
		replace QuestionText = "schoolclean" if regexm(QuestionText, "My school is clean")
		replace QuestionText = "afterschool" if regexm(QuestionText, "My school offers good after-school op")
		replace QuestionText = "enoughmaterials" if regexm(QuestionText, "We have enough teaching materials")
		
		*tab QuestionText schoolyear, m
			// NOTE: In 2013 and 2015 have 91 schools. In 2014 and 2016 only have 25-30 schools. In 2017 have 226 schools.
			//	Enjoy class not given in 2016 or 2017
			//	Like school only given in 2016 and 2017 (probably subsitute for above)
			//	Maintain control not given in 2013
			//	School calm only given in 2013 (probably substitute for above)
		
		replace QuestionText = "likeschool" if QuestionText=="enjoyclass"
		replace QuestionText = "maintaincontrol" if QuestionText=="schoolcalm"
		
	// Reshape so that each item is a column/variable
		
		reshape wide strongdisagree disagree agree strongagree total ///
			, i(schoolid schoolyear_fall) j(QuestionText) string
		foreach s in strongdisagree disagree agree strongagree total {
			rename `s'* *_`s'
			}
	
// Get final scores
	
	// Loop over items
	foreach item in ///
		afterschool familywelcome feelsafe likeschool ///
		maintaincontrol recommendschool schoolclean enoughmaterials ///
		{
		// Means on 4 point Likert scale
		gen `item' = ((`item'_strongagree*4) + (`item'_agree*3) + (`item'_disagree*2) + (`item'_strongdisagree*1))/`item'_total
		
		// Percentages
		foreach r in strongdisagree disagree agree strongagree {
			gen temp = `item'_`r'/`item'_total
			drop `item'_`r'
			rename temp `item'_`r'
		}
		
		// Percentage in top two categories (agree or higher)
		gen `item'_per_top2cat = `item'_strongagree + `item'_agree
		
		drop `item'_total `item'_s* `item'_d*
		}

save "$data_temp/student satisfaction index_2012 to 2018", replace
		
}
{ // SEL supports and Environments, SEL competencies (2017-18 onward)

/*
// Append all sheets and all years
	
	// Append sheets/surveys from s_2018
		foreach n in 1 2 3 {
			import excel using "$data_raw/Panorama and Stakeholder Surveys/S_2018 Student Survey Item-Level by School_edited", ///
			clear firstrow sheet("sheet_`n'")
			gen schoolyear_fall = 2017
			tempfile `n'
			save ``n''
		}
		
		foreach n in 1 2 3 {
			append using ``n''
		}
		duplicates drop
		
		save "$data_temp/student survey s_2018", replace
	
	// Append sheets/surveys from s_2019
		foreach n in 1 2 3 {
			import excel using "$data_raw/Panorama and Stakeholder Surveys/S_2019 Student Survey Item-Level by School_edited", ///
			clear firstrow sheet("sheet_`n'")
			gen schoolyear_fall = 2018
			tempfile `n'
			save ``n''
		}
		
		foreach n in 1 2 3 {
			append using ``n''
		}
		duplicates drop
	
		save "$data_temp/student survey s_2019", replace

	// Append s_2018 and s_2019
		
		foreach y in 18 19 {
			append using "$data_temp/student survey s_20`y'"
		}
save "$data_temp/student survey 2018 and 2019", replace
*/
		
// Clean

	use "$data_temp/student survey 2018 and 2019", clear
	duplicates drop
	drop if Survey=="Student Satisfaction Index" // cleaned up above
	gen grade_level = "3-5" if regexm(Survey, "Grades 3-5")
	replace grade_level = "6-12" if regexm(Survey, "Grades 6-12")
	drop SchoolName ReportType PercentFavorable AnswerMode TotalRespondents Survey Answer?Text
	
	rename SchoolID schoolid
	order schoolid schoolyear Topics QuestionText
	
	rename Answer?Respondents r? // need to reverse scores later on after reshaping
			
	// Clean QuestionText
		
		replace QuestionText = strrtrim(strltrim(stritrim(QuestionText)))
		replace QuestionText = subinstr(QuestionText,".","",1)
		
		*bro QuestionText if regexm(QuestionText, "How often did")
		replace QuestionText = "followdirections" if regexm(QuestionText, "How often did you follow directions")
		replace QuestionText = "workrightaway" if regexm(QuestionText, "How often did you get your work done right away")
		replace QuestionText = "payattention" if regexm(QuestionText, "How often did you pay attention")
		replace QuestionText = "remaincalm" if regexm(QuestionText, "How often did you remain calm")
		replace QuestionText = "allowspeak" if regexm(QuestionText, "How often did you allow others to speak")
		replace QuestionText = "complimentothers" if regexm(QuestionText, "How often did you compliment others' accomplishments")
		
		*bro QuestionText if regexm(QuestionText, "During the past 30")
		replace QuestionText = "listencarefully" if regexm(QuestionText, "How carefully did you listen to other people's points of view")
		replace QuestionText = "carefeelings" if regexm(QuestionText, "How much did you care about other people's feelings")
		replace QuestionText = "getalong" if regexm(QuestionText, "How well did you get along with students who are different from you")
		replace QuestionText = "describefeelings" if regexm(QuestionText, "How clearly were you able to describe your feelings")
		replace QuestionText = "standup" if regexm(QuestionText, "To what extent were you able to stand up for yourself")
		replace QuestionText = "noargument" if regexm(QuestionText, "To what extent were you able to disagree with others without starting an argument")
		replace QuestionText = "respectviews" if regexm(QuestionText, "how respectful were you of their views")
		
		*bro QuestionText if regexm(QuestionText, "How confident")
		replace QuestionText = "completework" if regexm(QuestionText, "How confident are you that you can complete all the work|How sure are you that you can complete all the work")
		replace QuestionText = "learnall" if regexm(QuestionText, "How confident are you that you can learn all the material presented in your classes|How sure are you that you can learn all the topics taught in your class")		
		replace QuestionText = "dohardestwork" if regexm(QuestionText, "How confident are you that you can do the hardest work|How sure are you that you can do the hardest work")
		replace QuestionText = "rememberlearned" if regexm(QuestionText, "How confident are you that you will remember what you learned|How sure are you that you will remember what you learned")
		*Note: surveys for lower & higher grades have different wordings, do we keep these items seperate?
		
		*bro QuestionText if regexm(QuestionText, "How much")
		replace QuestionText = "teacherencourage" if regexm(QuestionText, "How much do your teachers encourage you to do your best")
		replace QuestionText = "adultssupport" if regexm(QuestionText, "How much support do the adults at your school give you")
		replace QuestionText = "studentsrespect" if regexm(QuestionText, "How much respect do students at your school show you|How much respect do students in your school show you")
		replace QuestionText = "youmatter" if regexm(QuestionText, "How much do you matter to others at this school")
		
		*bro QuestionText if regexm(QuestionText, "How often") 
		replace QuestionText = "explainanswers" if regexm(QuestionText, "How often do your teachers make you explain your answers")
		replace QuestionText = "makesureunderstand" if regexm(QuestionText, "How often do your teachers take time to make sure you understand the material")
		replace QuestionText = "stayfocused" if regexm(QuestionText, "How often do you stay focused on the same goal for more than 3 months at a time|How often do you stay focused on the same goal for several months at a time")
		*Note: surveys for lower & higher grades have different wordings, do we keep these items seperate? 
		
		*bro QuestionText if regexm(QuestionText, "I am aware")
		replace QuestionText = "awareopinions" if regexm(QuestionText, "I am aware of the opinions I have about people who are different from me")
		
		*bro QuestionText if regexm(QuestionText, "cultural background")
		replace QuestionText = "cultlback" if regexm(QuestionText, "I understand my own cultural background")
		
		*bro QuestionText if regexm(QuestionText, "If you")
		replace QuestionText = "tryagain" if regexm(QuestionText, "how likely are you to try again")
		replace QuestionText = "keepworking" if regexm(QuestionText, "how well can you keep working")
	
		*bro QuestionText if regexm(QuestionText, "Overall")
		replace QuestionText = "belongschool" if regexm(QuestionText, "how much do you feel like you belong at your school")
		replace QuestionText = "teacherexpectations" if regexm(QuestionText, "how high are your teachers' expectations of you")
		
		*bro QuestionText if regexm(QuestionText, "complicated ideas")
		replace QuestionText = "understandideas" if regexm(QuestionText, "complicated ideas are discussed|complicated ideas are presented")
		*Note: surveys for lower & higher grades have different wordings, do we keep these items seperate? 
		
		*bro QuestionText if regexm(QuestionText, "When you")
		replace QuestionText = "teacherkeeptrying" if regexm(QuestionText, "how likely is it that your teachers will make you keep trying")
		*Note: surveys for lower & higher grades have different wordings, do we keep these items seperate?
		replace QuestionText = "howfocused" if regexm(QuestionText, "how focused can you stay when there are lots of distractions")
		
		*tab QuestionText
		replace QuestionText = "understandyou" if regexm(QuestionText, "How well do people at your school understand you as a person")
		replace QuestionText = "connectedadults" if regexm(QuestionText, "How connected do you feel to the adults at your school")
		replace QuestionText = "valuebackgrounds" if regexm(QuestionText, "I value people from different backgrounds")
		replace QuestionText = "continuepursue" if regexm(QuestionText, "how likely are you to continue to pursue one of your current goals")
		
		replace  QuestionText = "topic" if QuestionText=="Topic Total"

	// Clean Topics
		
		replace Topics = "cultcomp" if regexm(Topics, "Cultural")
		replace Topics = "pers" if regexm(Topics, "Perseverance")
		replace Topics = "rig" if regexm(Topics, "Rigorous")
		replace Topics = "selfeff" if regexm(Topics, "Self-Efficacy")
		replace Topics = "selfman" if regexm(Topics, "Self-Management")
		replace Topics = "belong" if regexm(Topics, "Sense")
		replace Topics = "aware" if regexm(Topics, "Awareness")
	
	// Combine Survey, Topics and QuestionText
		
		gen text = Topics + "_" + QuestionText
		
		drop QuestionText
	
// NOTE: FOR NOW, FOCUSING ON OVERARCHING TOPIC RATHER THAN EACH ITEM. MAY COME BACK TO THIS.
	
	// Calculate column total for r1~r5 of each topic
		
		foreach n in 1 2 3 4 5 {
			bys schoolid schoolyear grade_level Topics: egen t_response_`n' = total(r`n')
			}
		
		*tab text if r1==.  // all missing r1 is from topic_t variables
		
		foreach n in 1 2 3 4 5 {
			bys schoolid schoolyear grade_level Topics: replace r`n' = t_response_`n' if mi(r`n')
			}
		
		egen t = rowtotal(r?)
		
		drop Topics t_response_*
		
		keep if regexm(text, "topic")
		
		drop if text=="cultcomp_topic"
		//	NOTE: ONLY IN 2017, AND IN LATER GRADES.
	
		foreach v in aware belong pers rig selfeff selfman { // cultcomp
			replace text = "`v'" if text == "`v'_topic"
			}
		
	// Reshape so that each item is a column/variable
		
		reshape wide r1 r2 r3 r4 r5 t ///
			, i(schoolid grade_level schoolyear_fall) j(text) string
		
		foreach s in r1 r2 r3 r4 r5 t {
			rename `s'* *_`s'
			}
	
// Get final scores
	
	// Loop over topics
	foreach topic in ///
		aware belong selfman selfeff rig pers /// cultcomp ///
		{
		// Means on 5 point Likert scale
		gen `topic' = ((`topic'_r1*5) + (`topic'_r2*4) + (`topic'_r3*3) + (`topic'_r4*2) + (`topic'_r5*1))/`topic'_t
		
		// Percentages
		foreach r in r1 r2 r3 r4 r5 {
			gen temp = `topic'_`r'/`topic'_t
			drop `topic'_`r'
			rename temp `topic'_`r'
		}
		
		// Get percentage in top 2 categories
		gen `topic'_per_top2cat = `topic'_r1 + `topic'_r2
		
		drop `topic'_t `topic'_r?
		}
		
// Collapse to the school level (averaging across 3-5 and 6-12)
		
	collapse (mean) aware* belong* selfman* selfeff* rig* pers*, by(schoolid schoolyear)
	
save "$data_temp/student sel_2017 to 2018", replace
			
}
{ // Combine two surveys

use "$data_temp/student satisfaction index_2012 to 2018", clear
merge 1:1 schoolid schoolyear using "$data_temp/student sel_2017 to 2018", nogen

save "$data_temp/school_climate", replace

}
}
*-------------------------------------------------------*
*	Merge 												*
*-------------------------------------------------------*
if $merge {

// Student-level data 

	// Enrollment, attendance, demos, and suspensions (have data 2012-2019)

		use "$data_temp/attendance", clear
			// Unique by student-schoolyear 
			//	149,476 observations, and 32,923 students
			
		merge 1:1 localid schoolyear using "$data_temp/demographics", 
			// Demos files also unique by student-schoolyear
			//	143,950 observations, and 32,948 students
			// ~3K students in attendance file don't have demos; keep these.
			//	288 in demos not in attenance. Maybe drop later/
		*tab _merge	
		*unique localid if _merge==1
		drop _merge
			
		merge 1:1 localid schoolyear_fall using "$data_temp/suspensions", nogen keep(1 3)
			// All but 3 observations in the suspensions file merging. Drop these 3.
			//	Of course, lots and lots of students were never suspended at all.
		foreach v of varlist s_num_days_susp_insch s_num_days_susp_outsch s_num_days_susp {
			replace `v' = 0 if `v'==.
			}

	// Test scores (have data 2012 to MOY 2020...no spring 2020 due to COVID)

		// DIBELS (have for all years; primarily K-2, but also in some later grades)
			merge 1:1 localid schoolyear using "$data_temp/dibels", keep(1 3)
			*tab s_grade _merge, m
			*tab schoolyear _merge, m
			*tab s_grade schoolyear if _merge==3, m
			*tab s_grade schoolyear if _merge==1, m
				// 9 observations in the test score file but not elsewhere. Drop.
				// Matches are in grades K through 5, as they should be. Fair amount of missingness past grade 2,
				//	which makes sense given who the assessment is given to.
			drop _merge
		
		// TRC (have for all years; primarily K-2, but also in some later grades)
			merge 1:1 localid schoolyear using "$data_temp/trc", keep(1 3)
			*tab s_grade _merge, m
			*tab schoolyear _merge, m
			*tab s_grade schoolyear if _merge==3, m
			*tab s_grade schoolyear if _merge==1, m
			drop _merge
		
		// RI/SRI (more sporadic across years; have in 2016 onward; initially used in grades 4 and older
		//	but then in 2018 in 2nd grade and older)
			merge 1:1 localid schoolyear using "$data_temp/sri", keep(1 3)
			// NOTE: This file only has localid, not usi
			//	And only have BOY MOY for 2019-20 right now
			*tab s_grade _merge, m 
				// matching for second grade or higher, 
				//	but also lots of students in the test score file not in the other data (all from 2019, which makes sense)
			*tab schoolyear _merge, m
			*tab s_grade schoolyear if _merge==3, m
			*tab s_grade schoolyear if _merge==1, m
			drop _merge
		
		// iReady (math screening assessment; have in 2014 onward; grades K up)
			merge 1:1 localid schoolyear using "$data_temp/iready", keep(1 3)
			*tab s_grade _merge, m
			*tab schoolyear _merge, m
			*tab s_grade schoolyear if _merge==3, m
			*tab s_grade schoolyear if _merge==1, m
				// 25 observations in i-Ready not merging. Drop.
				// Merges mostly in grades K through 4 but some also in grades 4 through 7.
				// Have most students in grades 2 through 7. Less in lower grades, probably
				//	because test doesn't seem to have been administered in 2012 or 2013.
			drop _merge
			
		// PARCC (have in 2015 through 2018; no 2019 due to COVID; grades 3 and up)
			merge 1:1 localid schoolyear using "$data_temp/parcc", keep(1 3)
			*tab s_grade _merge, m
			*tab schoolyear _merge, m
			*tab s_grade schoolyear if _merge==3, m
			*tab s_grade schoolyear if _merge==1, m
				// 27 observations in PARCC file but not elsewhere. Drop
				// Matches are for grades 3-5, in 2015 through 2017, as expected.
				// 	But still have some missingness in these three grades.
				// 2 matches in grade 6 and none in grade 7, likely because the students/cohorts
				//	we are following hadn't advanced to those grades in our panel.
			drop _merge
		
		*egen num_tests = rownonmiss(s_dibels_ss_sd_f - s_sri_ss_sd_s)
			// 8 total tests.
		*tab s_grade num_tests, m
			// Pre-K grades missing all tests (mostly), as expected.
			// K and 1st grade have up to 4 tests. Would be missing PARCC and ??
		
		/*
		egen temp = rowmiss( ///
			s_dibels_ss_sd_f s_dibels_ss_sd_m s_dibels_ss_sd_s ///
			s_trc_booklevel_f s_trc_booklevel_m s_trc_booklevel_s ///
			s_ri_ss_sd_f s_ri_ss_sd_m /// s_ri_ss_sd_s // No spring yet, since only have one year of data in 2019-20
			s_parcc_ss_ela_sd s_parcc_ss_math_sd ///
			s_iready_ss_sd_f s_iready_ss_sd_s ///
			s_sri_ss_sd_f s_sri_ss_sd_s)
		tab temp if s_grade<0
			// 99.9% of pre-K students missing all of the test scores, so can drop them
		*/
		
		*drop if s_grade<0

		*unique localid
			// Have 32,955 unique students
			// 147,262 student-years
	
// School Climate Data

	merge m:1 schoolid schoolyear using "$data_temp/school_climate", keep(1 3) nogen
		// 124 school-years that aren't in the student-level data.
		//	Likely because they are middle or high schools only, whereas the other data
		//	focus on elementary schools/students.
	
// Teacher Information from IMPACT
	
	// Start by getting teacher-student links from course data
	//	Course file is missing 2019 data right now.
	//	We also limited the teacher-student links to K-3 students -- those are the ones for whom
	//	we want to capture characteristics of their teachers, and then link to student outcomes.
	
		merge 1:1 localid schoolyear using "$data_temp/teacher_student_links", keep(1 3) // nogen
			
		*tab s_grade if _merge==1
		*tab schoolyear if _merge==1
		*tab s_grade schoolyear if _merge==1
			// 12K out of 104K not merging
			// Greatest percentage of non-merges from 2019 (3K), which should be okay because we won't have teacher-level or outcome data
			//	from this year.
			// But, also have a sizeable share of non-merges from 2018 (particularly K), 2015 (across grades K to 3), and K in 2012 and 2013.
		drop _merge
	
	// Now can merge in teacher data
	
		merge m:1 employeeid schoolyear using "$data_temp/teacher_year", keep (1 3) nogen
		
save "$data_clean/student_level", replace
	
}














