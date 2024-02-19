clear
set more off, perm
*set mem 1073741824

// Change working directoy
	
	// David
	*cd "/Users/dblazar/Library/CloudStorage/Box-Box/DCPS-SERP Data Internal 2019"
	
	// Veronica
	*cd "/Users/veronicacarlan/Box Sync/DCPS-SERP Data Internal 2019/DCPS-SERP Data Internal 2019"

	// For others....
	cd "/Users/jiseungyoo/Desktop/DCPS"
	
// Set globals
	
	global data_raw 	"./Data/Raw/"
	global data_temp 	"./Data/Temporary/"
	global data_clean	"./Data/Clean/"
	global output		"./Output/"

*-------------------------------------------------------*
*	Qualitative Sample Profiles 						*
*-------------------------------------------------------*
{ // Creat school profiles to complement qualitative work

use "$data_clean/student_level", clear

	// Identify qualitative sample
		
		gen qual_samp = ///
			(schoolid==291 /// Boone (note that Orr also showing up here. Looks like name changed in 2018)
			| schoolid==238 /// Garfield 
			| schoolid==259 /// Kimball
			| schoolid==249 /// Hendley
			| schoolid==307 /// Savoy
			| schoolid==329 /// Turner
			)
		
		*tab schoolname if qual_samp, m

	// Narrow to relevant sample (qual sample schools and years)
		
		keep if schoolyear>=2018
		keep if qual_samp==1
		keep if s_grade>=0 & s_grade<=3
		
		foreach s in Garfield Hendley Kimball Boone Savoy Turner {
			replace schoolname = "`s'" if regexm(schoolname, "`s'")
			}
	
	// Clean up test scores to get performance levels as dummies (to allow for %)
		
		// DIBELS: 4 categories, with 3 being at benchmark
		foreach v of varlist s_dibels_pb* {
			gen `v'_profplus = (`v'>=3) 
			replace `v'_profplus = . if `v'==.
			}
		
		// TRC: 4 categories, with 3 being proficient
		foreach v of varlist s_trc_pb* {
			gen `v'_profplus = (`v'>=3) 
			replace `v'_profplus = . if `v'==.
			}
		
		// SRI (only available in 2019-20): 4 categories, with 3 being proficient
		foreach v of varlist s_sri_pb* {
			gen `v'_profplus = (`v'>=3) 
			replace `v'_profplus = . if `v'==.
			}
		
	// Collapse to school-year level
	
		collapse (mean) ///
			s_female s_lep s_sped /// s_frpl // FRPL isn't helpful because of direct cert
			s_native_american s_asian s_black s_latinx s_race_multi_other s_white ///
			s_days_absent_excused s_days_absent_unexcused s_num_days_susp_insch s_num_days_susp_outsch ///
			s_dibels_ss_? s_dibels_ss_sd_? s_dibels_pb_?_profplus ///
			s_trc_booklevel_? s_trc_pb_?_profplus ///
			s_sri_ss_? s_sri_ss_sd_? s_sri_pb_?_profplus ///
			, by(schoolname schoolyear)
	
	export excel "$output/qual_sample_profiles", replace firstrow(variables)


}
*-------------------------------------------------------*
*	Relationship between early and later ELA scores		*
*-------------------------------------------------------*
{ // How do early literacy scores predict later PARCC performance?

// Load data and reshape

	use "$data_clean/student_level", clear
		
		// Get PARCC scores in 3rd, 4th, and 5th grade
			
			drop temp
			foreach g in 3 4 5 {
				gen temp = s_parcc_ss_ela_sd if s_grade==`g'
				bysort localid: egen s_parcc_ss_ela_sd_g`g' = max(temp)
				drop temp
				}
		
		// Get DIBELS scores in K, 1, 2
			
			foreach g in 0 1 2 {
				gen temp = s_dibels_ss_sd_s if s_grade==`g'
				bysort localid: egen s_dibels_ss_sd_s_g`g' = max(temp)
				drop temp
	
			}	
	
// Identify qualitative sample
		
	gen qual_samp = ///
		(schoolid==291 /// Boone (note that Orr also showing up here. Looks like name changed in 2018)
		| schoolid==238 /// Garfield 
		| schoolid==259 /// Kimball
		| schoolid==249 /// Hendley
		| schoolid==307 /// Savoy
		| schoolid==329 /// Turner
		)
	
	gen full_samp = 1
	
// Run models
	
	// Loop over samples (full sample and qualitative schools sample)
		foreach s in full qual {
	// Loop over grade level for outcome
		foreach og in 3 4 5 {
	// Loop over grade level for independent variable
		foreach ig in 0 1 2 {
			
			*di "grade `ig'"
			
			areg s_parcc_ss_ela_sd_g`og' ///
				s_dibels_ss_sd_f ///
				i.schoolyear ///
				if s_grade==`ig' & `s'_samp==1 ///
				, absorb(schoolid1) robust
			/*	
			qui: areg s_parcc_ss_ela_sd_g`og' ///
				s_dibels_ss_sd_s ///
				i.schoolyear ///
				if s_grade==`ig' & `s'_samp==1 ///
				, absorb(schoolid1) robust
			
			outreg2 using "$output/early literacy versus PARCC.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			*/	
			}
			}
			}
				
}
*-------------------------------------------------------*
*	Cross-School Variation STUDENT LEVEL		 		*
*-------------------------------------------------------*
{ // How much variation in literacy scores across schools? And what explains it? 

use "$data_clean/student_level", clear
	
// Limit sample
		
	keep if s_grade<=2
	
// Identify qualitative sample
		
	gen qual_samp = ///
		(schoolid==291 /// Boone (note that Orr also showing up here. Looks like name changed in 2018)
		| schoolid==238 /// Garfield 
		| schoolid==259 /// Kimball
		| schoolid==249 /// Hendley
		| schoolid==307 /// Savoy
		| schoolid==329 /// Turner
		)
	
	gen full_samp = 1
	
// Run models
	
	foreach s in full qual {
	foreach test in dibels { // sri trc 
	foreach g in 0 1 2 {
		
		// Variation in performance level
			
			qui: xtmixed s_`test'_ss_sd_s ///
				if s_grade==`g' ///
				& `s'_samp==1 ///
				|| schoolid1: ///
				, var 
			
			// Get variance estimates
				// School
				local school = exp(_b[lns1_1_1:_cons])^2 
				// Residual
				local residual = exp(_b[lnsig_e:_cons])^2
				// Cross-school variation
				local explained = `school'/(`school'+`residual')
			
			// Output results
				outreg2 using "$output/cross school variation_student performance.xls", ///
					addstat(Explained School, `explained', School, `school', Residual, `residual') ///
					alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		
		// Growth model (i.e., conditioning on fall performance)
		
			qui: xtmixed s_`test'_ss_sd_s s_`test'_ss_sd_f ///
				if s_grade==`g' ///
				& `s'_samp==1 ///
				|| schoolid1: ///
				, var 
			
			// Get variance estimates
				// School
				local school = exp(_b[lns1_1_1:_cons])^2 
				// Residual
				local residual = exp(_b[lnsig_e:_cons])^2
				// Cross-school variation
				local explained = `school'/(`school'+`residual')
			
			// Output results
				outreg2 using "$output/cross school variation_student performance.xls", ///
					addstat(Explained School, `explained', School, `school', Residual, `residual') ///
					alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		
		// Add in student-level covariates

			qui: xtmixed s_`test'_ss_sd_s s_`test'_ss_sd_f ///
				s_female s_native_american s_asian s_black s_latinx s_white s_sped s_num_days_susp_insch s_num_days_susp_outsch ///
				if s_grade==`g' ///
				& `s'_samp==1 ///
				|| schoolid1: ///
				, var
			
			// Get variance estimates
				// School
				local school = exp(_b[lns1_1_1:_cons])^2 
				// Residual
				local residual = exp(_b[lnsig_e:_cons])^2
				// Cross-school variation
				local explained = `school'/(`school'+`residual')
			
			// Output results
				outreg2 using "$output/cross school variation_student performance.xls", ///
					addstat(Explained School, `explained', School, `school', Residual, `residual') ///
					alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		
		// Also account for teachers (but know that sample is greatly reduced!)
			
			qui: xtmixed s_`test'_ss_sd_s s_`test'_ss_sd_f ///
				s_female s_native_american s_asian s_black s_latinx s_white s_sped s_num_days_susp_insch s_num_days_susp_outsch ///
				if s_grade==`g' ///
				& `s'_samp==1 ///
				|| schoolid1: ///
				|| employeeid: ///
				, var
			
			// Get variance estimates
				// School
				local school = exp(_b[lns1_1_1:_cons])^2 
				// Teacher
				local teacher = exp(_b[lns2_1_1:_cons])^2 
				// Residual
				local residual = exp(_b[lnsig_e:_cons])^2
				// Cross-school variation
				local explained_sch = `school'/(`school'+ `teacher' + `residual')
				// Cross-teacher variation
				local explained_tch = `teacher'/(`school'+ `teacher' + `residual')
			
			// Output results
				outreg2 using "$output/cross school variation_student performance.xls", ///
					addstat(Explained School, `explained_sch', Explained Teacher, `explained_tch', School, `school', Teacher, `teacher', Residual, `residual') ///
					alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		}
		}
		}
	
}
*-------------------------------------------------------*
*	Cross-School Variation TEACHER LEVEL		 		*
*-------------------------------------------------------*
{ // How much variation in literacy scores across schools? And what explains it? 

/*
Note from DCPS conversation:
- Teacher race…do higher scores on EP translate into higher overall IMPACT scores
*/

// Get school names first
		
	use "$data_clean/student_level", clear
	keep schoolid1 schoolname1
		duplicates drop
		drop if schoolid1==.
		
		// A couple of duplicates
		duplicates tag schoolid, gen(temp)
		drop if temp>0 & regexm(schoolname1, "EC")
		drop if regexm(schoolname1, "School-Within-School")
		drop if schoolname1=="Malcolm X ES @ Green" // Also have "Malcolm X ES", and keeping that
		// 291 has two school names: Boone and Orr. Looks like name changed in 2018/
		drop if temp>0 & regexm(schoolname1, "Orr")
		drop temp
		
		rename schoolid1 schoolid
		rename schoolname1 schoolname
		
		tempfile temp
		save `temp'
	
// Load teacher observation file
	
	use "$data_temp/teacher_year", clear
	
	// Limit sample
		// Early elementary grades
		egen temp = rowtotal(t_teach_k t_teach_g1 t_teach_g2)
		gen early_elem_samp = (temp>0)
		drop temp
		*keep if early_elem_samp==1
		// Drop Early Childhood (EC) and Middle Schools (MS)
		*drop if regexm(schoolname, " EC") // drop 577
		*drop if regexm(schoolname, " MS") // drop 14
		
		// Mostly interested in Essential Practices, which come in 2016
		*keep if schoolyear>=2016
		
		// Limit to group 2 teachers
		*keep if regexm(group_impact, "Group 2")
		
	// Merge on school names
	
		merge m:1 schoolid using `temp', nogen keep(1 3)
			// SchoolIDs in teacher file not showing up in names file are (89 observations):
			//	943: dropped above...school within a school
			//	-111: not sure what this means
			//	456 and 466: but only one each of these
			// 26 schoolIDs not showing up in teacher file. Presumably not elementary school level.
		
		replace early_elem_samp = 0 if regexm(schoolname, " EC| MS")
	 
// Clean up teacher background information
	
	**Just placeholder for now until we get more HR data!!
	
	sort employeeid schoolyear
	bysort employeeid: egen temp = max(t_exp_step)
	replace t_exp_step = temp + 1 if schoolyear==2019 & temp!=.
	
	tsset employeeid schoolyear
	gen step_tm1 = L.t_exp_step
	replace t_exp_step = step_tm1 + 1 if t_exp_step==.
	tsset, clear
	
	replace t_exp_step = 17 if t_exp_step>17 & t_exp_step!=.

// Identify qualitative sample
		
	gen qual_samp = ///
		(schoolid==291 /// Boone (note that Orr also showing up here. Looks like name changed in 2018)
		| schoolid==238 /// Garfield 
		| schoolid==259 /// Kimball
		| schoolid==249 /// Hendley
		| schoolid==307 /// Savoy
		| schoolid==329 /// Turner
		)
	
	gen full_samp = 1

// Basic descriptive statistics
	
	// Means and SDs by EP
		
		preserve
			keep if early_elem_samp==1
			
			foreach v of varlist ///
				cultivate_community_avg rigorous_content_avg ///
				lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
				{
				gen `v'_sd = `v'
				}
			gen sample = 1
			
			collapse (sum) sample ///
				(mean) cultivate_community_avg rigorous_content_avg lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
				(sd) cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd maximize_ownership_avg_sd respond_evidence_avg_sd ///
				, by(schoolyear)
			
			order schoolyear sample cultivate_community_avg* rigorous_content_avg* lead_exp_avg* maximize_ownership_avg* respond_evidence_avg*
			export excel using "$output/teacher practices_means and SDs.xls" ///
				, firstrow(variables) replace
		restore
	
	// Differences by race
		
		foreach v of varlist ///
			cultivate_community_avg rigorous_content_avg ///
			lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
			{
			
		// Early Elementary Sample
			
			// Across schools
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				if schoolyear!=2019 ///
				& early_elem_samp==1 ///
				, robust absorb(schoolyear)
			
			outreg2 using "$output/EPs by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			
			
			// School fixed effects
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				i.schoolyear ///
				if schoolyear!=2019 ///
				& early_elem_samp==1 ///
				, absorb(schoolid)
			
			outreg2 using "$output/EPs by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
				
		// All Teachers
			
			// Across schools
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				if schoolyear!=2019 ///
				, absorb(schoolyear)
			
			outreg2 using "$output/EPs by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			
			// School fixed effects
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				i.schoolyear ///
				if schoolyear!=2019 ///
				, absorb(schoolid)
			
			outreg2 using "$output/EPs by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			}
	
	// Differences in IMPACT categories by race
		
		gen ineffective = (adjrating==1)
		gen mineffective = (adjrating==2)
		gen developing = (adjrating==3)
		gen effective = (adjrating==4)
		gen higheffective = (adjrating==5)
		
		foreach v of varlist ///
			ineffective mineffective developing effective higheffective ///
			{
			
		// Early Elementary Sample
			
			// Across schools
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				if schoolyear!=2019 ///
				& early_elem_samp==1 ///
				, robust absorb(schoolyear)
			
			outreg2 using "$output/IMPACT by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			
			
			// School fixed effects
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				i.schoolyear ///
				if schoolyear!=2019 ///
				& early_elem_samp==1 ///
				, absorb(schoolid)
			
			outreg2 using "$output/IMPACT by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
				
		// All Teachers
			
			// Across schools
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				if schoolyear!=2019 ///
				, absorb(schoolyear)
			
			outreg2 using "$output/IMPACT by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			
			// School fixed effects
			qui: areg `v' t_asian t_black t_hispanic t_race_missing /// t_white
				i.schoolyear ///
				if schoolyear!=2019 ///
				, absorb(schoolid)
			
			outreg2 using "$output/IMPACT by teacher race.xls", ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
			}
		
// Run models
	
	foreach s in full qual {
	foreach ep in ///
		cultivate_community_avg rigorous_content_avg ///
		lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
		{
		
	// Unconditional
		qui: xtmixed `ep' ///
			i.schoolyear ///
			if `s'_samp==1 ///
			|| schoolid: ///
			, var
		
		// Get variance estimates
			// School
			local school = exp(_b[lns1_1_1:_cons])^2 
			// Residual
			local residual = exp(_b[lnsig_e:_cons])^2
			// Cross-school variation
			local explained = `school'/(`school'+`residual')
			
		// Output results
			outreg2 using "$output/cross school variation_teacher practices.xls", ///
				addstat(Explained School, `explained', School, `school', Residual, `residual') ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
	// Conditional on teacher information
		qui: xtmixed `ep' ///
			t_exp_step ///
			i.schoolyear ///
			if `s'_samp==1 ///
			|| schoolid: ///
			, var
		
		// Get variance estimates
			// School
			local school = exp(_b[lns1_1_1:_cons])^2 
			// Residual
			local residual = exp(_b[lnsig_e:_cons])^2
			// Cross-school variation
			local explained = `school'/(`school'+`residual')
			
		// Output results
			outreg2 using "$output/cross school variation_teacher practices.xls", ///
				addstat(Explained School, `explained', School, `school', Residual, `residual') ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		}
		}
	
}
*-------------------------------------------------------*
*	Link Teacher Practices to Student Outcomes			*
*-------------------------------------------------------*
{

use "$data_clean/student_level", clear
drop temp

// Limit sample
	
	keep if s_grade>=0 & s_grade<=3
	keep if schoolyear>=2016 & schoolyear<=2018 // for 2019, only have part of the year

// Identify qualitative sample
		
	gen qual_samp = ///
		(schoolid==291 /// Boone (note that Orr also showing up here. Looks like name changed in 2018)
		| schoolid==238 /// Garfield 
		| schoolid==259 /// Kimball
		| schoolid==249 /// Hendley
		| schoolid==307 /// Savoy
		| schoolid==329 /// Turner
		)
	
	gen full_samp = 1
	
// Impute missing data
	
	// Student-level data
		
		egen temp = rowtotal(s_asian s_black s_latinx s_white)
		gen s_race_other = (temp==0)
		replace s_race_other = . if s_white==.
		drop temp
		
		foreach v of varlist ///
			s_female s_lep s_atrisk ///
			s_asian s_black s_latinx s_white s_race_other ///
			s_grade_repeat ///
			{
			bysort schoolid1 schoolyear: egen temp = mean(`v')
			replace `v' = temp if `v'==.
			drop temp
			}
	
	// Teacher information
	
		preserve
		duplicates drop employeeid schoolyear, force
		foreach v of varlist ///
			cultivate_community_avg rigorous_content_avg lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
			t_female t_asian t_black t_hispanic t_white t_exp_hire t_exp_step ///
			{
			bysort schoolid1 schoolyear: egen temp = mean(`v')
			replace `v' = temp if `v'==.
			drop temp
			}
		
		// Standardize teacher observation scores
		foreach v of varlist ///
			cultivate_community_avg rigorous_content_avg lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
			{
			bysort schoolyear: center `v', gen(`v'_sd) standardize
			}
		
		tempfile temp
		save `temp'
		restore
		
		drop cultivate_community_avg rigorous_content_avg lead_exp_avg maximize_ownership_avg respond_evidence_avg ///
			t_female t_asian t_black t_hispanic t_white t_exp_hire t_exp_step
		
		merge m:1 employeeid schoolyear using `temp', nogen	

// Run models
	
	foreach s in full { // qual
	foreach test in dibels { // sri trc 
		
		qui: areg s_`test'_ss_sd_s ///
			/// Essential Practices
			cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			maximize_ownership_avg_sd respond_evidence_avg_sd ///
			/// Other teacher characteristics
			t_female t_asian t_black t_hispanic /// t_white
			t_exp_step ///
			/// Student controls
			s_`test'_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			i.s_grade i.schoolyear ///
			if `s'_samp==1 ///
			, robust absorb(schoolid1) cluster(employeeid)
		
			outreg2 using "$output/teacher practices predict student outcomes.xls", ///
				/// addstat() ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		
		// Add Essential Practices in separate models
		foreach ep in ///
			cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			maximize_ownership_avg_sd respond_evidence_avg_sd ///
			{
			
		qui: areg s_`test'_ss_sd_s ///
			/// Essential Practices
			`ep' ///
			/// Other teacher characteristics
			t_female t_asian t_black t_hispanic /// t_white
			t_exp_step ///
			/// Student controls
			s_`test'_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			i.s_grade i.schoolyear ///
			if `s'_samp==1 ///
			, robust absorb(schoolid1) cluster(employeeid)
			
			outreg2 using "$output/teacher practices predict student outcomes.xls", ///
				/// addstat() ///
				alpha(0.001, 0.01, 0.05, 0.1) symbol(***, **, *, ~)
		}
		
		}
		}

// Additional models focused on teacher race
/*
Once clean up race and gender variables (and get from 2019), can look at interaction between race and gender
*/
	
	// Exclude EP
		
		areg s_dibels_ss_sd_s ///
			/// Essential Practices
			/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
			/// Other teacher characteristics
			t_female t_asian t_black t_hispanic /// t_white
			t_exp_step ///
			/// Student controls
			s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			i.s_grade i.schoolyear ///
			, robust absorb(schoolid1) cluster(employeeid)
	
	/*
	// Race*gender 
	//	VERY few Black male teachers in early elementary grades
	
		areg s_dibels_ss_sd_s ///
			/// Essential Practices
			/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
			/// Other teacher characteristics
			i.t_race#i.t_female ///
			/// t_female t_asian t_black t_hispanic /// t_white
			t_exp_step ///
			/// Student controls
			s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			i.s_grade i.schoolyear ///
			, robust absorb(schoolid1) cluster(employeeid)
	*/
	
	// Race-matching
		
		areg s_dibels_ss_sd_s ///
			/// Essential Practices
			/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
			/// Other teacher characteristics
			t_female t_black /// t_hispanic t_asian /// t_white
			t_exp_step ///
			/// Student controls
			s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			i.s_grade i.schoolyear ///
			if s_black==1 ///
			, robust absorb(schoolid1) cluster(employeeid)
	
	// By grade
		foreach g in 0 1 2 {
		areg s_dibels_ss_sd_s ///
			/// Essential Practices
			/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
			/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
			/// Other teacher characteristics
			t_female t_black /// t_hispanic t_asian /// t_white
			t_exp_step ///
			/// Student controls
			s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
			/// i.s_grade ///
			i.schoolyear ///
			if s_black==1 ///
			& s_grade==`g' ///
			, robust absorb(schoolid1) cluster(employeeid)
			}
	
	// Other outcomes
		
		foreach v of varlist ///
			s_days_absent s_days_absent_excused s_days_absent_unexcused ///
			s_num_days_susp s_num_days_susp_insch s_num_days_susp_outsch ///
			{
			
			areg `v' ///
				/// Essential Practices
				/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
				/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
				/// Other teacher characteristics
				t_female t_black /// t_hispanic t_asian /// t_white
				t_exp_step ///
				/// Student controls
				s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
				i.s_grade i.schoolyear ///
				/// if s_black==1 ///
				, robust absorb(schoolid1) cluster(employeeid)
				
			}
	
	// Alternative model specifications
	
		foreach v of varlist ///
			s_dibels_ss_sd_s ///
			s_days_absent s_days_absent_excused s_days_absent_unexcused ///
			s_num_days_susp s_num_days_susp_insch s_num_days_susp_outsch ///
			{
			
			areg `v' ///
				/// Essential Practices
				/// cultivate_community_avg_sd rigorous_content_avg_sd lead_exp_avg_sd ///
				/// maximize_ownership_avg_sd respond_evidence_avg_sd ///
				/// Other teacher characteristics
				t_female t_black /// t_hispanic t_asian /// t_white
				t_exp_step ///
				/// Student controls
				/// s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
				i.s_grade i.schoolyear ///
				if s_black==1 ///
				, robust absorb(localid) // cluster(employeeid)
				
			}
	
}
*-------------------------------------------------------*
*	Link SERP Qualitative Observations to DCPS Data		*
*-------------------------------------------------------*
{

// Load the qualitative observation data
	
	import excel using "DCPS_Observation Data_charts_0124.xlsx", ///
		clear sheet("Data_Transposed") firstrow
		// NOTE: 7 teachers missing IDs

	rename DCPSTeacherID employeeid
	drop if employeeid==. // 7 dropped, left with 35
	describe
	gen schoolyear_fall = 2021
	order employeeid schoolyear
	
	/*
	// Missingness
	foreach of v varlist ///
		interruptions_behavior students_lead_activity students_help_eachother whole_class_explanation whole_class_STS ///
		student_initiated_dialogue vocab_words_definied word_not_used_everyday times_students_given_choice ///
		{
		count if `v'==. // noe
		}
	*/
	
	/*
	// Simple correlations
	pwcorr interruptions_behavior students_lead_activity students_help_eachother whole_class_explanation whole_class_STS ///
		student_initiated_dialogue vocab_words_definied word_not_used_everyday times_students_given_choice
	*/
	
// Merge onto student-level data, using student-teacher links	
	tostring employeeid, replace
	merge 1:m employeeid schoolyear_fall using "student_level_js", nogen keep(3)
	
// Analyses linking qualitative observations to DC data
	
	// NOTES:
	//	observation dimensions are correlated, so can include all in the same regression model...but may also want to include in separate models
	
	areg s_dibels_ss_sd_s ///
		/// Qualitative Observation Scores
		teach_calls_students_individual_
		/// Other teacher characteristics
		t_female t_asian t_black t_hispanic /// t_white
		t_exp_step ///
		/// Student controls
		s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped ///
		i.s_grade i.schoolyear, absorb(schoolid1) cluster(employeeid)

areg s_dibels_ss_sd_s teach_calls_students_individual_ s_dibels_ss_sd_f s_female s_native_american s_asian s_black s_latinx s_white s_sped i.s_grade i.schoolyear, absorb(schoolid1) cluster(employeeid)


}
{ // Extra code from Veronica
/*
//Standardize variables we are going to use

egen zROTTminutes = std(ROTTminutes)
egen zInterBH = std(InterBH) 
egen zSOT_CR = std(SOT_CR)
egen zSleadfreq = std(Sleadfreq)
egen zHELP = std(HELP) 
egen zSOT_FH = std(SOT_FH)
egen zWCEX = std(WCEX)

//The following two fall under "Cultivate a responsive learning community"
//Supportive Community
regress a zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
//interestingly the two SOT variables are opposite signs so I removed one
regress a zROTTminutes zInterBH zSOT_CR zSleadfreq zHELP zWCEX
// in removing SOT_FH then SOT_CR all but disappears in terms of B's
regress a zROTTminutes zInterBH zSOT_FH zSleadfreq zHELP zWCEX
//put SOT_FH back in and again it does not account for much once we remove SOT_CR
regress a zROTTminutes zInterBH zSleadfreq zHELP zWCEX
//Only last two variables are statistically significant, so I removed ROTTminutes
regress a  zInterBH zSleadfreq zHELP zWCEX
//not sure there is much more to do here so I moved to  


//Student engagement
regress b zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
//here the last two and the SOT variables are stat sig but again the SOT variables have opposite relationship?
regress b zROTTminutes zInterBH zSOT_CR zSleadfreq zHELP zWCEX
// in removing SOT_FH we get a positive very small coefficient for SOT_CR but it is no longer stat sig
regress b  zSOT_CR zSOT_FH zInterBH zSleadfreq zHELP zWCEX
//slead is really stat insig
regress b  zSOT_CR zSOT_FH zInterBH zHELP zWCEX
// interBH becomes marginally more significant but not quit sig still also not hugely explanatory. Ultimately most explanatory features are SOT variables

******************


//Challenge students with rigorous content

regress BY zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
 //only WCEX and slead are significant (weirdly for rigorous content and not community). ROTTminutes and help have almost no explanatory power or significance
 regress BY zInterBH zSOT_CR zSOT_FH zSleadfreq zWCEX
 //remove SOT_CR
 regress BY zInterBH zSOT_FH zSleadfreq zWCEX
 // no effect 
 
 *********
 
 //Lead a well-planned, purposeful learning experience
 
 //Skillful Design
regress BZ zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
//only two variables that are REALLy insig are ROTTmin and slead
regress BZ  zInterBH zSOT_CR zSOT_FH zHELP zWCEX
  // remove sotCR
regress BZ  zInterBH zSOT_FH zHELP zWCEX
//SOT_FH becomes insignificant completely. I wonder what the relationship is between these variables. It looks like when togetehr they account for a fair amount of variability but alone nothing.

//Skillful Facilitation
regress CA zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
// very interstingly now the only one that is significant is slead. WCEX is ok as is InterBH (negatively associated)
regress CA  zInterBH zSleadfreq  zWCEX
// in isolating for these variables InterBH becomes less significant and explanatory, while WCEX increases in signifcance but is only minorly explanatory

****************
// Maximize student ownership of learning

//cognitive work 
regress CB zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
// the only thing with real explanatory and/or significant value is WCEX, which is interesting because this is specifically IRE questioning

// higher level understanding
regress CC zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX  
// the only thing with real explanatory and/or significant value is WCEX, which is interesting because this is specifically IRE questioning
  
*************
//Respond to evidence of student learning
//Evidence of learning
regress CD zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
// Most sig and explanatory is slead with wcex and rott also being semi significant (not surprising) - what is surprising is the ROTTmin is negatively associated
regress CD zROTTminutes zSleadfreq zWCEX
//in accounting for just these three variables, rott remains negative and wcex because a bit more significant and explanatory

//Supports and Extensions
regress CE zROTTminutes zInterBH zSOT_CR zSOT_FH zSleadfreq zHELP zWCEX
//SOT variables and WCEX omitted because of collinearity and no stanadard errors for any of the others
*/

 }
