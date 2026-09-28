# ============================================================
# RUN_03_BROADER_AIS_SENSITIVITY_v1_2_FIXED.R
# ============================================================
# Purpose:
#   Evaluate robustness of MIMIC primary association results to
#   progressively broader AIS case definitions.
#
# Required:
#   1) mimic_SENS03_primary_model_completecase_all_defs.csv
#   2) H94_primary_model_completecase.csv
#
# v1.2 FIX: grouped descriptive summaries now force stable numeric/integer types;
# this prevents data.table failures when median CCI is integer in one group and double in another.
# v1.1 FIX: exact duplicate case definitions are detected automatically;
# their fitted/simulation results are reused to avoid Monte Carlo-only CI differences.
#
# The frozen H94 file is REQUIRED so the P0 SQL reconstruction can
# be audited row-by-row before S1-S3 are interpreted.
# ============================================================

options(stringsAsFactors = FALSE)
options(width = 160)

required_pkgs <- c("data.table")
missing_pkgs <- required_pkgs[
  !vapply(required_pkgs, requireNamespace, logical(1), quietly=TRUE)
]
if (length(missing_pkgs)) {
  install.packages(missing_pkgs, repos="https://cloud.r-project.org")
}
if (!requireNamespace("data.table", quietly=TRUE)) {
  stop("Package data.table is required.")
}

# ------------------------------------------------------------
# Locate script and data
# ------------------------------------------------------------

script_dir <- normalizePath(getwd(), winslash="/", mustWork=TRUE)
if (requireNamespace("rstudioapi", quietly=TRUE) && rstudioapi::isAvailable()) {
  ctx <- try(rstudioapi::getActiveDocumentContext(), silent=TRUE)
  if (!inherits(ctx, "try-error") && nzchar(ctx$path)) {
    script_dir <- dirname(
      normalizePath(ctx$path, winslash="/", mustWork=TRUE)
    )
  }
}

needed <- c(
  "mimic_SENS03_primary_model_completecase_all_defs.csv",
  "H94_primary_model_completecase.csv"
)

find_file_case <- function(d, candidates) {
  ff <- list.files(d, full.names=TRUE)
  bn <- basename(ff)
  for (cand in candidates) {
    hit <- which(tolower(bn) == tolower(cand))
    if (length(hit)) return(ff[hit[1]])
  }
  NA_character_
}

choose_data_dir <- function() {
  candidates <- unique(c(
    script_dir,
    file.path(script_dir, "data"),
    dirname(script_dir)
  ))

  for (d in candidates) {
    if (!dir.exists(d)) next
    a <- find_file_case(d, "mimic_SENS03_primary_model_completecase_all_defs.csv")
    b <- find_file_case(
      d,
      c("H94_primary_model_completecase.csv",
        "mimic_H94_primary_model_completecase.csv")
    )
    if (!is.na(a) && !is.na(b)) {
      return(normalizePath(d, winslash="/", mustWork=TRUE))
    }
  }

  cat("\n请选择同时包含以下两个 CSV 的文件夹：\n")
  cat(" - mimic_SENS03_primary_model_completecase_all_defs.csv\n")
  cat(" - H94_primary_model_completecase.csv\n\n")

  if (.Platform$OS.type == "windows") {
    d <- utils::choose.dir(
      default=script_dir,
      caption="选择 broader AIS sensitivity 数据文件夹"
    )
  } else {
    d <- readline("Data directory: ")
  }

  if (is.na(d) || !nzchar(d)) stop("No data directory selected.")
  normalizePath(d, winslash="/", mustWork=TRUE)
}

DATA_DIR <- choose_data_dir()

sens_file <- find_file_case(
  DATA_DIR,
  "mimic_SENS03_primary_model_completecase_all_defs.csv"
)
h94_file <- find_file_case(
  DATA_DIR,
  c("H94_primary_model_completecase.csv",
    "mimic_H94_primary_model_completecase.csv")
)

if (is.na(sens_file)) stop("Cannot find SENS03 complete-case CSV.")
if (is.na(h94_file)) stop("Cannot find frozen H94 complete-case CSV.")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
OUT_DIR <- file.path(
  script_dir, "results",
  paste0("BROADER_AIS_SENS_", stamp)
)
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)

cat("\nSENS03 input:\n", sens_file, "\n")
cat("\nFrozen H94 input:\n", h94_file, "\n")
cat("\nOutput:\n", OUT_DIR, "\n\n")

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

check_cols <- function(d, cols, label) {
  miss <- setdiff(cols, names(d))
  if (length(miss)) {
    stop(label, " missing columns: ", paste(miss, collapse=", "))
  }
}

safe_logit <- function(p) {
  p <- pmin(pmax(p, 1e-12), 1-1e-12)
  log(p/(1-p))
}

lrt_test <- function(reduced, full) {
  ll0 <- as.numeric(logLik(reduced))
  ll1 <- as.numeric(logLik(full))
  df0 <- attr(logLik(reduced), "df")
  df1 <- attr(logLik(full), "df")
  chisq <- 2*(ll1-ll0)
  df <- df1-df0
  p <- pchisq(chisq, df=df, lower.tail=FALSE)
  c(chisq=chisq, df=df, p=p)
}

coef_extract <- function(fit, term) {
  sm <- summary(fit)$coefficients
  if (!(term %in% rownames(sm))) {
    return(c(beta=NA, SE=NA, OR=NA, CI_low=NA, CI_high=NA, p=NA))
  }
  b <- sm[term,1]
  se <- sm[term,2]
  c(
    beta=b,
    SE=se,
    OR=exp(b),
    CI_low=exp(b-1.96*se),
    CI_high=exp(b+1.96*se),
    p=sm[term,4]
  )
}

rmvnorm_eigen <- function(n, mu, Sigma) {
  S <- (Sigma + t(Sigma))/2
  ee <- eigen(S, symmetric=TRUE)
  vals <- pmax(ee$values, 0)
  A <- ee$vectors %*% diag(sqrt(vals), nrow=length(vals))
  Z <- matrix(rnorm(n*length(mu)), nrow=n)
  sweep(Z %*% t(A), 2, mu, "+")
}

# Standardized additive interaction for increments:
#   +1 CCI and +0.1 FI-Lab
# averaged over each cohort's empirical covariate/exposure distribution.
additive_interaction <- function(fit, d, B=5000L, seed=20260926L) {
  make_nd <- function(cci_add=0, fi_add=0) {
    nd <- as.data.frame(d)
    nd$cci_c <- nd$cci_c + cci_add
    nd$fi01_c <- nd$fi01_c + fi_add
    nd
  }

  nd00 <- make_nd(0,0)
  nd10 <- make_nd(1,0)
  nd01 <- make_nd(0,1)
  nd11 <- make_nd(1,1)

  tt <- delete.response(terms(fit))
  X00 <- model.matrix(tt, nd00)
  X10 <- model.matrix(tt, nd10)
  X01 <- model.matrix(tt, nd01)
  X11 <- model.matrix(tt, nd11)

  b <- coef(fit)
  V <- vcov(fit)

  calc_one <- function(beta) {
    p00 <- plogis(drop(X00 %*% beta))
    p10 <- plogis(drop(X10 %*% beta))
    p01 <- plogis(drop(X01 %*% beta))
    p11 <- plogis(drop(X11 %*% beta))
    mean(p11 - p10 - p01 + p00)
  }

  est <- calc_one(b)

  set.seed(seed)
  beta_draws <- rmvnorm_eigen(B, b, V)

  sims <- numeric(B)
  chunk <- 100L
  starts <- seq(1L, B, by=chunk)

  pb <- txtProgressBar(min=0, max=length(starts), style=3)

  for (j in seq_along(starts)) {
    i1 <- starts[j]
    i2 <- min(B, i1+chunk-1L)
    BB <- t(beta_draws[i1:i2,,drop=FALSE])

    p00 <- plogis(X00 %*% BB)
    p10 <- plogis(X10 %*% BB)
    p01 <- plogis(X01 %*% BB)
    p11 <- plogis(X11 %*% BB)

    sims[i1:i2] <- colMeans(p11-p10-p01+p00)
    setTxtProgressBar(pb, j)
  }
  close(pb)

  ci <- quantile(sims, c(.025,.975), na.rm=TRUE)

  c(
    estimate=est,
    CI_low=unname(ci[1]),
    CI_high=unname(ci[2])
  )
}

# ------------------------------------------------------------
# Load
# ------------------------------------------------------------

sens <- data.table::fread(sens_file)
h94 <- data.table::fread(h94_file)

req_sens <- c(
  "cohort_def","cohort_order",
  "subject_id","hadm_id","stay_id",
  "hospital_expire_flag",
  "cci_chronic_burden_no_age",
  "filab18_score","filab18_per_0_1",
  "age","female","gcs_min",
  "any_invasive_vent_m6p24",
  "any_vasopressor_m6p24",
  "n_measured","n_deficits"
)

req_h94 <- c(
  "subject_id","hadm_id","stay_id",
  "hospital_expire_flag",
  "cci_chronic_burden_no_age",
  "filab18_per_0_1",
  "age","female","gcs_min",
  "any_invasive_vent_m6p24",
  "any_vasopressor_m6p24"
)

check_cols(sens, req_sens, "SENS03")
check_cols(h94, req_h94, "H94")

# ------------------------------------------------------------
# P0 row-level audit against frozen H94
# ------------------------------------------------------------

p0 <- sens[cohort_def=="P0_PRIMARY_FROZEN"]

ids_p0 <- unique(p0[, .(subject_id,hadm_id,stay_id)])
ids_h94 <- unique(h94[, .(subject_id,hadm_id,stay_id)])

p0_only <- data.table::fsetdiff(ids_p0, ids_h94)
h94_only <- data.table::fsetdiff(ids_h94, ids_p0)

audit_join <- merge(
  p0,
  h94,
  by=c("subject_id","hadm_id","stay_id"),
  suffixes=c("_new","_frozen"),
  all=FALSE
)

max_abs_diff <- function(a,b) {
  z <- abs(as.numeric(a)-as.numeric(b))
  if (!length(z) || all(is.na(z))) return(NA_real_)
  max(z, na.rm=TRUE)
}


cohort_signature <- function(d) {
  keep <- setdiff(
    names(d),
    c("cohort_def","cohort_order")
  )
  dd <- data.table::copy(d[, ..keep])
  data.table::setorderv(dd, intersect(c("subject_id","hadm_id","stay_id"), names(dd)))
  # Stable text signature without extra packages.
  paste(
    apply(dd, 1, function(x) paste(ifelse(is.na(x), "<NA>", x), collapse="|")),
    collapse="\n"
  )
}

audit <- data.frame(
  metric=c(
    "P0 n",
    "H94 n",
    "P0 deaths",
    "H94 deaths",
    "IDs only in P0",
    "IDs only in H94",
    "max abs diff FI per 0.1",
    "max abs diff modified CCI",
    "max abs diff age",
    "max abs diff female",
    "max abs diff GCS",
    "max abs diff invasive ventilation",
    "max abs diff vasopressor",
    "max abs diff hospital death"
  ),
  value=c(
    nrow(p0),
    nrow(h94),
    sum(p0$hospital_expire_flag),
    sum(h94$hospital_expire_flag),
    nrow(p0_only),
    nrow(h94_only),
    max_abs_diff(
      audit_join$filab18_per_0_1_new,
      audit_join$filab18_per_0_1_frozen
    ),
    max_abs_diff(
      audit_join$cci_chronic_burden_no_age_new,
      audit_join$cci_chronic_burden_no_age_frozen
    ),
    max_abs_diff(
      audit_join$age_new,
      audit_join$age_frozen
    ),
    max_abs_diff(
      audit_join$female_new,
      audit_join$female_frozen
    ),
    max_abs_diff(
      audit_join$gcs_min_new,
      audit_join$gcs_min_frozen
    ),
    max_abs_diff(
      audit_join$any_invasive_vent_m6p24_new,
      audit_join$any_invasive_vent_m6p24_frozen
    ),
    max_abs_diff(
      audit_join$any_vasopressor_m6p24_new,
      audit_join$any_vasopressor_m6p24_frozen
    ),
    max_abs_diff(
      audit_join$hospital_expire_flag_new,
      audit_join$hospital_expire_flag_frozen
    )
  )
)

data.table::fwrite(
  audit,
  file.path(OUT_DIR, "00_P0_vs_frozen_H94_rowlevel_audit.csv")
)

if (nrow(p0) != 1665 ||
    sum(p0$hospital_expire_flag) != 183 ||
    nrow(p0_only) != 0 ||
    nrow(h94_only) != 0) {

  stop(
    "P0 does NOT reproduce frozen H94 IDs/counts. ",
    "STOP: do not interpret S1-S3. ",
    "Upload 00_P0_vs_frozen_H94_rowlevel_audit.csv."
  )
}

# Require key analysis variables to align.
key_diff_rows <- audit[
  audit$metric %in% c(
    "max abs diff modified CCI",
    "max abs diff age",
    "max abs diff female",
    "max abs diff GCS",
    "max abs diff invasive ventilation",
    "max abs diff vasopressor",
    "max abs diff hospital death"
  ), ]

if (any(key_diff_rows$value > 1e-10, na.rm=TRUE)) {
  stop(
    "P0 IDs match H94 but one or more key reconstructed variables differ. ",
    "STOP before interpreting S1-S3."
  )
}

# FI floating differences can be tiny.
fi_diff <- audit$value[audit$metric=="max abs diff FI per 0.1"]
if (length(fi_diff) && is.finite(fi_diff) && fi_diff > 1e-10) {
  stop(
    "P0 FI-Lab differs materially from frozen H94. ",
    "STOP before interpreting S1-S3."
  )
}

# ------------------------------------------------------------
# Harmonized centered model variables
# ------------------------------------------------------------

CCI_CENTER <- 1
FI01_CENTER <- 2.777777777777778
AGE_CENTER <- 65
GCS_CENTER <- 15

sens[, `:=`(
  death = hospital_expire_flag,
  cci_c = cci_chronic_burden_no_age - CCI_CENTER,
  fi01_c = filab18_per_0_1 - FI01_CENTER,
  age10_c = (age - AGE_CENTER)/10,
  female2 = female,
  gcs_c = gcs_min - GCS_CENTER,
  imv = any_invasive_vent_m6p24,
  vaso = any_vasopressor_m6p24
)]

defs <- unique(
  sens[order(cohort_order), .(cohort_order,cohort_def)]
)

# ------------------------------------------------------------
# Detect case definitions that are completely identical
# ------------------------------------------------------------

signatures <- lapply(defs$cohort_def, function(def) {
  cohort_signature(sens[cohort_def == def])
})
names(signatures) <- defs$cohort_def

duplicate_of <- setNames(rep(NA_character_, nrow(defs)), defs$cohort_def)

for (i in seq_len(nrow(defs))) {
  if (i == 1) next
  for (j in seq_len(i - 1)) {
    if (identical(signatures[[i]], signatures[[j]])) {
      duplicate_of[defs$cohort_def[i]] <- defs$cohort_def[j]
      break
    }
  }
}

dup_check <- data.frame(
  cohort_order = as.integer(defs$cohort_order),
  cohort_def = as.character(defs$cohort_def),
  duplicate_of = as.character(unname(duplicate_of[defs$cohort_def])),
  is_exact_duplicate = as.logical(!is.na(unname(duplicate_of[defs$cohort_def]))),
  stringsAsFactors = FALSE
)

data.table::fwrite(
  dup_check,
  file.path(OUT_DIR, "00A_exact_duplicate_definition_check.csv")
)

# ------------------------------------------------------------
# Descriptive counts
# ------------------------------------------------------------

desc <- sens[, .(
  n=as.integer(.N),
  deaths=as.integer(sum(death, na.rm=TRUE)),
  mortality=as.numeric(mean(death, na.rm=TRUE)),
  mean_age=as.numeric(mean(age, na.rm=TRUE)),
  female_n=as.integer(sum(female2, na.rm=TRUE)),
  female_pct=as.numeric(100*mean(female2, na.rm=TRUE)),
  mean_CCI=as.numeric(mean(cci_chronic_burden_no_age, na.rm=TRUE)),
  median_CCI=as.numeric(median(cci_chronic_burden_no_age, na.rm=TRUE)),
  mean_FI=as.numeric(mean(filab18_score, na.rm=TRUE)),
  median_FI=as.numeric(median(filab18_score, na.rm=TRUE)),
  mean_n_measured=as.numeric(mean(n_measured, na.rm=TRUE)),
  mean_GCS=as.numeric(mean(gcs_min, na.rm=TRUE)),
  invasive_vent_n=as.integer(sum(imv, na.rm=TRUE)),
  invasive_vent_pct=as.numeric(100*mean(imv, na.rm=TRUE)),
  vasopressor_n=as.integer(sum(vaso, na.rm=TRUE)),
  vasopressor_pct=as.numeric(100*mean(vaso, na.rm=TRUE))
), by=.(cohort_order,cohort_def)]

data.table::fwrite(
  desc,
  file.path(OUT_DIR, "01_completecase_descriptive_by_definition.csv")
)

# ------------------------------------------------------------
# Fit identical primary interaction models
# ------------------------------------------------------------

full_formula <- death ~ cci_c * fi01_c + age10_c + female2 + gcs_c + imv + vaso
reduced_formula <- death ~ cci_c + fi01_c + age10_c + female2 + gcs_c + imv + vaso

fits <- list()
main_rows <- list()
lrt_rows <- list()
add_rows <- list()
coef_rows <- list()

for (i in seq_len(nrow(defs))) {
  def <- defs$cohort_def[i]
  ord <- defs$cohort_order[i]

  dup <- duplicate_of[[def]]

  if (!is.na(dup)) {
    cat("\nExact duplicate detected:", def, "=", dup, "\n")
    cat("Reusing fitted model and additive-interaction simulation results.\n")

    fits[[def]] <- fits[[dup]]

    prev_main <- main_rows[[dup]]
    prev_main$cohort_order <- ord
    prev_main$cohort_def <- def
    prev_main$duplicate_of <- dup
    main_rows[[def]] <- prev_main

    prev_coef <- coef_rows[[dup]]
    prev_coef$cohort_order <- ord
    prev_coef$cohort_def <- def
    prev_coef$duplicate_of <- dup
    coef_rows[[def]] <- prev_coef

    prev_add <- add_rows[[dup]]
    prev_add$cohort_order <- ord
    prev_add$cohort_def <- def
    prev_add$duplicate_of <- dup
    add_rows[[def]] <- prev_add

    next
  }

  d <- as.data.frame(sens[cohort_def==def])

  fit_full <- glm(full_formula, family=binomial(), data=d)
  fit_red <- glm(reduced_formula, family=binomial(), data=d)

  fits[[def]] <- fit_full

  fi <- coef_extract(fit_full, "fi01_c")
  cc <- coef_extract(fit_full, "cci_c")
  ix <- coef_extract(fit_full, "cci_c:fi01_c")
  lrt <- lrt_test(fit_red, fit_full)

  main_rows[[def]] <- data.frame(
    cohort_order=ord,
    cohort_def=def,
    duplicate_of=NA_character_,
    n=nrow(d),
    deaths=sum(d$death),

    CCI_OR=cc["OR"],
    CCI_CI_low=cc["CI_low"],
    CCI_CI_high=cc["CI_high"],
    CCI_Wald_p=cc["p"],

    FI_OR_per_0_1=fi["OR"],
    FI_CI_low=fi["CI_low"],
    FI_CI_high=fi["CI_high"],
    FI_Wald_p=fi["p"],

    interaction_OR=ix["OR"],
    interaction_CI_low=ix["CI_low"],
    interaction_CI_high=ix["CI_high"],
    interaction_Wald_p=ix["p"],

    interaction_LRT_chisq=lrt["chisq"],
    interaction_LRT_df=lrt["df"],
    interaction_LRT_p=lrt["p"]
  )

  sm <- summary(fit_full)$coefficients
  coef_rows[[def]] <- data.frame(
    cohort_order=ord,
    cohort_def=def,
    duplicate_of=NA_character_,
    term=rownames(sm),
    beta=sm[,1],
    SE=sm[,2],
    OR=exp(sm[,1]),
    CI_low=exp(sm[,1]-1.96*sm[,2]),
    CI_high=exp(sm[,1]+1.96*sm[,2]),
    p_value=sm[,4],
    row.names=NULL
  )

  cat("\nAdditive interaction simulation:", def, "\n")
  add <- additive_interaction(
    fit_full,
    d,
    B=5000L,
    seed=20260926L + ord
  )

  add_rows[[def]] <- data.frame(
    cohort_order=ord,
    cohort_def=def,
    duplicate_of=NA_character_,
    n=nrow(d),
    deaths=sum(d$death),
    additive_interaction_probability=add["estimate"],
    additive_interaction_pp=100*add["estimate"],
    CI_low_probability=add["CI_low"],
    CI_high_probability=add["CI_high"],
    CI_low_pp=100*add["CI_low"],
    CI_high_pp=100*add["CI_high"],
    simulation_B=5000
  )
}

main_out <- data.table::rbindlist(main_rows, fill=TRUE)
coef_out <- data.table::rbindlist(coef_rows, fill=TRUE)
add_out <- data.table::rbindlist(add_rows, fill=TRUE)

data.table::fwrite(
  main_out,
  file.path(OUT_DIR, "02_primary_model_results_by_definition.csv")
)
data.table::fwrite(
  add_out,
  file.path(OUT_DIR, "03_additive_interaction_by_definition.csv")
)
data.table::fwrite(
  coef_out,
  file.path(OUT_DIR, "04_all_coefficients_by_definition.csv")
)

# ------------------------------------------------------------
# Frozen P0 numerical benchmark
# ------------------------------------------------------------

p0res <- main_out[cohort_def=="P0_PRIMARY_FROZEN"]
p0add <- add_out[cohort_def=="P0_PRIMARY_FROZEN"]

benchmark <- data.frame(
  metric=c(
    "n",
    "deaths",
    "CCI_OR",
    "FI_OR_per_0_1",
    "interaction_OR",
    "interaction_Wald_p",
    "interaction_LRT_p",
    "additive_interaction_pp"
  ),
  expected=c(
    1665,
    183,
    1.010,
    1.318,
    1.032,
    0.2078,
    0.2064,
    0.321
  ),
  observed=c(
    p0res$n,
    p0res$deaths,
    p0res$CCI_OR,
    p0res$FI_OR_per_0_1,
    p0res$interaction_OR,
    p0res$interaction_Wald_p,
    p0res$interaction_LRT_p,
    p0add$additive_interaction_pp
  )
)

benchmark$absolute_difference <- abs(
  benchmark$observed-benchmark$expected
)

data.table::fwrite(
  benchmark,
  file.path(OUT_DIR, "05_P0_frozen_numerical_benchmark.csv")
)

# ------------------------------------------------------------
# Comparison against frozen P0
# ------------------------------------------------------------

p0_beta_fi <- coef(fits[["P0_PRIMARY_FROZEN"]])["fi01_c"]
p0_beta_ix <- coef(fits[["P0_PRIMARY_FROZEN"]])["cci_c:fi01_c"]

comparison <- copy(main_out)
comparison[, `:=`(
  delta_FI_OR_vs_P0 = FI_OR_per_0_1 - p0res$FI_OR_per_0_1,
  ratio_FI_OR_vs_P0 = FI_OR_per_0_1 / p0res$FI_OR_per_0_1,
  delta_interaction_OR_vs_P0 = interaction_OR - p0res$interaction_OR,
  ratio_interaction_OR_vs_P0 = interaction_OR / p0res$interaction_OR,
  FI_beta_direction_same_as_P0 = NA,
  interaction_beta_direction_same_as_P0 = NA
)]

for (j in seq_len(nrow(comparison))) {
  def <- comparison$cohort_def[j]
  bb <- coef(fits[[def]])

  comparison$FI_beta_direction_same_as_P0[j] <-
    sign(bb["fi01_c"]) == sign(p0_beta_fi)

  comparison$interaction_beta_direction_same_as_P0[j] <-
    sign(bb["cci_c:fi01_c"]) == sign(p0_beta_ix)
}

data.table::fwrite(
  comparison,
  file.path(OUT_DIR, "06_comparison_vs_frozen_P0.csv")
)

# ------------------------------------------------------------
# Cohort overlap relative to P0
# ------------------------------------------------------------

p0ids <- sens[
  cohort_def=="P0_PRIMARY_FROZEN",
  .(subject_id,hadm_id,stay_id)
]

overlap_rows <- list()

for (i in seq_len(nrow(defs))) {
  def <- defs$cohort_def[i]
  ord <- defs$cohort_order[i]
  z <- sens[cohort_def==def, .(subject_id,hadm_id,stay_id)]

  shared_subject <- length(intersect(
    unique(p0ids$subject_id),
    unique(z$subject_id)
  ))

  exact_stay <- nrow(merge(
    p0ids, z,
    by=c("subject_id","hadm_id","stay_id")
  ))

  overlap_rows[[def]] <- data.frame(
    cohort_order=as.integer(ord),
    cohort_def=def,
    n=as.integer(nrow(z)),
    shared_subjects_with_P0=as.integer(shared_subject),
    exact_same_index_stay_as_P0=as.integer(exact_stay),
    new_subjects_vs_P0=as.integer(nrow(z)-shared_subject)
  )
}

overlap <- data.table::rbindlist(overlap_rows)
data.table::fwrite(
  overlap,
  file.path(OUT_DIR, "07_cohort_overlap_vs_P0.csv")
)

# ------------------------------------------------------------
# Quick summary
# ------------------------------------------------------------

fmt_or <- function(or,lo,hi) {
  sprintf("%.3f (%.3f-%.3f)", or,lo,hi)
}
fmt_p <- function(x) {
  if (is.na(x)) return("NA")
  if (x < 0.0001) return("<0.0001")
  sprintf("%.4f", x)
}

lines <- c(
  "BROADER AIS CASE-DEFINITION SENSITIVITY",
  "=======================================",
  "",
  "P0 row-level audit passed against frozen H94.",
  "",
  ifelse(any(dup_check$is_exact_duplicate),
         paste0("Exact duplicate definition(s): ", paste(dup_check$cohort_def[dup_check$is_exact_duplicate], "=", dup_check$duplicate_of[dup_check$is_exact_duplicate], collapse="; ")),
         "No exact duplicate definitions detected."),
  "",
  "Definition-level adjusted results:"
)

for (i in seq_len(nrow(main_out))) {
  z <- main_out[i]
  a <- add_out[cohort_def==z$cohort_def]

  lines <- c(
    lines,
    "",
    paste0(z$cohort_def, ": n=", z$n, ", deaths=", z$deaths),
    paste0(
      "  FI-Lab OR per +0.1: ",
      fmt_or(z$FI_OR_per_0_1,z$FI_CI_low,z$FI_CI_high),
      "; p=", fmt_p(z$FI_Wald_p)
    ),
    paste0(
      "  Interaction OR: ",
      fmt_or(z$interaction_OR,z$interaction_CI_low,z$interaction_CI_high),
      "; Wald p=", fmt_p(z$interaction_Wald_p),
      "; LRT p=", fmt_p(z$interaction_LRT_p)
    ),
    paste0(
      "  Standardized additive interaction: ",
      sprintf("%+.3f pp", a$additive_interaction_pp),
      " (",
      sprintf("%+.3f", a$CI_low_pp),
      " to ",
      sprintf("%+.3f", a$CI_high_pp),
      " pp)"
    )
  )
}

writeLines(
  lines,
  file.path(OUT_DIR, "08_QUICK_SUMMARY.txt")
)

# ------------------------------------------------------------
# Manifest + session
# ------------------------------------------------------------

manifest <- data.frame(
  file=c(
    "00_P0_vs_frozen_H94_rowlevel_audit.csv",
    "00A_exact_duplicate_definition_check.csv",
    "01_completecase_descriptive_by_definition.csv",
    "02_primary_model_results_by_definition.csv",
    "03_additive_interaction_by_definition.csv",
    "04_all_coefficients_by_definition.csv",
    "05_P0_frozen_numerical_benchmark.csv",
    "06_comparison_vs_frozen_P0.csv",
    "07_cohort_overlap_vs_P0.csv",
    "08_QUICK_SUMMARY.txt",
    "sessionInfo.txt"
  ),
  purpose=c(
    "Critical row-level reconstruction audit against frozen H94",
    "Detect exact duplicate case-definition cohorts and reuse results",
    "Complete-case descriptive statistics",
    "Adjusted FI, CCI, multiplicative interaction, Wald/LRT",
    "Standardized additive interaction with 5000 simulations",
    "Full model coefficients",
    "Frozen P0 numerical result reproduction",
    "Effect comparison with frozen P0",
    "Overlap/new subjects introduced by broader definitions",
    "Concise result summary",
    "R environment"
  )
)

data.table::fwrite(
  manifest,
  file.path(OUT_DIR, "OUTPUT_MANIFEST.csv")
)

capture.output(
  sessionInfo(),
  file=file.path(OUT_DIR, "sessionInfo.txt")
)

cat("\n============================================================\n")
cat("BROADER AIS SENSITIVITY COMPLETE\n")
cat("============================================================\n")
cat("Output:\n", OUT_DIR, "\n\n")
cat("Upload the entire BROADER_AIS_SENS_* folder.\n")
cat("Priority files:\n")
cat("  00_P0_vs_frozen_H94_rowlevel_audit.csv\n")
cat("  02_primary_model_results_by_definition.csv\n")
cat("  03_additive_interaction_by_definition.csv\n")
cat("  05_P0_frozen_numerical_benchmark.csv\n")
cat("  06_comparison_vs_frozen_P0.csv\n")
cat("  08_QUICK_SUMMARY.txt\n")
cat("============================================================\n")
