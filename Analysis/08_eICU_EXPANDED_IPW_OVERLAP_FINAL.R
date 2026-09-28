options(stringsAsFactors = FALSE)
options(width = 180)

SCRIPT_VERSION <- "v3.2"
cat("Running eICU expanded IPW script", SCRIPT_VERSION, "\n")

required <- c("data.table","sandwich","lmtest")
missing_pkgs <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if (length(missing_pkgs)) install.packages(missing_pkgs, repos="https://cloud.r-project.org")
still <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if (length(still)) stop("Missing R packages: ", paste(still, collapse=", "))

args <- commandArgs(trailingOnly=TRUE)
DATA_DIR <- if (length(args)>=1) args[1] else getwd()
OUT_DIR  <- if (length(args)>=2) args[2] else file.path(getwd(),"results","eICU_expanded_IPW_v2")
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)

cat("DATA_DIR =", DATA_DIR, "\n")
cat("OUT_DIR  =", OUT_DIR, "\n")

f_sel <- file.path(DATA_DIR,"eicu_IPW_expanded_selection_input.csv")
f_out <- file.path(DATA_DIR,"eicu_IPW_expanded_outcome_input.csv")
if (!file.exists(f_sel)) stop("Missing: ", f_sel)
if (!file.exists(f_out)) stop("Missing: ", f_out)

sel0 <- data.table::fread(f_sel)
out0 <- data.table::fread(f_out)
sel0[, FI_valid := as.integer(!is.na(filab18))]

# -------------------- frozen QC --------------------
bench <- data.frame(
  metric=c(
    "eicu48_n",
    "eicu48_observed_deaths",
    "eicu48_mortality_missing",
    "fi_valid_n",
    "fi_valid_observed_deaths",
    "fi_valid_mortality_missing",
    "eicu50_n",
    "eicu50_deaths"
  ),
  expected=c(
    2807,
    261,
    44,
    2091,
    205,
    30,
    2015,
    197
  ),
  observed=c(
    nrow(sel0),
    sum(sel0$hospital_mortality, na.rm=TRUE),
    sum(is.na(sel0$hospital_mortality)),
    sum(sel0$FI_valid, na.rm=TRUE),
    sum(sel0$hospital_mortality[sel0$FI_valid==1], na.rm=TRUE),
    sum(is.na(sel0$hospital_mortality[sel0$FI_valid==1])),
    nrow(out0),
    sum(out0$hospital_mortality, na.rm=TRUE)
  )
)
bench$pass <- as.integer(bench$expected==bench$observed)
data.table::fwrite(bench,file.path(OUT_DIR,"00_frozen_benchmark.csv"))
if (any(is.na(bench$pass)) || !all(bench$pass==1)) {
  print(bench)
  stop("Frozen benchmark failed. Inspect 00_frozen_benchmark.csv.")
}

# -------------------- hospital overlap diagnostic --------------------
hosp <- sel0[, .(
  n=.N,
  valid_n=sum(FI_valid),
  invalid_n=sum(1-FI_valid),
  valid_rate=mean(FI_valid)
), by=hospitalid]
hosp[, overlap_status := data.table::fifelse(valid_n>0 & invalid_n>0,"mixed",
                          data.table::fifelse(valid_n==n,"all_valid","all_invalid"))]
data.table::fwrite(hosp[order(hospitalid)],
                   file.path(OUT_DIR,"01_hospital_overlap_diagnostic.csv"))

overlap_summary <- hosp[, .(
  hospitals=.N,
  patients=sum(n),
  fi_valid=sum(valid_n),
  fi_invalid=sum(invalid_n)
), by=overlap_status]
data.table::fwrite(overlap_summary,
                   file.path(OUT_DIR,"02_hospital_overlap_summary.csv"))

mixed_hosp <- hosp[overlap_status=="mixed", hospitalid]

# -------------------- helpers --------------------
mode01 <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) return(0)
  ux <- sort(unique(x))
  ux[which.max(tabulate(match(x,ux)))]
}

prep_selection <- function(d) {
  d <- data.table::copy(d)

  # continuous
  for (v in c("age_numeric","cci_chronic_burden_no_age","gcs")) {
    d[, (paste0(v,"_missing")) := as.integer(is.na(get(v)))]
    med <- median(d[[v]],na.rm=TRUE)
    d[, (paste0(v,"_imp")) := data.table::fifelse(is.na(get(v)),med,as.numeric(get(v)))]
  }
  d[, age_numeric_sel := (age_numeric_imp-65)/10]
  d[, cci_chronic_burden_no_age_sel := cci_chronic_burden_no_age_imp-1]
  d[, gcs_sel := gcs_imp-15]

  # binary
  for (v in c("sex_female","invasive_ventilation_day1","vasopressor_use_firstday")) {
    d[, (paste0(v,"_missing")) := as.integer(is.na(get(v)))]
    md <- mode01(as.numeric(d[[v]]))
    d[, (paste0(v,"_sel")) := data.table::fifelse(is.na(get(v)),md,as.numeric(get(v)))]
  }
  d
}

fit_propensity <- function(d, label) {
  d <- prep_selection(d)
  if (any(is.na(d$hospitalid))) stop(label, ": hospitalid missing.")
  d[, hospital_factor := factor(hospitalid)]

  base_terms <- c(
    "age_numeric_sel","sex_female_sel","cci_chronic_burden_no_age_sel",
    "gcs_sel","invasive_ventilation_day1_sel","vasopressor_use_firstday_sel"
  )
  all_miss <- c(
    "age_numeric_missing","sex_female_missing","cci_chronic_burden_no_age_missing",
    "gcs_missing","invasive_ventilation_day1_missing","vasopressor_use_firstday_missing"
  )
  miss_terms <- all_miss[
    vapply(all_miss,function(v) length(unique(d[[v]]))>1,logical(1))
  ]
  form <- as.formula(paste("FI_valid ~",
                           paste(c(base_terms,miss_terms,"hospital_factor"),collapse=" + ")))

  warns <- character()
  fit <- withCallingHandlers(
    glm(form,family=binomial(),data=d,
        control=glm.control(maxit=200,epsilon=1e-8)),
    warning=function(w) {
      warns <<- c(warns,conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  if (!isTRUE(fit$converged)) stop(label, ": propensity model did not converge.")

  p_raw <- as.numeric(predict(fit,type="response"))
  if (any(!is.finite(p_raw))) stop(label, ": non-finite propensity.")

  LOW <- 0.005; HIGH <- 0.995
  d[, p_raw := p_raw]
  d[, p := pmin(HIGH,pmax(LOW,p_raw))]
  d[, p_clipped := as.integer(p_raw<LOW | p_raw>HIGH)]

  numerator <- mean(d$FI_valid)
  d[, sw := ifelse(FI_valid==1,numerator/p,(1-numerator)/(1-p))]

  v <- d[FI_valid==1]
  b <- quantile(v$sw,c(.01,.99),na.rm=TRUE,names=FALSE)
  v[, sw_trim := pmin(b[2],pmax(b[1],sw))]

  list(data=d, valid=v, fit=fit, warnings=unique(warns),
       numerator=numerator, trim=b)
}

ess <- function(w) sum(w)^2/sum(w^2)

fit_outcome <- function(out, weights, weight_name, label) {
  w <- merge(out,weights,by=c("patientunitstayid","hospitalid"),
             all.x=TRUE,sort=FALSE)
  if (any(is.na(w[[weight_name]]))) stop(label, ": missing weights after merge.")

  w[, `:=`(
    death=as.integer(hospital_mortality),
    cci_c=as.numeric(cci_chronic_burden_no_age)-1,
    fi01_c=as.numeric(filab18_per_0_1)-2.777777777777778,
    age10_c=(as.numeric(age_numeric)-65)/10,
    female2=as.integer(sex_female),
    gcs_c=as.numeric(gcs)-15,
    imv=as.integer(invasive_ventilation_day1),
    vaso=as.integer(vasopressor_use_firstday)
  )]

  form <- death ~ cci_c*fi01_c + age10_c + female2 + gcs_c + imv + vaso
  fit <- suppressWarnings(glm(form,family=quasibinomial(link="logit"),
                              weights=w[[weight_name]],data=w))
  V <- sandwich::vcovCL(fit,cluster=w$hospitalid,type="HC1")
  ct <- lmtest::coeftest(fit,vcov.=V)
  co <- data.frame(
    term=rownames(ct),
    beta=ct[,1],
    cluster_robust_SE=ct[,2],
    z=ct[,3],
    p_value=ct[,4],
    OR=exp(ct[,1]),
    CI_low=exp(ct[,1]-1.96*ct[,2]),
    CI_high=exp(ct[,1]+1.96*ct[,2]),
    row.names=NULL
  )
  list(data=w,fit=fit,coef=co)
}

# ================================================================
# A. FULL-HOSPITAL model: retains original target, but reports positivity problem
# ================================================================
A <- fit_propensity(sel0,"FULL")
writeLines(c(
  paste0("converged=",A$fit$converged),
  paste0("warnings=",if(length(A$warnings)) paste(A$warnings,collapse=" | ") else "none")
),file.path(OUT_DIR,"03_FULL_propensity_status.txt"))

A_valid <- A$valid
A_weights <- A_valid[,.(patientunitstayid,hospitalid,p_raw,p,sw,sw_trim)]
A_out1 <- fit_outcome(out0,A_weights,"sw","FULL_untrimmed")
A_out2 <- fit_outcome(out0,A_weights,"sw_trim","FULL_trimmed")

full_diag <- data.frame(
  target="all_149_hospitals",
  selection_n=nrow(sel0),
  valid_n=nrow(A_valid),
  outcome_n=nrow(A_out1$data),
  outcome_deaths=sum(A_out1$data$death),
  propensity_clipped_n=sum(A$data$p_clipped),
  sw_median=median(A_valid$sw),
  sw_q1=quantile(A_valid$sw,.25),
  sw_q3=quantile(A_valid$sw,.75),
  sw_p01=quantile(A_valid$sw,.01),
  sw_p99=quantile(A_valid$sw,.99),
  sw_max=max(A_valid$sw),
  ESS_untrimmed=ess(A_out1$data$sw),
  ESS_trimmed=ess(A_out2$data$sw_trim)
)
data.table::fwrite(full_diag,file.path(OUT_DIR,"04_FULL_weight_diagnostics.csv"))
data.table::fwrite(A_out1$coef,file.path(OUT_DIR,"05_FULL_untrimmed_results.csv"))
data.table::fwrite(A_out2$coef,file.path(OUT_DIR,"06_FULL_trimmed_results.csv"))

# ================================================================
# B. OVERLAP-HOSPITAL sensitivity: only hospitals with both valid and invalid
# ================================================================
sel_overlap <- sel0[hospitalid %in% mixed_hosp]
out_overlap <- out0[hospitalid %in% mixed_hosp]

B <- fit_propensity(sel_overlap,"OVERLAP")
writeLines(c(
  paste0("converged=",B$fit$converged),
  paste0("warnings=",if(length(B$warnings)) paste(B$warnings,collapse=" | ") else "none")
),file.path(OUT_DIR,"07_OVERLAP_propensity_status.txt"))

B_valid <- B$valid
B_weights <- B_valid[,.(patientunitstayid,hospitalid,p_raw,p,sw,sw_trim)]
B_out1 <- fit_outcome(out_overlap,B_weights,"sw","OVERLAP_untrimmed")
B_out2 <- fit_outcome(out_overlap,B_weights,"sw_trim","OVERLAP_trimmed")

overlap_diag <- data.frame(
  target="92_hospitals_with_both_FI_valid_and_invalid",
  selection_n=nrow(sel_overlap),
  valid_n=nrow(B_valid),
  outcome_n=nrow(B_out1$data),
  outcome_deaths=sum(B_out1$data$death),
  propensity_clipped_n=sum(B$data$p_clipped),
  sw_median=median(B_valid$sw),
  sw_q1=quantile(B_valid$sw,.25),
  sw_q3=quantile(B_valid$sw,.75),
  sw_p01=quantile(B_valid$sw,.01),
  sw_p99=quantile(B_valid$sw,.99),
  sw_max=max(B_valid$sw),
  ESS_untrimmed=ess(B_out1$data$sw),
  ESS_trimmed=ess(B_out2$data$sw_trim)
)
data.table::fwrite(overlap_diag,file.path(OUT_DIR,"08_OVERLAP_weight_diagnostics.csv"))
data.table::fwrite(B_out1$coef,file.path(OUT_DIR,"09_OVERLAP_untrimmed_results.csv"))
data.table::fwrite(B_out2$coef,file.path(OUT_DIR,"10_OVERLAP_trimmed_results.csv"))

pick <- function(co,term) {
  z <- co[co$term==term,]
  if(nrow(z)!=1) stop("Cannot find term: ",term)
  z
}
headline_one <- function(co,target,weighting,n,deaths,ESS) {
  fi <- pick(co,"fi01_c")
  ix <- pick(co,"cci_c:fi01_c")
  data.frame(
    target=target,weighting=weighting,n=n,deaths=deaths,ESS=ESS,
    FI_OR=fi$OR,FI_CI_low=fi$CI_low,FI_CI_high=fi$CI_high,FI_p=fi$p_value,
    interaction_OR=ix$OR,interaction_CI_low=ix$CI_low,
    interaction_CI_high=ix$CI_high,interaction_p=ix$p_value
  )
}

headline <- rbind(
  headline_one(A_out1$coef,"all_hospitals","clipped_no_quantile_trim",
               nrow(A_out1$data),sum(A_out1$data$death),ess(A_out1$data$sw)),
  headline_one(A_out2$coef,"all_hospitals","clipped_plus_1_99_trim",
               nrow(A_out2$data),sum(A_out2$data$death),ess(A_out2$data$sw_trim)),
  headline_one(B_out1$coef,"overlap_hospitals_only","clipped_no_quantile_trim",
               nrow(B_out1$data),sum(B_out1$data$death),ess(B_out1$data$sw)),
  headline_one(B_out2$coef,"overlap_hospitals_only","clipped_plus_1_99_trim",
               nrow(B_out2$data),sum(B_out2$data$death),ess(B_out2$data$sw_trim))
)
data.table::fwrite(headline,file.path(OUT_DIR,"11_HEADLINE_IPW_v2.csv"))

capture.output(sessionInfo(),file=file.path(OUT_DIR,"sessionInfo.txt"))
cat("eICU expanded IPW v2 completed.\n")
