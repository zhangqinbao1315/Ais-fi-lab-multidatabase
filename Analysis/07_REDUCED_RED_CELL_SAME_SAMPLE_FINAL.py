#!/usr/bin/env python3
"""
Reproduce the same-sample reduced red-cell-domain FI-Lab sensitivity reported in V5.

Inputs:
- H94_primary_model_completecase.csv
- 10a_MIMIC_Core18_FROZEN_ALIGNED.csv

The frozen H94 sample is held constant. Core17 removes RBC; Core16 removes RBC and
hematocrit. No new post-deletion computability threshold is imposed.
"""
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats

H94 = pd.read_csv("H94_primary_model_completecase.csv")
raw = pd.read_csv("10a_MIMIC_Core18_FROZEN_ALIGNED.csv")

def dval(x, cond):
    return np.where(pd.isna(x), np.nan, np.asarray(cond, dtype=float))

f=raw["female"]
D=pd.DataFrame(index=raw.index)
D["wbc"]=dval(raw.wbc,(raw.wbc<4)|(raw.wbc>10))
D["hemoglobin"]=dval(raw.hemoglobin,np.where(f.eq(1),(raw.hemoglobin<11.2)|(raw.hemoglobin>15.7),(raw.hemoglobin<13.7)|(raw.hemoglobin>17.5)))
D["hematocrit"]=dval(raw.hematocrit,np.where(f.eq(1),(raw.hematocrit<34)|(raw.hematocrit>45),(raw.hematocrit<40)|(raw.hematocrit>51)))
D["platelet"]=dval(raw.platelet,(raw.platelet<150)|(raw.platelet>400))
D["rbc"]=dval(raw.rbc,np.where(f.eq(1),(raw.rbc<3.9)|(raw.rbc>5.2),(raw.rbc<4.6)|(raw.rbc>6.1)))
D["mcv"]=dval(raw.mcv,(raw.mcv<82)|(raw.mcv>98))
D["sodium"]=dval(raw.sodium,(raw.sodium<135)|(raw.sodium>145))
D["potassium"]=dval(raw.potassium,(raw.potassium<3.5)|(raw.potassium>5.1))
D["chloride"]=dval(raw.chloride,(raw.chloride<96)|(raw.chloride>108))
D["bicarbonate"]=dval(raw.bicarbonate,(raw.bicarbonate<22)|(raw.bicarbonate>32))
D["bun"]=dval(raw.bun,(raw.bun<6)|(raw.bun>20))
D["creatinine"]=dval(raw.creatinine,np.where(f.eq(1),(raw.creatinine<.4)|(raw.creatinine>1.1),(raw.creatinine<.5)|(raw.creatinine>1.2)))
D["glucose"]=dval(raw.glucose,(raw.glucose<70)|(raw.glucose>100))
D["calcium"]=dval(raw.calcium,(raw.calcium<8.4)|(raw.calcium>10.3))
D["magnesium"]=dval(raw.magnesium,(raw.magnesium<1.6)|(raw.magnesium>2.6))
D["phosphate"]=dval(raw.phosphate,(raw.phosphate<2.7)|(raw.phosphate>4.5))
D["inr"]=dval(raw.inr,(raw.inr<.9)|(raw.inr>1.1))
D["aptt"]=dval(raw.aptt,(raw.aptt<25)|(raw.aptt>36.5))

scores=pd.DataFrame({"stay_id":raw.stay_id})
for name,items in {
    "fi17":[c for c in D.columns if c!="rbc"],
    "fi16":[c for c in D.columns if c not in ("rbc","hematocrit")]
}.items():
    ne=D[items].notna().sum(axis=1)
    nd=D[items].sum(axis=1,skipna=True)
    scores[name]=nd/ne.replace(0,np.nan)

dat=H94.merge(scores,on="stay_id",how="left",validate="one_to_one")

def run(fi,label):
    z=dat.copy()
    z["death"]=z.hospital_expire_flag
    z["cci_c"]=z.cci_chronic_burden_no_age-1
    z["fi01_c"]=z[fi]*10-2.777777777777778
    z["age10_c"]=(z.age-65)/10
    z["gcs_c"]=z.gcs_min-15
    z["female2"]=z.female
    z["imv"]=z.any_invasive_vent_m6p24
    z["vaso"]=z.any_vasopressor_m6p24
    f0=smf.glm("death ~ cci_c + fi01_c + age10_c + female2 + gcs_c + imv + vaso",data=z,family=sm.families.Binomial()).fit()
    f1=smf.glm("death ~ cci_c*fi01_c + age10_c + female2 + gcs_c + imv + vaso",data=z,family=sm.families.Binomial()).fit()
    def orci(fit,term):
        ci=fit.conf_int().loc[term]
        return np.exp(fit.params[term]),np.exp(ci.iloc[0]),np.exp(ci.iloc[1]),fit.pvalues[term]
    a=orci(f0,"fi01_c"); b=orci(f1,"cci_c:fi01_c")
    lr=2*(f1.llf-f0.llf)
    return [label,len(z),int(z.death.sum()),*a,*b,float(stats.chi2.sf(lr,1))]

rows=[
    run("fi17","Core17: Core18 minus RBC"),
    run("fi16","Core16: Core18 minus RBC and hematocrit")
]
pd.DataFrame(rows,columns=[
    "definition","n","deaths","FI_OR","FI_CI_low","FI_CI_high","FI_p",
    "interaction_OR","interaction_CI_low","interaction_CI_high","interaction_Wald_p","interaction_LRT_p"
]).to_csv("MIMIC_reduced_FI_same_sample.csv",index=False)
