# ============================================================
# 01_MIMIC_PRIMARY_ASSOCIATION_INCREMENTAL_FINAL.R
# ============================================================
# Final full-cohort primary MIMIC analysis:
# - multiplicative CCI x FI-Lab interaction (Wald + LRT)
# - standardized additive interaction
# - incremental prognostic information of FI-Lab
#
# Required:
#   H94_primary_model_completecase.csv
# ============================================================

options(stringsAsFactors=FALSE)
options(width=160)

required <- c("data.table","MASS","pROC")
missing <- required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if (length(missing)) {
  install.packages(missing,repos="https://cloud.r-project.org")
}
still <- required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)]
if (length(still)) stop("Missing R packages: ",paste(still,collapse=", "))

args <- commandArgs(trailingOnly=TRUE)
DATA_DIR <- if (length(args)>=1) args[1] else getwd()
OUT_DIR <- if (length(args)>=2) args[2] else file.path(getwd(),"results","01_MIMIC_PRIMARY")
dir.create(OUT_DIR,recursive=TRUE,showWarnings=FALSE)

input <- file.path(DATA_DIR,"H94_primary_model_completecase.csv")
if (!file.exists(input)) stop("Cannot find: ",input)

m <- data.table::fread(input)

need <- c(
  "hospital_expire_flag","cci_chronic_burden_no_age","filab18_per_0_1",
  "age","female","gcs_min","any_invasive_vent_m6p24","any_vasopressor_m6p24"
)
miss <- setdiff(need,names(m))
if (length(miss)) stop("Missing columns: ",paste(miss,collapse=", "))

CCI_CENTER <- 1
FI01_CENTER <- 2.777777777777778
AGE_CENTER <- 65
GCS_CENTER <- 15

m[, `:=`(
  death=as.integer(hospital_expire_flag),
  cci_c=as.numeric(cci_chronic_burden_no_age)-CCI_CENTER,
  fi01_c=as.numeric(filab18_per_0_1)-FI01_CENTER,
  age10_c=(as.numeric(age)-AGE_CENTER)/10,
  female2=as.integer(female),
  gcs_c=as.numeric(gcs_min)-GCS_CENTER,
  imv=as.integer(any_invasive_vent_m6p24),
  vaso=as.integer(any_vasopressor_m6p24)
)]

model_vars <- c("death","cci_c","fi01_c","age10_c","female2","gcs_c","imv","vaso")
m <- m[complete.cases(m[,..model_vars])]

if (nrow(m)!=1665 || sum(m$death)!=183) {
  stop("Frozen H94 benchmark failed: expected n=1665 and deaths=183.")
}

form_int <- death ~ cci_c*fi01_c + age10_c + female2 + gcs_c + imv + vaso
form_noint <- death ~ cci_c + fi01_c + age10_c + female2 + gcs_c + imv + vaso
form_base <- death ~ cci_c + age10_c + female2 + gcs_c + imv + vaso

fit_int <- glm(form_int,family=binomial(),data=m)
fit_noint <- glm(form_noint,family=binomial(),data=m)
fit_base <- glm(form_base,family=binomial(),data=m)

# Multiplicative interaction
lrt_int <- anova(fit_noint,fit_int,test="LRT")
b <- coef(fit_int)["cci_c:fi01_c"]
se <- sqrt(vcov(fit_int)["cci_c:fi01_c","cci_c:fi01_c"])

interaction_out <- data.frame(
  interaction_OR=exp(b),
  CI_low=exp(b-1.96*se),
  CI_high=exp(b+1.96*se),
  Wald_p=summary(fit_int)$coefficients["cci_c:fi01_c",4],
  LRT_chisq=lrt_int$Deviance[2],
  LRT_df=lrt_int$Df[2],
  LRT_p=lrt_int$`Pr(>Chi)`[2]
)
data.table::fwrite(interaction_out,file.path(OUT_DIR,"01_MIMIC_interaction_Wald_and_LRT.csv"))

# Full coefficient table
sm <- summary(fit_int)$coefficients
coef_out <- data.frame(
  term=rownames(sm),
  beta=sm[,1],
  SE=sm[,2],
  OR=exp(sm[,1]),
  CI_low=exp(sm[,1]-1.96*sm[,2]),
  CI_high=exp(sm[,1]+1.96*sm[,2]),
  p_value=sm[,4],
  row.names=NULL
)
data.table::fwrite(coef_out,file.path(OUT_DIR,"01A_MIMIC_full_interaction_coefficients.csv"))

# Standardized additive interaction:
# E[p(C+1,F+0.1)-p(C+1,F)-p(C,F+0.1)+p(C,F)]
mm_formula <- delete.response(terms(fit_int))
make_X <- function(d,dcci=0,dfi=0) {
  nd <- as.data.frame(d)
  nd$cci_c <- nd$cci_c+dcci
  nd$fi01_c <- nd$fi01_c+dfi
  model.matrix(mm_formula,nd)
}
X00 <- make_X(m,0,0)
X10 <- make_X(m,1,0)
X01 <- make_X(m,0,1)
X11 <- make_X(m,1,1)
meanrisk <- function(X,beta) mean(plogis(drop(X%*%beta)))
beta_hat <- coef(fit_int)
add_point <- meanrisk(X11,beta_hat)-meanrisk(X10,beta_hat)-meanrisk(X01,beta_hat)+meanrisk(X00,beta_hat)

set.seed(20260926L)
draws <- MASS::mvrnorm(5000,mu=coef(fit_int),Sigma=vcov(fit_int))
sim <- apply(draws,1,function(bb) {
  meanrisk(X11,bb)-meanrisk(X10,bb)-meanrisk(X01,bb)+meanrisk(X00,bb)
})
ci <- quantile(sim,c(.025,.975),na.rm=TRUE)

add_out <- data.frame(
  estimand="E[p(C+1,F+0.1)-p(C+1,F)-p(C,F+0.1)+p(C,F)]",
  percentage_points=100*add_point,
  CI_low_percentage_points=100*ci[1],
  CI_high_percentage_points=100*ci[2],
  simulation_draws=5000
)
data.table::fwrite(add_out,file.path(OUT_DIR,"02_MIMIC_additive_interaction.csv"))

# Incremental FI value
lrt_fi <- anova(fit_base,fit_noint,test="LRT")
p0 <- predict(fit_base,type="response")
p1 <- predict(fit_noint,type="response")
yy <- m$death
roc0 <- pROC::roc(yy,p0,quiet=TRUE)
roc1 <- pROC::roc(yy,p1,quiet=TRUE)
auc0 <- as.numeric(pROC::auc(roc0))
auc1 <- as.numeric(pROC::auc(roc1))
delong_p <- pROC::roc.test(roc0,roc1,paired=TRUE,method="delong")$p.value
brier0 <- mean((yy-p0)^2)
brier1 <- mean((yy-p1)^2)

set.seed(20260928L)
B <- 1000L
boot <- matrix(NA_real_,nrow=B,ncol=2,dimnames=list(NULL,c("delta_AUC","delta_Brier")))
for (i in seq_len(B)) {
  idx <- sample.int(nrow(m),nrow(m),replace=TRUE)
  yb <- yy[idx]
  if (length(unique(yb))>1) {
    boot[i,"delta_AUC"] <-
      as.numeric(pROC::auc(pROC::roc(yb,p1[idx],quiet=TRUE))) -
      as.numeric(pROC::auc(pROC::roc(yb,p0[idx],quiet=TRUE)))
    boot[i,"delta_Brier"] <- mean((yb-p1[idx])^2)-mean((yb-p0[idx])^2)
  }
}

inc_out <- data.frame(
  metric=c(
    "LR_chisq_add_FI","LR_p_add_FI",
    "AUC_base_without_FI","AUC_plus_FI","delta_AUC","DeLong_p",
    "Brier_base_without_FI","Brier_plus_FI","delta_Brier_plusFI_minus_base"
  ),
  estimate=c(
    lrt_fi$Deviance[2],lrt_fi$`Pr(>Chi)`[2],
    auc0,auc1,auc1-auc0,delong_p,
    brier0,brier1,brier1-brier0
  ),
  CI_low=c(
    NA,NA,NA,NA,
    quantile(boot[,"delta_AUC"],.025,na.rm=TRUE),
    NA,NA,NA,
    quantile(boot[,"delta_Brier"],.025,na.rm=TRUE)
  ),
  CI_high=c(
    NA,NA,NA,NA,
    quantile(boot[,"delta_AUC"],.975,na.rm=TRUE),
    NA,NA,NA,
    quantile(boot[,"delta_Brier"],.975,na.rm=TRUE)
  )
)
data.table::fwrite(inc_out,file.path(OUT_DIR,"03_MIMIC_incremental_FI_value.csv"))

capture.output(sessionInfo(),file=file.path(OUT_DIR,"sessionInfo.txt"))
cat("MIMIC primary association/incremental analysis complete.\n")
