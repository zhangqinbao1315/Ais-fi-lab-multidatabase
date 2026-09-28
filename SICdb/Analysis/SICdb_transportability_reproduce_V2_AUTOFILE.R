# ============================================================
# SICdb exploratory FI-Lab transportability — AUTHORITATIVE FINAL
# Firth penalized logistic regression using logistf
# ============================================================
#
# Reported manuscript results reproduced by this script:
#   FI-Lab only:
#     OR per +0.1 = 1.898
#     profile-likelihood 95% CI = 1.095–3.784
#     p ≈ 0.021
#
#   FI-Lab + age:
#     FI-Lab OR per +0.1 = 2.285
#     profile-likelihood 95% CI = 1.173–6.057
#     p ≈ 0.012
#
# SICdb is exploratory only. These models are not a third full
# external validation and do not use the partial chronic-domain
# proxy as a harmonized CCI.
#
# Required files in one folder:
#   sicdb_43_analysis_base_all.csv
#   sicdb_44_primary_FI_analysis_cohort.csv
#   sicdb_45_available_covariate_completecase.csv
#
# The authoritative archived environment used logistf 1.26.1.
# ============================================================

options(stringsAsFactors = FALSE)
options(width = 180)

required_files <- c(
  "sicdb_43_analysis_base_all.csv",
  "sicdb_44_primary_FI_analysis_cohort.csv",
  "sicdb_45_available_covariate_completecase.csv"
)

if (!requireNamespace("logistf", quietly = TRUE)) {
  stop(
    paste0(
      "Package 'logistf' is required. ",
      "The archived final environment used logistf 1.26.1. ",
      "Install it with install.packages('logistf') and rerun."
    )
  )
}

has_all_required_files <- function(folder) {
  if (is.null(folder) || length(folder) == 0 || is.na(folder) || !nzchar(folder)) {
    return(FALSE)
  }
  all(file.exists(file.path(folder, required_files)))
}

safe_normalize <- function(path) {
  tryCatch(
    normalizePath(path, winslash = "/", mustWork = TRUE),
    error = function(e) path
  )
}

resolve_data_dir <- function() {
  candidates <- character()

  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    active_path <- tryCatch(
      rstudioapi::getActiveDocumentContext()$path,
      error = function(e) ""
    )
    if (!is.null(active_path) && length(active_path) == 1 && nzchar(active_path)) {
      candidates <- c(candidates, dirname(active_path))
    }
  }

  candidates <- unique(c(candidates, getwd()))
  candidates <- candidates[nzchar(candidates)]

  for (folder in candidates) {
    if (has_all_required_files(folder)) return(safe_normalize(folder))
  }

  if (interactive()) {
    message("")
    message("Select any one of the 3 required SICdb CSV files.")
    picked <- tryCatch(file.choose(), error = function(e) "")
    if (nzchar(picked)) {
      folder <- dirname(picked)
      if (has_all_required_files(folder)) return(safe_normalize(folder))
    }
  }

  stop(
    paste0(
      "Could not locate all required SICdb CSV files. Put these in one folder:\n",
      paste0(" - ", required_files, collapse = "\n")
    )
  )
}

DATA_DIR <- resolve_data_dir()
OUT_DIR <- file.path(DATA_DIR, "SICdb_Firth_FINAL_results")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

all_dat <- read.csv(
  file.path(DATA_DIR, "sicdb_43_analysis_base_all.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
fi <- read.csv(
  file.path(DATA_DIR, "sicdb_44_primary_FI_analysis_cohort.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
cc <- read.csv(
  file.path(DATA_DIR, "sicdb_45_available_covariate_completecase.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

needed <- c("hospital_mortality", "filab18_per_0_1", "age")
missing_cols <- setdiff(needed, names(fi))
if (length(missing_cols)) {
  stop("FI-valid input is missing required columns: ", paste(missing_cols, collapse = ", "))
}

bench <- data.frame(
  metric = c(
    "analysis_base_n",
    "analysis_base_deaths",
    "FI_valid_n",
    "FI_valid_deaths",
    "available_completecase_n"
  ),
  expected = c(33, 9, 30, 8, 30),
  observed = c(
    nrow(all_dat),
    sum(all_dat$hospital_mortality, na.rm = TRUE),
    nrow(fi),
    sum(fi$hospital_mortality, na.rm = TRUE),
    nrow(cc)
  )
)
bench$pass <- bench$expected == bench$observed
write.csv(
  bench,
  file.path(OUT_DIR, "00_SICdb_frozen_benchmark.csv"),
  row.names = FALSE
)

if (!all(bench$pass)) {
  print(bench)
  stop("Frozen SICdb benchmark failed. Do not continue.")
}

if (anyNA(fi[, needed])) {
  stop("Unexpected missing values in the authoritative FI-valid Firth model variables.")
}

m1 <- logistf::logistf(
  hospital_mortality ~ filab18_per_0_1,
  data = fi,
  firth = TRUE,
  pl = TRUE
)

m2 <- logistf::logistf(
  hospital_mortality ~ filab18_per_0_1 + I((age - 65) / 10),
  data = fi,
  firth = TRUE,
  pl = TRUE
)

extract_logistf <- function(model, term, model_name) {
  if (!(term %in% names(model$coefficients))) {
    stop("Term not found in logistf model: ", term)
  }

  data.frame(
    model = model_name,
    term = term,
    beta = unname(model$coefficients[term]),
    OR = exp(unname(model$coefficients[term])),
    profile_CI_low = exp(unname(model$ci.lower[term])),
    profile_CI_high = exp(unname(model$ci.upper[term])),
    p_value = unname(model$prob[term]),
    CI_method = "Profile Likelihood",
    fitting_method = "Penalized ML",
    n = as.integer(model$n),
    stringsAsFactors = FALSE
  )
}

r1 <- extract_logistf(m1, "filab18_per_0_1", "FI-Lab only")
r2 <- extract_logistf(m2, "filab18_per_0_1", "FI-Lab + age")
results <- rbind(r1, r2)

write.csv(
  results,
  file.path(OUT_DIR, "01_SICdb_Firth_authoritative_results.csv"),
  row.names = FALSE
)

expected <- data.frame(
  model = c("FI-Lab only", "FI-Lab + age"),
  expected_OR = c(1.8979915281, 2.285),
  expected_low = c(1.0946026543, 1.173),
  expected_high = c(3.7837967184, 6.057),
  expected_p = c(0.021, 0.012)
)

check <- merge(results, expected, by = "model", all.x = TRUE, sort = FALSE)
check$OR_abs_diff <- abs(check$OR - check$expected_OR)
check$low_abs_diff <- abs(check$profile_CI_low - check$expected_low)
check$high_abs_diff <- abs(check$profile_CI_high - check$expected_high)
check$p_abs_diff <- abs(check$p_value - check$expected_p)

check$checkpoint_pass <- (
  check$OR_abs_diff < 0.02 &
  check$low_abs_diff < 0.03 &
  check$high_abs_diff < 0.08 &
  check$p_abs_diff < 0.01
)

write.csv(
  check,
  file.path(OUT_DIR, "02_SICdb_Firth_reproduction_check.csv"),
  row.names = FALSE
)

cat("============================================================\n")
cat("SICdb AUTHORITATIVE FIRTH ANALYSIS\n")
cat("============================================================\n")
print(results, row.names = FALSE)
cat("\nReproduction checkpoint:\n")
print(check[, c(
  "model", "OR", "profile_CI_low", "profile_CI_high", "p_value", "checkpoint_pass"
)], row.names = FALSE)

if (!all(check$checkpoint_pass)) {
  stop(
    "Firth result checkpoint did not reproduce the frozen manuscript result. ",
    "Do not replace the manuscript values; inspect data/package version first."
  )
}

capture.output(summary(m1), file = file.path(OUT_DIR, "03_FI_only_logistf_summary.txt"))
capture.output(summary(m2), file = file.path(OUT_DIR, "04_FI_plus_age_logistf_summary.txt"))
capture.output(sessionInfo(), file = file.path(OUT_DIR, "sessionInfo.txt"))

cat("\nPASS: frozen SICdb Firth results reproduced.\n")
cat("Results folder:\n  ", OUT_DIR, "\n")
