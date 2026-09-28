# ============================================================
# 05_eICU_ASSOCIATION_SENSITIVITIES_FINAL.R
# ============================================================
# Reproduces the final eICU association sensitivity analyses:
# 1) same-form hospital-cluster robust refit
# 2) diagnosis-only CCI sensitivity
# 3) minimum evaluable-item threshold 14/15/16/17/18
# 4) FI-valid vs FI-invalid descriptive comparison
# 5) IPW sensitivity for FI-Lab computability
#
# Required:
#   eicu_48_analysis_base_all.csv
#   eicu_50_primary_model_completecase.csv
# ============================================================

options(stringsAsFactors=FALSE)
options(width=160)

required <- c("data.table","sandwich","lmtest")
missing <- required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if (length(missing)) install.packages(missing,repos="https://cloud.r-project.org")
still <- required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if (length(still)) stop("Missing R packages: ",paste(still,collapse=", "))

args <- commandArgs(trailingOnly=TRUE)
DATA_DIR <- if (length(args)>=1) args[1] else getwd()
OUT_DIR <- if (length(args)>=2) args[2] else file.path(getwd(),"results","05_eICU_SENSITIVITIES")
dir.create(OUT_DIR,recursive=TRUE,showWarnings=FALSE)

f48 <- file.path(DATA_DIR,"eicu_48_analysis_base_all.csv")
f50 <- file.path(DATA_DIR,"eicu_50_primary_model_completecase.csv")
if (!file.exists(f48)) stop("Cannot find ",f48)
if (!file.exists(f50)) stop("Cannot find ",f50)

e48 <- data.table::fread(f48)
e50 <- data.table::fread(f50)

CCI_CENTER <- 1
FI01_CENTER <- 2.777777777777778
AGE_CENTER <- 65
GCS_CENTER <- 15

center <- function(d,cci_col="cci_chronic_burden_no_age",fi_col="filab18_per_0_1") {
  d <- data.table::copy(d)
  d[, `:=`(
    death=as.integer(hospital_mortality),
    cci_c=as.numeric(get(cci_col))-CCI_CENTER,
    fi01_c=as.numeric(get(fi_col))-FI01_CENTER,
    age10_c=(as.numeric(age_numeric)-AGE_CENTER)/10,
    female2=as.integer(sex_female),
    gcs_c=as.numeric(gcs)-GCS_CENTER,
    imv=as.integer(invasive_ventilation_day1),
    vaso=as.integer(vasopressor_use_firstday)
  )]
  d
}

extract_cluster <- function(fit,cluster) {
  V <- sandwich::vcovCL(fit,cluster=cluster,type="HC1")
  ct <- lmtest::coeftest(fit,vcov.=V)
  data.frame(
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
}

form <- death ~ cci_c*fi01_c + age10_c + female2 + gcs_c + imv + vaso

# 1. Same-form primary eICU refit
d <- center(e50)
fit <- glm(form,family=binomial(),data=d)
cluster_main <- extract_cluster(fit,d$hospitalid)
data.table::fwrite(cluster_main,file.path(OUT_DIR,"01_eICU_sameform_cluster_robust.csv"))

# 2. Diagnosis-only CCI sensitivity
ddx <- center(e50,cci_col="cci_chronic_burden_no_age_dx_only")
keep <- complete.cases(ddx[,.(death,cci_c,fi01_c,age10_c,female2,gcs_c,imv,vaso,hospitalid)])
ddx <- ddx[keep]
fit_dx <- glm(form,family=binomial(),data=ddx)
cluster_dx <- extract_cluster(fit_dx,ddx$hospitalid)
data.table::fwrite(cluster_dx,file.path(OUT_DIR,"02_eICU_diagnosis_only_CCI.csv"))

# 3. Threshold sensitivity
threshold_rows <- list()
for (k in 14:18) {
  z <- e48[filab18_n_evaluable>=k]
  z[, filab18_threshold_per_0_1 :=
      (as.numeric(filab18_n_deficits)/as.numeric(filab18_n_evaluable))*10.0]
  z <- center(z,fi_col="filab18_threshold_per_0_1")
  keep <- complete.cases(z[,.(death,cci_c,fi01_c,age10_c,female2,gcs_c,imv,vaso,hospitalid)])
  zz <- z[keep]
  ff <- glm(form,family=binomial(),data=zz)
  co <- extract_cluster(ff,zz$hospitalid)

  fi <- co[co$term=="fi01_c",]
  ix <- co[co$term=="cci_c:fi01_c",]

  threshold_rows[[as.character(k)]] <- data.frame(
    minimum_items=k,
    FI_valid_n=nrow(e48[filab18_n_evaluable>=k]),
    complete_case_n=nrow(zz),
    deaths=sum(zz$death),
    FI_OR=fi$OR,
    FI_CI_low=fi$CI_low,
    FI_CI_high=fi$CI_high,
    FI_p=fi$p_value,
    interaction_OR=ix$OR,
    interaction_CI_low=ix$CI_low,
    interaction_CI_high=ix$CI_high,
    interaction_p=ix$p_value
  )
}
threshold_out <- data.table::rbindlist(threshold_rows)
data.table::fwrite(threshold_out,file.path(OUT_DIR,"03_eICU_threshold_14_to_18.csv"))

# 4. FI-valid vs invalid descriptive comparison
e48[, FI_valid := as.integer(filab18_n_evaluable>=15)]
validity <- e48[, .(
  n=.N,
  deaths=sum(hospital_mortality,na.rm=TRUE),
  mortality=mean(hospital_mortality,na.rm=TRUE),
  age_mean=mean(age_numeric,na.rm=TRUE),
  age_sd=sd(age_numeric,na.rm=TRUE),
  female_n=sum(sex_female==1,na.rm=TRUE),
  female_pct=100*mean(sex_female==1,na.rm=TRUE),
  gcs_median=median(gcs,na.rm=TRUE),
  imv_n=sum(invasive_ventilation_day1==1,na.rm=TRUE),
  imv_pct=100*mean(invasive_ventilation_day1==1,na.rm=TRUE),
  vaso_n=sum(vasopressor_use_firstday==1,na.rm=TRUE),
  vaso_pct=100*mean(vasopressor_use_firstday==1,na.rm=TRUE),
  cci_mean=mean(cci_chronic_burden_no_age,na.rm=TRUE),
  cci_sd=sd(cci_chronic_burden_no_age,na.rm=TRUE)
), by=FI_valid]
data.table::fwrite(validity,file.path(OUT_DIR,"04_eICU_FI_valid_vs_invalid.csv"))

coverage_cols <- c(
  wbc="wbc",hemoglobin="hemoglobin",hematocrit="hematocrit",platelet="platelet",
  rbc="rbc",mcv="mcv",sodium="sodium",potassium="potassium",chloride="chloride",
  bicarbonate="bicarbonate",bun="bun",creatinine="creatinine",glucose="glucose",
  calcium="calcium",magnesium="magnesium",phosphate="phosphate",inr="inr",aptt="aptt"
)
coverage <- data.frame(
  item=names(coverage_cols),
  coverage=vapply(coverage_cols,function(cc) mean(!is.na(e48[[cc]])),numeric(1))
)
coverage$missing <- 1-coverage$coverage
data.table::fwrite(coverage,file.path(OUT_DIR,"05_eICU_item_coverage.csv"))

# 5. IPW sensitivity
e48[, FI_valid := as.integer(!is.na(filab18))]
sel <- e48[
  !is.na(FI_valid) &
  !is.na(age_numeric) &
  !is.na(sex_female) &
  !is.na(cci_chronic_burden_no_age) &
  !is.na(hospitalid)
]

prop_fit <- suppressWarnings(glm(
  FI_valid ~ age_numeric + sex_female + cci_chronic_burden_no_age + factor(hospitalid),
  family=binomial(), data=sel, control=glm.control(maxit=100)
))
if (!isTRUE(prop_fit$converged)) {
  prop_fit <- glm(
    FI_valid ~ age_numeric + sex_female + cci_chronic_burden_no_age,
    family=binomial(), data=sel
  )
}
sel[, p_valid := pmin(.995,pmax(.005,predict(prop_fit,type="response")))]
p_num <- mean(sel$FI_valid)
sel[, sw := ifelse(FI_valid==1,p_num/p_valid,(1-p_num)/(1-p_valid))]

weights <- sel[,.(patientunitstayid,hospitalid,p_valid,sw)]
wv <- merge(e50,weights,by=c("patientunitstayid","hospitalid"),all.x=TRUE)
wv <- wv[!is.na(sw)]
wv <- center(wv)

q <- quantile(wv$sw,c(.01,.99),na.rm=TRUE)
wv[, sw_trim := pmin(q[2],pmax(q[1],sw))]

fit_ipw <- glm(
  form,family=binomial(),weights=sw_trim,data=wv
)
ipw_out <- extract_cluster(fit_ipw,wv$hospitalid)
data.table::fwrite(ipw_out,file.path(OUT_DIR,"06_eICU_IPW_cluster_robust.csv"))

weight_out <- data.frame(
  FI_validity_rate=p_num,
  selection_model_n=nrow(sel),
  outcome_model_n=nrow(wv),
  deaths=sum(wv$death),
  weight_trim="1st-99th percentile",
  weight_mean=mean(wv$sw_trim),
  weight_median=median(wv$sw_trim),
  weight_p01=quantile(wv$sw_trim,.01),
  weight_p99=quantile(wv$sw_trim,.99),
  weight_max=max(wv$sw_trim)
)
data.table::fwrite(weight_out,file.path(OUT_DIR,"07_eICU_IPW_weight_summary.csv"))

# Hard benchmark checks for headline rows
bench <- data.frame(
  metric=c(
    "primary_n","primary_deaths",
    "threshold14_completecase_n","threshold15_completecase_n",
    "threshold16_completecase_n","threshold17_completecase_n","threshold18_completecase_n"
  ),
  expected=c(2015,197,2379,2015,1654,809,376),
  observed=c(
    nrow(d),sum(d$death),
    threshold_out$complete_case_n[threshold_out$minimum_items==14],
    threshold_out$complete_case_n[threshold_out$minimum_items==15],
    threshold_out$complete_case_n[threshold_out$minimum_items==16],
    threshold_out$complete_case_n[threshold_out$minimum_items==17],
    threshold_out$complete_case_n[threshold_out$minimum_items==18]
  )
)
bench$pass <- as.integer(bench$expected==bench$observed)
data.table::fwrite(bench,file.path(OUT_DIR,"08_eICU_sensitivity_benchmark.csv"))

capture.output(sessionInfo(),file=file.path(OUT_DIR,"sessionInfo.txt"))
cat("eICU association sensitivities complete.\n")
