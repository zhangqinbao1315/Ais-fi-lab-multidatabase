# ============================================================
# RUN_02_FUNCTIONAL_FORM_FULL.R
# ============================================================
# Project: AIS multimorbidity + Core-18 FI-Lab
#
# Purpose
# -------
# Formally assess the linear-logit assumption for:
#   1) Core-18 FI-Lab
#   2) modified CCI (cci_chronic_burden_no_age)
#
# Databases
# ---------
# MIMIC-IV H94 primary complete-case cohort
# eICU-CRD eicu_50 primary complete-case cohort
#
# Main strategy
# -------------
# - Restricted cubic spline (RCS), 4 knots.
# - Knots are derived ONCE from the frozen MIMIC H94 distribution
#   without using outcomes, then applied unchanged to eICU.
# - Nonlinearity is tested by the nonlinear RCS terms.
# - MIMIC: likelihood-ratio test + model-based Wald test.
# - eICU: likelihood-ratio test + hospital-cluster robust Wald test.
# - Also tests whether the prespecified linear-by-linear CCI x FI-Lab
#   product term remains materially changed after allowing nonlinear
#   main effects.
#
# This script DOES NOT:
# - change the frozen cohorts;
# - change Core-18 thresholds;
# - search for outcome-optimized cutoffs;
# - change the primary hospital-mortality outcome.
# ============================================================

options(stringsAsFactors = FALSE)
options(width = 160)

# ------------------------------------------------------------
# Packages
# ------------------------------------------------------------

required_pkgs <- c("data.table", "sandwich")
missing_pkgs <- required_pkgs[
  !vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_pkgs)) {
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}
still_missing <- required_pkgs[
  !vapply(required_pkgs, requireNamespace, logical(1), quietly = TRUE)
]
if (length(still_missing)) {
  stop("Missing R packages: ", paste(still_missing, collapse = ", "))
}

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

script_dir <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  ctx <- try(rstudioapi::getActiveDocumentContext(), silent = TRUE)
  if (!inherits(ctx, "try-error") && nzchar(ctx$path)) {
    script_dir <- dirname(
      normalizePath(ctx$path, winslash = "/", mustWork = TRUE)
    )
  }
}

find_existing_file <- function(d, candidates) {
  p <- file.path(d, candidates)
  hit <- p[file.exists(p)]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[1], winslash = "/", mustWork = TRUE)
}

choose_data_dir <- function() {
  mimic_candidates <- c(
    "H94_primary_model_completecase.csv",
    "mimic_H94_primary_model_completecase.csv"
  )
  eicu_candidates <- c(
    "eicu_50_primary_model_completecase.csv",
    "eICU_50_primary_model_completecase.csv"
  )

  auto_dirs <- unique(c(
    script_dir,
    file.path(script_dir, "data"),
    dirname(script_dir)
  ))

  for (d in auto_dirs) {
    if (!dir.exists(d)) next
    mf <- find_existing_file(d, mimic_candidates)
    ef <- find_existing_file(d, eicu_candidates)
    if (!is.na(mf) && !is.na(ef)) {
      return(normalizePath(d, winslash="/", mustWork=TRUE))
    }
  }

  cat("\n请选择同时包含以下冻结 CSV 的文件夹：\n")
  cat("  - H94_primary_model_completecase.csv\n")
  cat("  - eicu_50_primary_model_completecase.csv\n\n")

  if (.Platform$OS.type == "windows") {
    d <- utils::choose.dir(
      default = script_dir,
      caption = "选择 H94 + eICU-50 数据文件夹"
    )
  } else {
    d <- readline("Data directory: ")
  }

  if (is.na(d) || !nzchar(d)) stop("No data directory selected.")
  normalizePath(d, winslash="/", mustWork=TRUE)
}

DATA_DIR <- choose_data_dir()

mimic_file <- find_existing_file(
  DATA_DIR,
  c("H94_primary_model_completecase.csv",
    "mimic_H94_primary_model_completecase.csv")
)
eicu_file <- find_existing_file(
  DATA_DIR,
  c("eicu_50_primary_model_completecase.csv",
    "eICU_50_primary_model_completecase.csv")
)

if (is.na(mimic_file)) stop("Cannot find H94 primary complete-case CSV.")
if (is.na(eicu_file)) stop("Cannot find eICU-50 primary complete-case CSV.")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
OUT_DIR <- file.path(
  script_dir,
  "results",
  paste0("FUNCTIONAL_FORM_", stamp)
)
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)

cat("\nMIMIC input:\n", mimic_file, "\n")
cat("\neICU input:\n", eicu_file, "\n")
cat("\nOutput directory:\n", OUT_DIR, "\n\n")

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

check_cols <- function(d, required, label) {
  missing <- setdiff(required, names(d))
  if (length(missing)) {
    stop(label, " missing columns: ", paste(missing, collapse=", "))
  }
}

# Restricted cubic spline basis:
# K knots -> x linear term + (K-2) nonlinear basis terms.
rcs_nonlinear_basis <- function(x, knots, prefix) {
  knots <- sort(as.numeric(knots))
  if (length(knots) < 3) stop("RCS requires at least 3 knots.")
  if (anyDuplicated(knots)) stop("RCS knots must be unique.")

  K <- length(knots)
  kKm1 <- knots[K-1]
  kK <- knots[K]
  denom <- (kK - knots[1])^2
  if (!is.finite(denom) || denom <= 0) stop("Invalid RCS knot range.")

  pcube <- function(z) pmax(z, 0)^3

  out <- data.frame(row_id__ = seq_along(x))
  for (j in seq_len(K-2)) {
    kj <- knots[j]
    h <- (
      pcube(x - kj)
      - ((kK - kj) / (kK - kKm1)) * pcube(x - kKm1)
      + ((kKm1 - kj) / (kK - kKm1)) * pcube(x - kK)
    ) / denom

    out[[paste0(prefix, "_nl", j)]] <- h
  }
  out$row_id__ <- NULL
  out
}

# 4-knot empirical percentile rule.
# Primary target: 5th, 35th, 65th, 95th percentiles.
# If a discrete exposure creates duplicated knots, alternate
# percentile sets are tried WITHOUT reference to the outcome.
choose_four_knots <- function(x) {
  x <- x[is.finite(x)]
  if (length(unique(x)) < 4) {
    stop("Exposure has fewer than 4 distinct values; 4-knot RCS impossible.")
  }

  prob_sets <- list(
    c(.05, .35, .65, .95),
    c(.05, .50, .75, .95),
    c(.05, .50, .80, .95),
    c(.10, .50, .80, .95),
    c(.05, .40, .75, .95)
  )

  for (pp in prob_sets) {
    kk <- as.numeric(
      stats::quantile(x, probs=pp, na.rm=TRUE, type=2, names=FALSE)
    )
    if (length(unique(kk)) == 4 && all(diff(kk) > 0)) {
      return(list(knots=kk, probs=pp, method="empirical_percentiles"))
    }
  }

  # Outcome-independent fallback for very discrete variables.
  ux <- sort(unique(x))
  idx <- unique(round(seq(1, length(ux), length.out=4)))
  if (length(idx) < 4) {
    idx <- unique(floor(seq(1, length(ux), length.out=4)))
  }
  kk <- ux[idx]
  if (length(kk) != 4 || any(diff(kk) <= 0)) {
    stop("Could not construct 4 unique outcome-independent knots.")
  }

  list(
    knots=as.numeric(kk),
    probs=rep(NA_real_, 4),
    method="equally_spaced_distinct_values_fallback"
  )
}

lrt_compare <- function(reduced, full) {
  ll0 <- as.numeric(logLik(reduced))
  ll1 <- as.numeric(logLik(full))
  df0 <- attr(logLik(reduced), "df")
  df1 <- attr(logLik(full), "df")
  chisq <- 2 * (ll1 - ll0)
  df <- df1 - df0
  p <- pchisq(chisq, df=df, lower.tail=FALSE)

  c(
    LRT_chisq=chisq,
    LRT_df=df,
    LRT_p=p
  )
}

safe_inverse <- function(M) {
  out <- try(solve(M), silent=TRUE)
  if (!inherits(out, "try-error")) return(out)

  ee <- eigen((M + t(M))/2, symmetric=TRUE)
  tol <- max(dim(M)) * max(abs(ee$values)) * .Machine$double.eps
  invvals <- ifelse(abs(ee$values) > tol, 1/ee$values, 0)
  ee$vectors %*% diag(invvals, nrow=length(invvals)) %*% t(ee$vectors)
}

wald_block <- function(fit, terms, V) {
  terms <- intersect(terms, names(coef(fit)))
  if (!length(terms)) {
    return(c(Wald_chisq=NA_real_, Wald_df=NA_real_, Wald_p=NA_real_))
  }

  b <- coef(fit)[terms]
  VV <- V[terms, terms, drop=FALSE]
  W <- as.numeric(t(b) %*% safe_inverse(VV) %*% b)
  df <- length(b)
  p <- pchisq(W, df=df, lower.tail=FALSE)

  c(
    Wald_chisq=W,
    Wald_df=df,
    Wald_p=p
  )
}

coef_one <- function(fit, term, V, label, covariance_type) {
  if (!(term %in% names(coef(fit)))) {
    return(data.frame(
      model=label, term=term, beta=NA_real_, SE=NA_real_,
      OR=NA_real_, CI_low=NA_real_, CI_high=NA_real_,
      p_value=NA_real_, covariance=covariance_type
    ))
  }

  b <- unname(coef(fit)[term])
  se <- sqrt(V[term, term])
  z <- b/se
  p <- 2*pnorm(abs(z), lower.tail=FALSE)

  data.frame(
    model=label,
    term=term,
    beta=b,
    SE=se,
    OR=exp(b),
    CI_low=exp(b - 1.96*se),
    CI_high=exp(b + 1.96*se),
    p_value=p,
    covariance=covariance_type
  )
}

model_fit_row <- function(fit, database, model_name) {
  data.frame(
    database=database,
    model=model_name,
    n=nobs(fit),
    deaths=sum(model.response(model.frame(fit)) == 1),
    coefficients=length(coef(fit)),
    logLik=as.numeric(logLik(fit)),
    AIC=AIC(fit),
    deviance=deviance(fit)
  )
}

make_curve <- function(fit, V, exposure, grid, ref, knots, database) {
  beta <- coef(fit)
  names_beta <- names(beta)

  if (exposure == "FI-Lab") {
    prefix <- "fi"
    linear_term <- "fi01"
  } else if (exposure == "modified CCI") {
    prefix <- "cci"
    linear_term <- "cci"
  } else {
    stop("Unknown exposure.")
  }

  b_grid <- rcs_nonlinear_basis(grid, knots, prefix)
  b_ref <- rcs_nonlinear_basis(rep(ref, length(grid)), knots, prefix)

  out <- vector("list", length(grid))

  for (i in seq_along(grid)) {
    contrast <- rep(0, length(beta))
    names(contrast) <- names_beta

    if (linear_term %in% names_beta) {
      contrast[linear_term] <- grid[i] - ref
    }

    nl_names <- names(b_grid)
    for (nm in nl_names) {
      if (nm %in% names_beta) {
        contrast[nm] <- b_grid[[nm]][i] - b_ref[[nm]][i]
      }
    }

    est <- sum(contrast * beta)
    se <- sqrt(as.numeric(t(contrast) %*% V %*% contrast))

    out[[i]] <- data.frame(
      database=database,
      exposure=exposure,
      x=grid[i],
      reference=ref,
      log_OR=est,
      SE=se,
      OR=exp(est),
      CI_low=exp(est - 1.96*se),
      CI_high=exp(est + 1.96*se)
    )
  }

  data.table::rbindlist(out)
}

save_curve_plot <- function(curve_dt, exposure, database, out_prefix) {
  x <- curve_dt$x
  y <- curve_dt$OR
  lo <- curve_dt$CI_low
  hi <- curve_dt$CI_high

  # Prevent visually extreme tails from making the plot unreadable.
  ymax <- max(hi[is.finite(hi)], na.rm=TRUE)
  if (!is.finite(ymax)) ymax <- 2
  ylim_top <- min(ymax * 1.05, 10)
  ylim_top <- max(ylim_top, 1.5)

  xlab <- if (exposure == "FI-Lab") {
    "Core-18 FI-Lab"
  } else {
    "Modified CCI"
  }

  title_txt <- paste0(database, ": ", xlab, " functional form")

  draw_plot <- function() {
    plot(
      x, y,
      type="l",
      lwd=2,
      xlab=xlab,
      ylab="Adjusted odds ratio",
      main=title_txt,
      ylim=c(0, ylim_top)
    )
    lines(x, lo, lty=2)
    lines(x, hi, lty=2)
    abline(h=1, lty=3)
  }

  png(
    filename=paste0(out_prefix, ".png"),
    width=2400, height=1800, res=300
  )
  draw_plot()
  dev.off()

  tiff(
    filename=paste0(out_prefix, ".tif"),
    width=7.5, height=5.5, units="in",
    res=600, compression="lzw"
  )
  draw_plot()
  dev.off()
}

# ------------------------------------------------------------
# Load frozen data
# ------------------------------------------------------------

m0 <- data.table::fread(mimic_file)
e0 <- data.table::fread(eicu_file)

need_m <- c(
  "hospital_expire_flag",
  "cci_chronic_burden_no_age",
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
  "cci_chronic_burden_no_age",
  "filab18_per_0_1",
  "age_numeric",
  "sex_female",
  "gcs",
  "invasive_ventilation_day1",
  "vasopressor_use_firstday"
)

check_cols(m0, need_m, "MIMIC H94")
check_cols(e0, need_e, "eICU-50")

# Harmonized analysis frames.
m <- data.table(
  death = as.integer(m0$hospital_expire_flag),
  fi01 = as.numeric(m0$filab18_per_0_1),
  cci = as.numeric(m0$cci_chronic_burden_no_age),
  age10 = (as.numeric(m0$age) - 65) / 10,
  female = as.integer(m0$female),
  gcs_c = as.numeric(m0$gcs_min) - 15,
  imv = as.integer(m0$any_invasive_vent_m6p24),
  vaso = as.integer(m0$any_vasopressor_m6p24),
  hospitalid = 1L
)

e <- data.table(
  death = as.integer(e0$hospital_mortality),
  fi01 = as.numeric(e0$filab18_per_0_1),
  cci = as.numeric(e0$cci_chronic_burden_no_age),
  age10 = (as.numeric(e0$age_numeric) - 65) / 10,
  female = as.integer(e0$sex_female),
  gcs_c = as.numeric(e0$gcs) - 15,
  imv = as.integer(e0$invasive_ventilation_day1),
  vaso = as.integer(e0$vasopressor_use_firstday),
  hospitalid = e0$hospitalid
)

analysis_vars <- c(
  "death","fi01","cci","age10","female","gcs_c","imv","vaso","hospitalid"
)

m <- m[complete.cases(m[, ..analysis_vars])]
e <- e[complete.cases(e[, ..analysis_vars])]

# ------------------------------------------------------------
# Frozen sample QC
# ------------------------------------------------------------

input_qc <- data.frame(
  database=c("MIMIC H94","eICU-50"),
  n=c(nrow(m), nrow(e)),
  deaths=c(sum(m$death), sum(e$death)),
  mortality=c(mean(m$death), mean(e$death)),
  FI_mean=c(mean(m$fi01)/10, mean(e$fi01)/10),
  FI_median=c(median(m$fi01)/10, median(e$fi01)/10),
  FI_min=c(min(m$fi01)/10, min(e$fi01)/10),
  FI_max=c(max(m$fi01)/10, max(e$fi01)/10),
  CCI_mean=c(mean(m$cci), mean(e$cci)),
  CCI_median=c(median(m$cci), median(e$cci)),
  CCI_min=c(min(m$cci), min(e$cci)),
  CCI_max=c(max(m$cci), max(e$cci)),
  hospitals=c(1, length(unique(e$hospitalid)))
)

data.table::fwrite(
  input_qc,
  file.path(OUT_DIR, "00_input_QC.csv")
)

expected_qc <- data.frame(
  database=c("MIMIC H94","eICU-50"),
  expected_n=c(1665,2015),
  expected_deaths=c(183,197),
  observed_n=c(nrow(m),nrow(e)),
  observed_deaths=c(sum(m$death),sum(e$death))
)
expected_qc$n_match <- expected_qc$expected_n == expected_qc$observed_n
expected_qc$deaths_match <- expected_qc$expected_deaths == expected_qc$observed_deaths

data.table::fwrite(
  expected_qc,
  file.path(OUT_DIR, "00A_frozen_sample_reproduction_check.csv")
)

if (!all(expected_qc$n_match) || !all(expected_qc$deaths_match)) {
  warning(
    "Frozen sample size/death counts do not match V5 expectations. ",
    "Do not interpret functional-form tests until file versions are checked."
  )
}

# ------------------------------------------------------------
# MIMIC-derived, outcome-independent knots
# ------------------------------------------------------------

fi_k <- choose_four_knots(m$fi01)
cci_k <- choose_four_knots(m$cci)

knots_out <- data.frame(
  exposure=rep(c("FI-Lab per 0.1","modified CCI"), each=4),
  knot_number=rep(1:4, 2),
  knot_value=c(fi_k$knots, cci_k$knots),
  knot_value_display=c(fi_k$knots/10, cci_k$knots),
  target_percentile=c(fi_k$probs, cci_k$probs),
  method=c(rep(fi_k$method,4), rep(cci_k$method,4)),
  derivation_database="MIMIC H94",
  applied_to="MIMIC H94 and eICU-50"
)

data.table::fwrite(
  knots_out,
  file.path(OUT_DIR, "01_RCS_knots.csv")
)

# ------------------------------------------------------------
# Add RCS nonlinear terms using identical MIMIC-derived knots
# ------------------------------------------------------------

add_basis <- function(d) {
  fi_b <- rcs_nonlinear_basis(d$fi01, fi_k$knots, "fi")
  cci_b <- rcs_nonlinear_basis(d$cci, cci_k$knots, "cci")
  cbind(d, fi_b, cci_b)
}

m2 <- add_basis(m)
e2 <- add_basis(e)

fi_nl_terms <- grep("^fi_nl", names(m2), value=TRUE)
cci_nl_terms <- grep("^cci_nl", names(m2), value=TRUE)
all_nl_terms <- c(fi_nl_terms, cci_nl_terms)

rhs_cov <- "age10 + female + gcs_c + imv + vaso"
rhs_fi_nl <- paste(fi_nl_terms, collapse=" + ")
rhs_cci_nl <- paste(cci_nl_terms, collapse=" + ")

f_linear <- as.formula(
  paste("death ~ fi01 + cci +", rhs_cov)
)

f_fi_flex <- as.formula(
  paste("death ~ fi01 +", rhs_fi_nl, "+ cci +", rhs_cov)
)

f_cci_flex <- as.formula(
  paste("death ~ fi01 + cci +", rhs_cci_nl, "+", rhs_cov)
)

f_joint_flex <- as.formula(
  paste(
    "death ~ fi01 +", rhs_fi_nl,
    "+ cci +", rhs_cci_nl,
    "+", rhs_cov
  )
)

f_linear_interaction <- as.formula(
  paste("death ~ fi01 * cci +", rhs_cov)
)

f_flex_interaction <- as.formula(
  paste(
    "death ~ fi01 +", rhs_fi_nl,
    "+ cci +", rhs_cci_nl,
    "+ fi01:cci +", rhs_cov
  )
)

fit_database <- function(d, database, cluster_robust=FALSE) {
  fits <- list(
    linear_additive = glm(f_linear, family=binomial(), data=d),
    FI_flexible = glm(f_fi_flex, family=binomial(), data=d),
    CCI_flexible = glm(f_cci_flex, family=binomial(), data=d),
    joint_flexible = glm(f_joint_flex, family=binomial(), data=d),
    linear_interaction = glm(f_linear_interaction, family=binomial(), data=d),
    flexible_main_plus_linear_interaction =
      glm(f_flex_interaction, family=binomial(), data=d)
  )

  vcovs <- lapply(fits, function(fit) {
    if (cluster_robust) {
      sandwich::vcovCL(
        fit,
        cluster=d$hospitalid,
        type="HC0"
      )
    } else {
      vcov(fit)
    }
  })

  names(vcovs) <- names(fits)
  list(fits=fits, vcovs=vcovs)
}

res_m <- fit_database(m2, "MIMIC H94", cluster_robust=FALSE)
res_e <- fit_database(e2, "eICU-50", cluster_robust=TRUE)

# ------------------------------------------------------------
# Functional-form tests
# ------------------------------------------------------------

functional_tests_one <- function(res, database, covariance_label) {
  fits <- res$fits
  Vs <- res$vcovs

  rows <- list()

  # FI-Lab nonlinear terms conditional on linear CCI.
  lrt <- lrt_compare(fits$linear_additive, fits$FI_flexible)
  wal <- wald_block(fits$FI_flexible, fi_nl_terms, Vs$FI_flexible)

  rows[[1]] <- data.frame(
    database=database,
    test="FI-Lab nonlinearity",
    reduced_model="linear_additive",
    full_model="FI_flexible",
    nonlinear_df=length(fi_nl_terms),
    LRT_chisq=lrt["LRT_chisq"],
    LRT_df=lrt["LRT_df"],
    LRT_p=lrt["LRT_p"],
    Wald_chisq=wal["Wald_chisq"],
    Wald_df=wal["Wald_df"],
    Wald_p=wal["Wald_p"],
    Wald_covariance=covariance_label
  )

  # CCI nonlinear terms conditional on linear FI-Lab.
  lrt <- lrt_compare(fits$linear_additive, fits$CCI_flexible)
  wal <- wald_block(fits$CCI_flexible, cci_nl_terms, Vs$CCI_flexible)

  rows[[2]] <- data.frame(
    database=database,
    test="Modified CCI nonlinearity",
    reduced_model="linear_additive",
    full_model="CCI_flexible",
    nonlinear_df=length(cci_nl_terms),
    LRT_chisq=lrt["LRT_chisq"],
    LRT_df=lrt["LRT_df"],
    LRT_p=lrt["LRT_p"],
    Wald_chisq=wal["Wald_chisq"],
    Wald_df=wal["Wald_df"],
    Wald_p=wal["Wald_p"],
    Wald_covariance=covariance_label
  )

  # Joint nonlinearity.
  lrt <- lrt_compare(fits$linear_additive, fits$joint_flexible)
  wal <- wald_block(fits$joint_flexible, all_nl_terms, Vs$joint_flexible)

  rows[[3]] <- data.frame(
    database=database,
    test="Joint FI-Lab + modified CCI nonlinearity",
    reduced_model="linear_additive",
    full_model="joint_flexible",
    nonlinear_df=length(all_nl_terms),
    LRT_chisq=lrt["LRT_chisq"],
    LRT_df=lrt["LRT_df"],
    LRT_p=lrt["LRT_p"],
    Wald_chisq=wal["Wald_chisq"],
    Wald_df=wal["Wald_df"],
    Wald_p=wal["Wald_p"],
    Wald_covariance=covariance_label
  )

  # FI block conditional on flexible CCI.
  wal <- wald_block(
    fits$joint_flexible,
    fi_nl_terms,
    Vs$joint_flexible
  )
  rows[[4]] <- data.frame(
    database=database,
    test="FI-Lab nonlinear block within jointly flexible model",
    reduced_model=NA_character_,
    full_model="joint_flexible",
    nonlinear_df=length(fi_nl_terms),
    LRT_chisq=NA_real_,
    LRT_df=NA_real_,
    LRT_p=NA_real_,
    Wald_chisq=wal["Wald_chisq"],
    Wald_df=wal["Wald_df"],
    Wald_p=wal["Wald_p"],
    Wald_covariance=covariance_label
  )

  # CCI block conditional on flexible FI.
  wal <- wald_block(
    fits$joint_flexible,
    cci_nl_terms,
    Vs$joint_flexible
  )
  rows[[5]] <- data.frame(
    database=database,
    test="Modified CCI nonlinear block within jointly flexible model",
    reduced_model=NA_character_,
    full_model="joint_flexible",
    nonlinear_df=length(cci_nl_terms),
    LRT_chisq=NA_real_,
    LRT_df=NA_real_,
    LRT_p=NA_real_,
    Wald_chisq=wal["Wald_chisq"],
    Wald_df=wal["Wald_df"],
    Wald_p=wal["Wald_p"],
    Wald_covariance=covariance_label
  )

  data.table::rbindlist(rows, fill=TRUE)
}

functional_tests <- data.table::rbindlist(
  list(
    functional_tests_one(
      res_m,
      "MIMIC H94",
      "model-based"
    ),
    functional_tests_one(
      res_e,
      "eICU-50",
      "hospital-cluster robust"
    )
  ),
  fill=TRUE
)

functional_tests[, primary_test := ifelse(
  database == "eICU-50",
  "hospital-cluster robust Wald",
  "likelihood-ratio test + model-based Wald"
)]

data.table::fwrite(
  functional_tests,
  file.path(OUT_DIR, "02_functional_form_tests.csv")
)

# ------------------------------------------------------------
# Interaction sensitivity after flexible main effects
# ------------------------------------------------------------

interaction_one <- function(res, database, covariance_label) {
  fits <- res$fits
  Vs <- res$vcovs

  linear_row <- coef_one(
    fits$linear_interaction,
    "fi01:cci",
    Vs$linear_interaction,
    "original_linear_main_effects_plus_interaction",
    covariance_label
  )

  flex_row <- coef_one(
    fits$flexible_main_plus_linear_interaction,
    "fi01:cci",
    Vs$flexible_main_plus_linear_interaction,
    "flexible_main_effects_plus_linear_interaction",
    covariance_label
  )

  # Conventional nested LRT for product term after flexible main effects.
  lrt <- lrt_compare(
    fits$joint_flexible,
    fits$flexible_main_plus_linear_interaction
  )

  linear_row$database <- database
  flex_row$database <- database

  linear_row$LRT_for_product_after_flexible_main_effects <- NA_real_
  flex_row$LRT_for_product_after_flexible_main_effects <- lrt["LRT_p"]

  data.table::rbindlist(list(linear_row, flex_row), fill=TRUE)
}

interaction_sensitivity <- data.table::rbindlist(
  list(
    interaction_one(
      res_m,
      "MIMIC H94",
      "model-based"
    ),
    interaction_one(
      res_e,
      "eICU-50",
      "hospital-cluster robust"
    )
  ),
  fill=TRUE
)

data.table::fwrite(
  interaction_sensitivity,
  file.path(OUT_DIR, "03_interaction_sensitivity_after_flexible_main_effects.csv")
)

# MIMIC V5 reproduction check for the original linear product term.
m_linear <- interaction_sensitivity[
  database=="MIMIC H94" &
  model=="original_linear_main_effects_plus_interaction"
]

interaction_qc <- data.frame(
  metric=c("interaction_OR","interaction_Wald_p"),
  expected=c(1.032, 0.2078),
  observed=c(m_linear$OR, m_linear$p_value)
)
interaction_qc$absolute_difference <- abs(
  interaction_qc$observed - interaction_qc$expected
)

data.table::fwrite(
  interaction_qc,
  file.path(OUT_DIR, "03A_MIMIC_interaction_reproduction_check.csv")
)

# ------------------------------------------------------------
# Model fit table
# ------------------------------------------------------------

fit_table <- data.table::rbindlist(
  c(
    lapply(names(res_m$fits), function(nm) {
      model_fit_row(res_m$fits[[nm]], "MIMIC H94", nm)
    }),
    lapply(names(res_e$fits), function(nm) {
      model_fit_row(res_e$fits[[nm]], "eICU-50", nm)
    })
  ),
  fill=TRUE
)

data.table::fwrite(
  fit_table,
  file.path(OUT_DIR, "04_model_fit_comparison.csv")
)

# ------------------------------------------------------------
# Adjusted spline curves
# Joint flexible additive model; no interaction.
# MIMIC model-based CI; eICU hospital-cluster robust CI.
# ------------------------------------------------------------

FI_REF <- 2.777777777777778   # FI = 0.2777778
CCI_REF <- 1

make_database_curves <- function(
  d, res, database, V_joint
) {
  fit <- res$fits$joint_flexible

  fi_lo <- as.numeric(quantile(d$fi01, .025, na.rm=TRUE))
  fi_hi <- as.numeric(quantile(d$fi01, .975, na.rm=TRUE))
  fi_grid <- seq(fi_lo, fi_hi, length.out=201)

  cci_lo <- max(0, as.numeric(quantile(d$cci, .025, na.rm=TRUE)))
  cci_hi <- as.numeric(quantile(d$cci, .975, na.rm=TRUE))
  cci_grid <- seq(cci_lo, cci_hi, length.out=201)

  fi_curve <- make_curve(
    fit=fit,
    V=V_joint,
    exposure="FI-Lab",
    grid=fi_grid,
    ref=FI_REF,
    knots=fi_k$knots,
    database=database
  )
  fi_curve[, x_display := x / 10]
  fi_curve[, reference_display := reference / 10]

  cci_curve <- make_curve(
    fit=fit,
    V=V_joint,
    exposure="modified CCI",
    grid=cci_grid,
    ref=CCI_REF,
    knots=cci_k$knots,
    database=database
  )
  cci_curve[, x_display := x]
  cci_curve[, reference_display := reference]

  list(FI=fi_curve, CCI=cci_curve)
}

curves_m <- make_database_curves(
  m2,
  res_m,
  "MIMIC H94",
  res_m$vcovs$joint_flexible
)
curves_e <- make_database_curves(
  e2,
  res_e,
  "eICU-50",
  res_e$vcovs$joint_flexible
)

curves_all <- data.table::rbindlist(
  list(curves_m$FI, curves_m$CCI, curves_e$FI, curves_e$CCI),
  fill=TRUE
)

data.table::fwrite(
  curves_all,
  file.path(OUT_DIR, "05_adjusted_RCS_curves.csv")
)

# Plotting uses display-scale x for FI.
plot_curve_transform <- function(curve, exposure, database, file_tag) {
  cc <- copy(curve)
  cc[, x := x_display]

  save_curve_plot(
    cc,
    exposure=exposure,
    database=database,
    out_prefix=file.path(
      OUT_DIR,
      paste0("FigS_", file_tag)
    )
  )
}

plot_curve_transform(
  curves_m$FI,
  "FI-Lab",
  "MIMIC H94",
  "MIMIC_FI_Lab_RCS"
)
plot_curve_transform(
  curves_m$CCI,
  "modified CCI",
  "MIMIC H94",
  "MIMIC_modified_CCI_RCS"
)
plot_curve_transform(
  curves_e$FI,
  "FI-Lab",
  "eICU-50",
  "eICU_FI_Lab_RCS"
)
plot_curve_transform(
  curves_e$CCI,
  "modified CCI",
  "eICU-50",
  "eICU_modified_CCI_RCS"
)

# ------------------------------------------------------------
# Coefficients for audit
# ------------------------------------------------------------

coef_audit <- function(res, database, cluster_robust=FALSE) {
  out <- list()
  for (nm in names(res$fits)) {
    fit <- res$fits[[nm]]
    V <- res$vcovs[[nm]]
    bb <- coef(fit)
    se <- sqrt(diag(V))

    z <- bb/se
    p <- 2*pnorm(abs(z), lower.tail=FALSE)

    out[[nm]] <- data.frame(
      database=database,
      model=nm,
      term=names(bb),
      beta=as.numeric(bb),
      SE=as.numeric(se),
      OR=exp(as.numeric(bb)),
      CI_low=exp(as.numeric(bb) - 1.96*as.numeric(se)),
      CI_high=exp(as.numeric(bb) + 1.96*as.numeric(se)),
      p_value=as.numeric(p),
      covariance=ifelse(
        cluster_robust,
        "hospital-cluster robust",
        "model-based"
      )
    )
  }
  data.table::rbindlist(out, fill=TRUE)
}

coef_all <- data.table::rbindlist(
  list(
    coef_audit(res_m, "MIMIC H94", FALSE),
    coef_audit(res_e, "eICU-50", TRUE)
  ),
  fill=TRUE
)

data.table::fwrite(
  coef_all,
  file.path(OUT_DIR, "06_all_model_coefficients_for_audit.csv")
)

# ------------------------------------------------------------
# Automated concise interpretation aid
# This is NOT manuscript text; it simply flags the statistical result.
# ------------------------------------------------------------

get_primary_p <- function(db, test_name) {
  z <- functional_tests[
    database==db & test==test_name
  ]
  if (!nrow(z)) return(NA_real_)

  if (db == "eICU-50") {
    z$Wald_p[1]
  } else {
    z$LRT_p[1]
  }
}

summary_lines <- c(
  "FUNCTIONAL-FORM ANALYSIS SUMMARY",
  "================================",
  "",
  paste0(
    "MIMIC FI-Lab nonlinearity p = ",
    format.pval(
      get_primary_p("MIMIC H94","FI-Lab nonlinearity"),
      digits=4, eps=1e-4
    )
  ),
  paste0(
    "MIMIC modified CCI nonlinearity p = ",
    format.pval(
      get_primary_p("MIMIC H94","Modified CCI nonlinearity"),
      digits=4, eps=1e-4
    )
  ),
  paste0(
    "eICU FI-Lab cluster-robust nonlinearity p = ",
    format.pval(
      get_primary_p("eICU-50","FI-Lab nonlinearity"),
      digits=4, eps=1e-4
    )
  ),
  paste0(
    "eICU modified CCI cluster-robust nonlinearity p = ",
    format.pval(
      get_primary_p("eICU-50","Modified CCI nonlinearity"),
      digits=4, eps=1e-4
    )
  ),
  "",
  "Interpretation must consider effect shape, confidence intervals,",
  "cross-database consistency, and model stability; do not use p-values alone.",
  "",
  "See 02_functional_form_tests.csv and 03_interaction_sensitivity_after_flexible_main_effects.csv."
)

writeLines(
  summary_lines,
  con=file.path(OUT_DIR, "07_QUICK_SUMMARY.txt")
)

capture.output(
  sessionInfo(),
  file=file.path(OUT_DIR, "sessionInfo.txt")
)

# ------------------------------------------------------------
# Output manifest
# ------------------------------------------------------------

manifest <- data.frame(
  file=c(
    "00_input_QC.csv",
    "00A_frozen_sample_reproduction_check.csv",
    "01_RCS_knots.csv",
    "02_functional_form_tests.csv",
    "03_interaction_sensitivity_after_flexible_main_effects.csv",
    "03A_MIMIC_interaction_reproduction_check.csv",
    "04_model_fit_comparison.csv",
    "05_adjusted_RCS_curves.csv",
    "06_all_model_coefficients_for_audit.csv",
    "07_QUICK_SUMMARY.txt",
    "FigS_MIMIC_FI_Lab_RCS.png/.tif",
    "FigS_MIMIC_modified_CCI_RCS.png/.tif",
    "FigS_eICU_FI_Lab_RCS.png/.tif",
    "FigS_eICU_modified_CCI_RCS.png/.tif",
    "sessionInfo.txt"
  ),
  purpose=c(
    "Frozen input counts and exposure summaries",
    "Verify n/deaths against V5 frozen cohorts",
    "Outcome-independent MIMIC-derived RCS knots applied to both databases",
    "Formal nonlinearity tests",
    "CCI x FI-Lab product-term sensitivity after flexible main effects",
    "Reproduce frozen MIMIC linear interaction result",
    "AIC/log-likelihood/deviance comparison",
    "Numeric values underlying RCS figures",
    "Full coefficient audit",
    "Quick statistical summary",
    "MIMIC FI-Lab adjusted RCS curve",
    "MIMIC modified CCI adjusted RCS curve",
    "eICU FI-Lab adjusted RCS curve",
    "eICU modified CCI adjusted RCS curve",
    "R environment"
  )
)

data.table::fwrite(
  manifest,
  file.path(OUT_DIR, "OUTPUT_MANIFEST.csv")
)

cat("\n============================================================\n")
cat("FUNCTIONAL-FORM ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Results:\n", OUT_DIR, "\n\n")
cat("Please upload the entire FUNCTIONAL_FORM_* result folder.\n")
cat("Priority files:\n")
cat("  00A_frozen_sample_reproduction_check.csv\n")
cat("  01_RCS_knots.csv\n")
cat("  02_functional_form_tests.csv\n")
cat("  03_interaction_sensitivity_after_flexible_main_effects.csv\n")
cat("  03A_MIMIC_interaction_reproduction_check.csv\n")
cat("  05_adjusted_RCS_curves.csv\n")
cat("  07_QUICK_SUMMARY.txt\n")
cat("============================================================\n")
