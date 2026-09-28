options(stringsAsFactors=FALSE)
options(width=180)

required <- c("data.table","MASS")
missing_pkgs <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if (length(missing_pkgs)) install.packages(missing_pkgs, repos="https://cloud.r-project.org")
still <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if (length(still)) stop("Missing R packages: ", paste(still, collapse=", "))

args <- commandArgs(trailingOnly=TRUE)
DATA_DIR <- if (length(args)>=1) args[1] else getwd()
OUT_DIR <- if (length(args)>=2) args[2] else file.path(getwd(),"results","MIMIC_OASIS")
dir.create(OUT_DIR,recursive=TRUE,showWarnings=FALSE)

f <- file.path(DATA_DIR,"mimic_H94_OASIS_sensitivity_input.csv")
if (!file.exists(f)) stop("Missing: ",f)
m0 <- data.table::fread(f)

if (nrow(m0)!=1665 || sum(m0$hospital_expire_flag)!=183) stop("H94 benchmark failed.")
if (data.table::uniqueN(m0$stay_id)!=1665) stop("stay_id is not unique.")
if (sum(is.na(m0$oasis))!=0) stop("Unexpected OASIS missingness.")

m <- data.table::copy(m0)
m[, `:=`(
  death=as.integer(hospital_expire_flag),
  cci_c=as.numeric(cci_chronic_burden_no_age)-1,
  fi01_c=as.numeric(filab18_per_0_1)-2.777777777777778,
  female2=as.integer(female),
  oasis5_c=(as.numeric(oasis)-median(oasis))/5,
  vaso=as.integer(any_vasopressor_m6p24)
)]

full <- glm(death ~ cci_c*fi01_c + female2 + oasis5_c + vaso,
            family=binomial(),data=m)
red  <- glm(death ~ cci_c + fi01_c + female2 + oasis5_c + vaso,
            family=binomial(),data=m)
lrt <- anova(red,full,test="LRT")

sm <- summary(full)$coefficients
co <- data.frame(
  term=rownames(sm),
  beta=sm[,1],
  SE=sm[,2],
  OR=exp(sm[,1]),
  CI_low=exp(sm[,1]-1.96*sm[,2]),
  CI_high=exp(sm[,1]+1.96*sm[,2]),
  p_value=sm[,4],
  row.names=NULL
)
data.table::fwrite(co,file.path(OUT_DIR,"01_OASIS_coefficients.csv"))

fi <- co[co$term=="fi01_c",]
ix <- co[co$term=="cci_c:fi01_c",]

headline <- data.frame(
  n=nrow(m),deaths=sum(m$death),
  oasis_mean=mean(m$oasis),oasis_sd=sd(m$oasis),
  oasis_median=median(m$oasis),oasis_q1=quantile(m$oasis,.25),
  oasis_q3=quantile(m$oasis,.75),oasis_min=min(m$oasis),oasis_max=max(m$oasis),
  FI_OR=fi$OR,FI_CI_low=fi$CI_low,FI_CI_high=fi$CI_high,FI_p=fi$p_value,
  interaction_OR=ix$OR,interaction_CI_low=ix$CI_low,
  interaction_CI_high=ix$CI_high,interaction_Wald_p=ix$p_value,
  interaction_LRT_chisq=lrt$Deviance[2],
  interaction_LRT_p=lrt$`Pr(>Chi)`[2]
)
data.table::fwrite(headline,file.path(OUT_DIR,"02_HEADLINE_OASIS.csv"))

# additive interaction
mm_formula <- delete.response(terms(full))
makeX <- function(d,dc=0,df=0) {
  nd <- as.data.frame(d)
  nd$cci_c <- nd$cci_c + dc
  nd$fi01_c <- nd$fi01_c + df
  model.matrix(mm_formula,nd)
}
X00<-makeX(m,0,0); X10<-makeX(m,1,0); X01<-makeX(m,0,1); X11<-makeX(m,1,1)
meanrisk <- function(X,b) mean(plogis(drop(X %*% b)))
b <- coef(full)
point <- meanrisk(X11,b)-meanrisk(X10,b)-meanrisk(X01,b)+meanrisk(X00,b)

set.seed(20260927L)
draws <- MASS::mvrnorm(5000,mu=coef(full),Sigma=vcov(full))
sim <- apply(draws,1,function(bb)
  meanrisk(X11,bb)-meanrisk(X10,bb)-meanrisk(X01,bb)+meanrisk(X00,bb))
ci <- quantile(sim,c(.025,.975))

add <- data.frame(
  additive_interaction_pp=100*point,
  CI_low_pp=100*ci[1],
  CI_high_pp=100*ci[2],
  draws=5000
)
data.table::fwrite(add,file.path(OUT_DIR,"03_OASIS_additive_interaction.csv"))

capture.output(sessionInfo(),file=file.path(OUT_DIR,"sessionInfo.txt"))
cat("MIMIC OASIS sensitivity completed.\n")
