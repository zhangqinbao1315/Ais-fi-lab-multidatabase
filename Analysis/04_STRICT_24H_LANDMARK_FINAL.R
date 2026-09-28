# ============================================================
# RUN_04_STRICT_24H_LANDMARK_FINAL.R
# ============================================================
# Final REVISED replacement analysis for the secondary 24-h landmark model.
#
# Rationale:
#   The original V5 landmark model included hospitalization-level modified CCI,
#   which is not guaranteed to be available by the 24-h prediction time.
#   The final strict landmark model therefore uses ONLY variables available
#   within/by the first ICU day:
#
#   hospital mortality ~
#     Core-18 FI-Lab + age + sex + GCS + invasive ventilation + vasopressor
#
# Development:
#   MIMIC-IV H94-derived 24-h landmark cohort
#
# External validation:
#   eICU-CRD 24-h landmark cohort
#   MIMIC coefficients applied FIXED, with NO refitting and NO recalibration
#   before primary validation metrics.
#
# Hospital-cluster bootstrap:
#   eICU, B = 1000
#
# Continuous calibration:
#   fixed predictions + prespecified natural-spline smoother in eICU
#   with hospital-cluster bootstrap CI, B = 1000
#
# This script does NOT change:
#   - the primary full-cohort association model;
#   - modified CCI definition in the association analysis;
#   - Core-18 definition or thresholds.
# ============================================================

options(stringsAsFactors = FALSE)
options(width = 160)

# ------------------------------------------------------------
# Packages
# ------------------------------------------------------------

required_pkgs <- c("data.table", "pROC", "jsonlite", "readxl")
missing_pkgs <- required_pkgs[
  !vapply(required_pkgs, requireNamespace, logical(1), quietly=TRUE)
]
if (length(missing_pkgs)) {
  install.packages(missing_pkgs, repos="https://cloud.r-project.org")
}

still_missing <- required_pkgs[
  !vapply(required_pkgs, requireNamespace, logical(1), quietly=TRUE)
]
if (length(still_missing)) {
  stop("Missing R packages: ", paste(still_missing, collapse=", "))
}

# ------------------------------------------------------------
# Paths — robust CSV/XLS/XLSX locator
# ------------------------------------------------------------

norm <- function(x) normalizePath(x, winslash="/", mustWork=TRUE)

active_dir <- NA_character_
if (requireNamespace("rstudioapi", quietly=TRUE) && rstudioapi::isAvailable()) {
  ctx <- try(rstudioapi::getActiveDocumentContext(), silent=TRUE)
  if (!inherits(ctx, "try-error") && length(ctx$path) && nzchar(ctx$path)) {
    active_dir <- dirname(norm(ctx$path))
  }
}

candidate_dirs <- unique(na.omit(c(
  active_dir,
  norm(getwd())
)))

find_named_table <- function(d, base_names) {
  if (!dir.exists(d)) return(NA_character_)
  ff <- list.files(d, full.names=TRUE)
  if (!length(ff)) return(NA_character_)

  exts <- tolower(tools::file_ext(ff))
  ok_ext <- exts %in% c("csv","xls","xlsx")
  ff <- ff[ok_ext]
  if (!length(ff)) return(NA_character_)

  stems <- tolower(tools::file_path_sans_ext(basename(ff)))
  wanted <- tolower(base_names)

  ii <- which(stems %in% wanted)
  if (length(ii)) return(ff[ii[1]])
  NA_character_
}

find_pair_in_dir <- function(d) {
  mf <- find_named_table(
    d,
    c("H94_primary_model_completecase",
      "mimic_H94_primary_model_completecase")
  )
  ef <- find_named_table(
    d,
    c("eicu_50_primary_model_completecase")
  )
  list(mimic=mf, eicu=ef)
}

DATA_DIR <- NA_character_
mimic_file <- NA_character_
eicu_file <- NA_character_

# First try active script folder / current working directory automatically.
for (d in candidate_dirs) {
  pp <- find_pair_in_dir(d)
  if (!is.na(pp$mimic) && !is.na(pp$eicu)) {
    DATA_DIR <- norm(d)
    mimic_file <- norm(pp$mimic)
    eicu_file <- norm(pp$eicu)
    break
  }
}

# If not found, select H94 once. The script then searches the same folder
# for eICU-50 automatically.
if (is.na(DATA_DIR)) {
  cat("\n没有自动找到两个数据文件。\n")
  cat("现在只需要选择一次 H94 文件即可。\n")
  cat("支持 CSV / XLS / XLSX。\n\n")

  if (.Platform$OS.type == "windows") {
    pick <- utils::choose.files(
      caption="请选择 H94_primary_model_completecase 文件",
      filters=matrix(
        c(
          "Data files (*.csv;*.xls;*.xlsx)",
          "*.csv;*.xls;*.xlsx",
          "All files (*.*)",
          "*.*"
        ),
        ncol=2, byrow=TRUE
      ),
      multi=FALSE
    )
    if (!length(pick) || !nzchar(pick[1])) {
      stop("没有选择 H94 文件。")
    }
    mimic_file <- norm(pick[1])
  } else {
    mimic_file <- norm(file.choose())
  }

  DATA_DIR <- dirname(mimic_file)
  eicu_file <- find_named_table(
    DATA_DIR,
    c("eicu_50_primary_model_completecase")
  )

  if (is.na(eicu_file)) {
    cat("\n同一文件夹没有自动找到 eICU-50。\n")
    cat("请再选择一次 eICU_50_primary_model_completecase 文件。\n\n")

    if (.Platform$OS.type == "windows") {
      pick2 <- utils::choose.files(
        caption="请选择 eicu_50_primary_model_completecase 文件",
        filters=matrix(
          c(
            "Data files (*.csv;*.xls;*.xlsx)",
            "*.csv;*.xls;*.xlsx",
            "All files (*.*)",
            "*.*"
          ),
          ncol=2, byrow=TRUE
        ),
        multi=FALSE
      )
      if (!length(pick2) || !nzchar(pick2[1])) {
        stop("没有选择 eICU-50 文件。")
      }
      eicu_file <- norm(pick2[1])
    } else {
      eicu_file <- norm(file.choose())
    }
  } else {
    eicu_file <- norm(eicu_file)
  }
}

cat("\n============================================================\n")
cat("DATA DIRECTORY FOUND\n")
cat("============================================================\n")
cat("MIMIC input:\n  ", mimic_file, "\n")
cat("eICU input:\n  ", eicu_file, "\n")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
OUT_DIR <- file.path(
  DATA_DIR,
  "results",
  paste0("STRICT_24H_LANDMARK_REVISED_1496_162_", stamp)
)
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)

cat("Output:\n  ", OUT_DIR, "\n\n")

read_frozen_table <- function(path) {
  ext <- tolower(tools::file_ext(path))

  if (ext == "csv") {
    return(data.table::fread(path))
  }

  if (ext %in% c("xls","xlsx")) {
    return(data.table::as.data.table(
      readxl::read_excel(path)
    ))
  }

  stop("Unsupported input type: ", ext,
       ". Please use CSV, XLS, or XLSX.")
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

check_cols <- function(d, need, label) {
  miss <- setdiff(need, names(d))
  if (length(miss)) {
    stop(label, " missing columns: ", paste(miss, collapse=", "))
  }
}

safe_auc <- function(y, p) {
  if (length(unique(y[!is.na(y)])) < 2) return(NA_real_)
  as.numeric(
    pROC::auc(
      pROC::roc(y, p, quiet=TRUE)
    )
  )
}

brier <- function(y, p) {
  mean((y-p)^2, na.rm=TRUE)
}

calibration_intercept <- function(y, lp) {
  fit <- try(
    glm(y ~ 1 + offset(lp), family=binomial()),
    silent=TRUE
  )
  if (inherits(fit, "try-error")) return(NA_real_)
  unname(coef(fit)[1])
}

calibration_slope <- function(y, lp) {
  fit <- try(
    glm(y ~ lp, family=binomial()),
    silent=TRUE
  )
  if (inherits(fit, "try-error")) return(NA_real_)
  unname(coef(fit)["lp"])
}

coef_table <- function(fit) {
  sm <- summary(fit)$coefficients
  data.frame(
    term=rownames(sm),
    beta=sm[,1],
    SE=sm[,2],
    OR=exp(sm[,1]),
    CI_low=exp(sm[,1]-1.96*sm[,2]),
    CI_high=exp(sm[,1]+1.96*sm[,2]),
    p_value=sm[,4],
    row.names=NULL
  )
}

point_metrics <- function(d, pred, lp, dataset) {
  data.frame(
    dataset=dataset,
    n=nrow(d),
    deaths=sum(d$death, na.rm=TRUE),
    mortality=mean(d$death, na.rm=TRUE),
    AUC=safe_auc(d$death, pred),
    Brier=brier(d$death, pred),
    mean_predicted_risk=mean(pred, na.rm=TRUE),
    calibration_intercept=calibration_intercept(d$death, lp),
    calibration_slope=calibration_slope(d$death, lp)
  )
}

# ------------------------------------------------------------
# Load frozen files
# ------------------------------------------------------------

m0 <- read_frozen_table(mimic_file)
e0 <- read_frozen_table(eicu_file)

need_m <- c(
  "hospital_expire_flag",
  "icu_los_days",
  "days_to_death_from_icu",
  "filab18_per_0_1",
  "age",
  "female",
  "gcs_min",
  "any_invasive_vent_m6p24",
  "any_vasopressor_m6p24"
)

need_e <- c(
  "hospital_mortality",
  "hospitalid",
  "unitdischargeoffset",
  "filab18_per_0_1",
  "age_numeric",
  "sex_female",
  "gcs",
  "invasive_ventilation_day1",
  "vasopressor_use_firstday"
)

check_cols(m0, need_m, "MIMIC H94")
check_cols(e0, need_e, "eICU-50")

# ------------------------------------------------------------
# Build strict 24-h landmark samples
# ------------------------------------------------------------

# MIMIC:
# Must still be alive and in ICU at 24 h.
m <- m0[
  icu_los_days >= 1 &
  !(
    hospital_expire_flag == 1 &
    !is.na(days_to_death_from_icu) &
    days_to_death_from_icu <= 1
  )
]

# eICU:
# Must still be in ICU at 24 h.
e <- e0[unitdischargeoffset >= 1440]

# Harmonized centered variables.
FI_CENTER <- 2.777777777777778   # FI 0.2777778 on per-0.1 scale
AGE_CENTER <- 65
GCS_CENTER <- 15

m[, `:=`(
  death=as.integer(hospital_expire_flag),
  fi01_c=as.numeric(filab18_per_0_1)-FI_CENTER,
  age10_c=(as.numeric(age)-AGE_CENTER)/10,
  female2=as.integer(female),
  gcs_c=as.numeric(gcs_min)-GCS_CENTER,
  imv=as.integer(any_invasive_vent_m6p24),
  vaso=as.integer(any_vasopressor_m6p24)
)]

e[, `:=`(
  death=as.integer(hospital_mortality),
  fi01_c=as.numeric(filab18_per_0_1)-FI_CENTER,
  age10_c=(as.numeric(age_numeric)-AGE_CENTER)/10,
  female2=as.integer(sex_female),
  gcs_c=as.numeric(gcs)-GCS_CENTER,
  imv=as.integer(invasive_ventilation_day1),
  vaso=as.integer(vasopressor_use_firstday)
)]

model_vars <- c(
  "death","fi01_c","age10_c","female2","gcs_c","imv","vaso"
)

m <- m[complete.cases(m[, ..model_vars])]
e <- e[complete.cases(e[, c(model_vars,"hospitalid"), with=FALSE])]

# ------------------------------------------------------------
# Frozen sample count check — hard stop
# ------------------------------------------------------------

sample_check <- data.frame(
  dataset=c("MIMIC strict 24-h landmark","eICU strict 24-h landmark"),
  expected_n=c(1496,1638),
  expected_deaths=c(162,168),
  observed_n=c(nrow(m),nrow(e)),
  observed_deaths=c(sum(m$death),sum(e$death))
)
sample_check$n_match <- sample_check$expected_n == sample_check$observed_n
sample_check$deaths_match <- (
  sample_check$expected_deaths == sample_check$observed_deaths
)

data.table::fwrite(
  sample_check,
  file.path(OUT_DIR, "00_sample_reproduction_check.csv")
)

if (!all(sample_check$n_match) || !all(sample_check$deaths_match)) {
  stop(
    "Strict landmark samples do NOT match the previously verified analysis: ",
    "expected MIMIC 1496/162 and eICU 1638/168. STOP."
  )
}


# Provenance note:
# The MIMIC benchmark was revised after direct SQL audit of the authoritative
# raw-reconstructed H94 table. Under the stated landmark rule (ICU LOS >=24 h
# and alive beyond 24 h), H94 reproducibly yields n=1496 and 162 subsequent
# hospital deaths. Four patients died between >24 h and <=30 h and therefore
# belong in the landmark cohort.

# ------------------------------------------------------------
# Final MIMIC development model
# ------------------------------------------------------------

final_formula <- death ~ fi01_c + age10_c + female2 + gcs_c + imv + vaso

fit_m <- glm(
  final_formula,
  family=binomial(),
  data=as.data.frame(m)
)

coef_m <- coef_table(fit_m)
coef_m$interpretation_scale <- c(
  "intercept at centered reference values",
  "per +0.1 FI-Lab",
  "per +10 years age",
  "female vs male",
  "per +1 GCS point",
  "yes vs no",
  "yes vs no"
)

data.table::fwrite(
  coef_m,
  file.path(OUT_DIR, "01_MIMIC_final_model_coefficients.csv")
)

# Exact fixed coefficients file for S4 / external validation.
fixed_coef <- data.frame(
  term=names(coef(fit_m)),
  beta=unname(coef(fit_m))
)
data.table::fwrite(
  fixed_coef,
  file.path(OUT_DIR, "01A_FIXED_COEFFICIENTS_FOR_eICU.csv")
)

# ------------------------------------------------------------
# Apparent MIMIC predictions and FIXED eICU predictions
# ------------------------------------------------------------

m[, lp := as.numeric(predict(fit_m, newdata=as.data.frame(m), type="link"))]
m[, pred := plogis(lp)]

e[, lp_fixed := as.numeric(
  predict(fit_m, newdata=as.data.frame(e), type="link")
)]
e[, pred_fixed := plogis(lp_fixed)]

m_perf <- point_metrics(
  m,
  m$pred,
  m$lp,
  "MIMIC apparent"
)

# For development cohort, calibration intercept/slope are mathematically
# ~0 and ~1; retained only for audit.
e_perf <- point_metrics(
  e,
  e$pred_fixed,
  e$lp_fixed,
  "eICU fixed-coefficient external validation"
)

point_perf <- data.table::rbindlist(
  list(m_perf,e_perf),
  fill=TRUE
)

data.table::fwrite(
  point_perf,
  file.path(OUT_DIR, "02_final_point_performance.csv")
)

# ------------------------------------------------------------
# eICU calibration smoother setup
# Prespecified from the ORIGINAL eICU fixed linear predictor distribution.
# ------------------------------------------------------------

cal_knots <- as.numeric(
  quantile(e$lp_fixed, c(.25,.50,.75), na.rm=TRUE, names=FALSE)
)
cal_boundary <- as.numeric(
  quantile(e$lp_fixed, c(.01,.99), na.rm=TRUE, names=FALSE)
)

cal_settings <- data.frame(
  parameter=c(
    "smoother",
    "internal_knots_lp_q25",
    "internal_knots_lp_q50",
    "internal_knots_lp_q75",
    "boundary_lp_q01",
    "boundary_lp_q99",
    "bootstrap_B"
  ),
  value=c(
    "natural spline on fixed logit risk; 3 internal knots",
    cal_knots[1],
    cal_knots[2],
    cal_knots[3],
    cal_boundary[1],
    cal_boundary[2],
    "1000 hospital-cluster bootstrap replicates"
  )
)

data.table::fwrite(
  cal_settings,
  file.path(OUT_DIR, "03_calibration_curve_settings.csv")
)

fit_cal_curve <- function(d) {
  try(
    glm(
      death ~ splines::ns(
        lp_fixed,
        knots=cal_knots,
        Boundary.knots=cal_boundary
      ),
      family=binomial(),
      data=as.data.frame(d)
    ),
    silent=TRUE
  )
}

grid_lp <- seq(
  as.numeric(quantile(e$lp_fixed,.01,na.rm=TRUE)),
  as.numeric(quantile(e$lp_fixed,.99,na.rm=TRUE)),
  length.out=201
)

cal_fit_original <- fit_cal_curve(e)
if (inherits(cal_fit_original, "try-error")) {
  stop("Original eICU calibration smoother failed.")
}

grid_df <- data.frame(lp_fixed=grid_lp)
grid_observed <- plogis(
  predict(
    cal_fit_original,
    newdata=grid_df,
    type="link"
  )
)
grid_predicted <- plogis(grid_lp)

# ------------------------------------------------------------
# eICU hospital-cluster bootstrap:
# metrics + calibration curve in one loop
# ------------------------------------------------------------

B <- 1000L
SEED <- 20260926L
set.seed(SEED)

hospitals <- unique(e$hospitalid)

boot_metrics <- matrix(
  NA_real_,
  nrow=B,
  ncol=4,
  dimnames=list(
    NULL,
    c(
      "AUC",
      "Brier",
      "calibration_intercept",
      "calibration_slope"
    )
  )
)

boot_curve <- matrix(
  NA_real_,
  nrow=B,
  ncol=length(grid_lp)
)

pb <- txtProgressBar(min=0,max=B,style=3)

for (b in seq_len(B)) {
  sampled_hospitals <- sample(
    hospitals,
    length(hospitals),
    replace=TRUE
  )

  dd <- data.table::rbindlist(
    lapply(seq_along(sampled_hospitals), function(j) {
      z <- e[hospitalid == sampled_hospitals[j]]
      z[, bootstrap_cluster__ := j]
      z
    }),
    use.names=TRUE,
    fill=TRUE
  )

  if (length(unique(dd$death)) >= 2) {
    boot_metrics[b,"AUC"] <- safe_auc(
      dd$death,
      dd$pred_fixed
    )
    boot_metrics[b,"Brier"] <- brier(
      dd$death,
      dd$pred_fixed
    )
    boot_metrics[b,"calibration_intercept"] <- calibration_intercept(
      dd$death,
      dd$lp_fixed
    )
    boot_metrics[b,"calibration_slope"] <- calibration_slope(
      dd$death,
      dd$lp_fixed
    )

    fcb <- fit_cal_curve(dd)
    if (!inherits(fcb, "try-error")) {
      pr <- try(
        plogis(
          predict(
            fcb,
            newdata=grid_df,
            type="link"
          )
        ),
        silent=TRUE
      )
      if (!inherits(pr, "try-error") &&
          length(pr)==length(grid_lp) &&
          all(is.finite(pr))) {
        boot_curve[b,] <- pr
      }
    }
  }

  if (b %% 10 == 0 || b == B) {
    setTxtProgressBar(pb,b)
  }
}

close(pb)

# ------------------------------------------------------------
# Bootstrap metric CIs
# ------------------------------------------------------------

point_e <- c(
  AUC=e_perf$AUC,
  Brier=e_perf$Brier,
  calibration_intercept=e_perf$calibration_intercept,
  calibration_slope=e_perf$calibration_slope
)

boot_ci_rows <- lapply(names(point_e), function(metric) {
  x <- boot_metrics[,metric]
  data.frame(
    metric=metric,
    estimate=as.numeric(point_e[[metric]]),
    CI_low=as.numeric(quantile(x,.025,na.rm=TRUE)),
    CI_high=as.numeric(quantile(x,.975,na.rm=TRUE)),
    successful_bootstrap_replicates=sum(is.finite(x)),
    requested_bootstrap_replicates=B
  )
})

boot_ci <- data.table::rbindlist(boot_ci_rows)

data.table::fwrite(
  boot_ci,
  file.path(OUT_DIR, "04_eICU_hospital_cluster_bootstrap_CI.csv")
)

# ------------------------------------------------------------
# Calibration curve bootstrap CI
# ------------------------------------------------------------

curve_low <- apply(
  boot_curve, 2,
  quantile, probs=.025, na.rm=TRUE
)
curve_high <- apply(
  boot_curve, 2,
  quantile, probs=.975, na.rm=TRUE
)
curve_success <- colSums(is.finite(boot_curve))

cal_curve <- data.frame(
  predicted_risk=grid_predicted,
  smoothed_observed_risk=grid_observed,
  CI_low=curve_low,
  CI_high=curve_high,
  successful_bootstrap_replicates=curve_success
)

data.table::fwrite(
  cal_curve,
  file.path(OUT_DIR, "05_eICU_continuous_calibration_curve.csv")
)

# ------------------------------------------------------------
# Generate FINAL replacement calibration figure
# ------------------------------------------------------------

draw_calibration <- function() {
  max_axis <- max(
    c(
      cal_curve$predicted_risk,
      cal_curve$smoothed_observed_risk,
      cal_curve$CI_high
    ),
    na.rm=TRUE
  )

  # Keep sensible calibration display limits.
  max_axis <- min(max(max_axis*1.05,0.40),1.00)

  plot(
    cal_curve$predicted_risk,
    cal_curve$smoothed_observed_risk,
    type="l",
    lwd=2,
    xlim=c(0,max_axis),
    ylim=c(0,max_axis),
    xlab="Predicted hospital mortality risk",
    ylab="Observed hospital mortality risk",
    main="eICU external calibration of the strict 24-hour landmark model"
  )

  lines(
    cal_curve$predicted_risk,
    cal_curve$CI_low,
    lty=2
  )
  lines(
    cal_curve$predicted_risk,
    cal_curve$CI_high,
    lty=2
  )

  abline(
    a=0,b=1,
    lty=3
  )

  rug(
    e$pred_fixed,
    side=1,
    ticksize=0.025
  )

  legend(
    "topleft",
    legend=c(
      "Continuous calibration",
      "95% cluster-bootstrap interval",
      "Ideal calibration"
    ),
    lty=c(1,2,3),
    lwd=c(2,1,1),
    bty="n"
  )
}

png(
  file.path(
    OUT_DIR,
    "Fig4_STRICT_24H_eICU_calibration.png"
  ),
  width=2400,
  height=1800,
  res=300
)
draw_calibration()
dev.off()

tiff(
  file.path(
    OUT_DIR,
    "Fig4_STRICT_24H_eICU_calibration.tif"
  ),
  width=7.5,
  height=5.5,
  units="in",
  res=600,
  compression="lzw"
)
draw_calibration()
dev.off()

# ------------------------------------------------------------
# Aggregate predicted-risk distribution for reporting / S5
# No patient-level predictions are exported.
# ------------------------------------------------------------

risk_summary <- data.frame(
  dataset="eICU strict 24-h fixed-coefficient validation",
  n=nrow(e),
  deaths=sum(e$death),
  observed_mortality=mean(e$death),
  mean_predicted_risk=mean(e$pred_fixed),
  sd_predicted_risk=sd(e$pred_fixed),
  q01=unname(quantile(e$pred_fixed,.01)),
  q05=unname(quantile(e$pred_fixed,.05)),
  q25=unname(quantile(e$pred_fixed,.25)),
  q50=unname(quantile(e$pred_fixed,.50)),
  q75=unname(quantile(e$pred_fixed,.75)),
  q95=unname(quantile(e$pred_fixed,.95)),
  q99=unname(quantile(e$pred_fixed,.99))
)

data.table::fwrite(
  risk_summary,
  file.path(OUT_DIR, "06_eICU_predicted_risk_aggregate_summary.csv")
)

# ------------------------------------------------------------
# Direct old-V5 vs strict-model comparison
# Old values are frozen manuscript values, included ONLY for change tracking.
# ------------------------------------------------------------

old_vs_new <- data.frame(
  metric=c(
    "MIMIC n",
    "MIMIC deaths",
    "MIMIC AUC",
    "MIMIC Brier",
    "eICU n",
    "eICU deaths",
    "eICU AUC",
    "eICU Brier",
    "eICU observed mortality",
    "eICU mean predicted risk",
    "eICU calibration intercept",
    "eICU calibration slope"
  ),
  old_V5_with_hospitalization_CCI=c(
    1492,
    158,
    0.839,
    0.08088,
    1638,
    168,
    0.782,
    0.09080,
    0.1026,
    0.1323,
    -0.411,
    0.633
  ),
  strict_24h_no_CCI=c(
    nrow(m),
    sum(m$death),
    m_perf$AUC,
    m_perf$Brier,
    nrow(e),
    sum(e$death),
    e_perf$AUC,
    e_perf$Brier,
    e_perf$mortality,
    e_perf$mean_predicted_risk,
    e_perf$calibration_intercept,
    e_perf$calibration_slope
  )
)
old_vs_new$difference <- (
  old_vs_new$strict_24h_no_CCI -
  old_vs_new$old_V5_with_hospitalization_CCI
)

data.table::fwrite(
  old_vs_new,
  file.path(OUT_DIR, "07_old_V5_vs_strict_24h_comparison.csv")
)

# ------------------------------------------------------------
# Quick summary
# ------------------------------------------------------------

fi_row <- coef_m[coef_m$term=="fi01_c",]

fmt <- function(x,d=3) formatC(x,format="f",digits=d)
fmtp <- function(x) {
  if (is.na(x)) return("NA")
  if (x<0.0001) return("<0.0001")
  formatC(x,format="f",digits=4)
}

summary_lines <- c(
  "FINAL STRICT 24-H LANDMARK MODEL",
  "================================",
  "",
  "Model:",
  "hospital mortality ~ FI-Lab + age + sex + GCS + invasive ventilation + vasopressor",
  "",
  paste0(
    "MIMIC: n=", nrow(m),
    ", deaths=", sum(m$death),
    ", AUC=", fmt(m_perf$AUC),
    ", Brier=", fmt(m_perf$Brier,5)
  ),
  paste0(
    "FI-Lab OR per +0.1 = ",
    fmt(fi_row$OR),
    " (", fmt(fi_row$CI_low), "-", fmt(fi_row$CI_high), ")",
    "; p=", fmtp(fi_row$p_value)
  ),
  "",
  paste0(
    "eICU fixed-coefficient validation: n=", nrow(e),
    ", deaths=", sum(e$death)
  ),
  paste0(
    "AUC=", fmt(e_perf$AUC),
    "; Brier=", fmt(e_perf$Brier,5)
  ),
  paste0(
    "Observed mortality=", fmt(100*e_perf$mortality,2), "%",
    "; mean predicted risk=", fmt(100*e_perf$mean_predicted_risk,2), "%"
  ),
  paste0(
    "Calibration intercept=", fmt(e_perf$calibration_intercept),
    "; slope=", fmt(e_perf$calibration_slope)
  ),
  "",
  "See 04_eICU_hospital_cluster_bootstrap_CI.csv for 95% CIs.",
  "This is the final strict replacement for the old CCI-containing landmark model."
)

writeLines(
  summary_lines,
  file.path(OUT_DIR, "08_QUICK_SUMMARY.txt")
)

# ------------------------------------------------------------
# Output manifest + session
# ------------------------------------------------------------

manifest <- data.frame(
  file=c(
    "00_sample_reproduction_check.csv",
    "01_MIMIC_final_model_coefficients.csv",
    "01A_FIXED_COEFFICIENTS_FOR_eICU.csv",
    "02_final_point_performance.csv",
    "03_calibration_curve_settings.csv",
    "04_eICU_hospital_cluster_bootstrap_CI.csv",
    "05_eICU_continuous_calibration_curve.csv",
    "06_eICU_predicted_risk_aggregate_summary.csv",
    "07_old_V5_vs_strict_24h_comparison.csv",
    "08_QUICK_SUMMARY.txt",
    "Fig4_STRICT_24H_eICU_calibration.png",
    "Fig4_STRICT_24H_eICU_calibration.tif",
    "sessionInfo.txt"
  ),
  purpose=c(
    "Hard check of final landmark sample sizes/deaths",
    "Final MIMIC development coefficients",
    "Exact coefficients applied unchanged to eICU",
    "MIMIC apparent and eICU external point performance",
    "Prespecified continuous-calibration smoother settings",
    "Hospital-cluster bootstrap CIs for external metrics",
    "Numeric continuous calibration curve + bootstrap band",
    "Aggregate eICU predicted-risk distribution; no patient-level data",
    "Change tracking against old V5 CCI-containing landmark model",
    "Concise final numerical summary",
    "Preview calibration figure",
    "600-dpi final calibration figure",
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


# ------------------------------------------------------------
# Single-file headline export bundle
# ------------------------------------------------------------

bundle_rows <- list()

bundle_rows[[1]] <- data.frame(
  section_order=1L,
  section="SAMPLE_CHECK",
  row_no=seq_len(nrow(sample_check)),
  payload_json=vapply(
    seq_len(nrow(sample_check)),
    function(i) jsonlite::toJSON(sample_check[i,,drop=FALSE], auto_unbox=TRUE),
    character(1)
  ),
  stringsAsFactors=FALSE
)

bundle_rows[[2]] <- data.frame(
  section_order=2L,
  section="MIMIC_COEFFICIENTS",
  row_no=seq_len(nrow(coef_m)),
  payload_json=vapply(
    seq_len(nrow(coef_m)),
    function(i) jsonlite::toJSON(coef_m[i,,drop=FALSE], auto_unbox=TRUE),
    character(1)
  ),
  stringsAsFactors=FALSE
)

bundle_rows[[3]] <- data.frame(
  section_order=3L,
  section="POINT_PERFORMANCE",
  row_no=seq_len(nrow(point_perf)),
  payload_json=vapply(
    seq_len(nrow(point_perf)),
    function(i) jsonlite::toJSON(point_perf[i,,drop=FALSE], auto_unbox=TRUE),
    character(1)
  ),
  stringsAsFactors=FALSE
)

bundle_rows[[4]] <- data.frame(
  section_order=4L,
  section="eICU_BOOTSTRAP_CI",
  row_no=seq_len(nrow(boot_ci)),
  payload_json=vapply(
    seq_len(nrow(boot_ci)),
    function(i) jsonlite::toJSON(boot_ci[i,,drop=FALSE], auto_unbox=TRUE),
    character(1)
  ),
  stringsAsFactors=FALSE
)

headline_bundle <- data.table::rbindlist(bundle_rows, fill=TRUE)

data.table::fwrite(
  headline_bundle,
  file.path(OUT_DIR, "00_SEND_ME_THIS_STRICT_24H_HEADLINE_BUNDLE.csv")
)

cat("\n============================================================\n")
cat("FINAL STRICT 24-H LANDMARK ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Output:\n", OUT_DIR, "\n\n")
cat("For headline verification, upload only:\n")
cat("  00_SEND_ME_THIS_STRICT_24H_HEADLINE_BUNDLE.csv\n")
cat("Keep the full output folder for final figure/S5 regeneration.\n")
cat("Priority files:\n")
cat("  00_sample_reproduction_check.csv\n")
cat("  01_MIMIC_final_model_coefficients.csv\n")
cat("  02_final_point_performance.csv\n")
cat("  04_eICU_hospital_cluster_bootstrap_CI.csv\n")
cat("  05_eICU_continuous_calibration_curve.csv\n")
cat("  07_old_V5_vs_strict_24h_comparison.csv\n")
cat("  08_QUICK_SUMMARY.txt\n")
cat("  Fig4_STRICT_24H_eICU_calibration.tif\n")
cat("============================================================\n")
