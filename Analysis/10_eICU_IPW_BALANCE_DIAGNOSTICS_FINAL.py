#!/usr/bin/env python3
"""
10_eICU_IPW_BALANCE_DIAGNOSTICS_FINAL.py

Reproduces selection-model balance diagnostics for the expanded eICU
FI-Lab-validity IPW sensitivity. Requires:
  eicu_IPW_expanded_selection_input.csv

Usage:
  python 10_eICU_IPW_BALANCE_DIAGNOSTICS_FINAL.py <data_dir> <out_dir>

Outputs aggregate balance only; no patient-level data are written.
"""
from pathlib import Path
import sys
import numpy as np
import pandas as pd
import statsmodels.api as sm

DATA_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
OUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.cwd() / "results" / "eICU_IPW_balance"
OUT_DIR.mkdir(parents=True, exist_ok=True)

d0 = pd.read_csv(DATA_DIR / "eicu_IPW_expanded_selection_input.csv")
d0["FI_valid"] = d0["filab18"].notna().astype(int)

def mode01(x):
    x = x.dropna()
    vc = x.value_counts()
    m = vc.max()
    return sorted(vc[vc == m].index)[0]

def prep(d):
    d = d.copy()
    for v in ["age_numeric","cci_chronic_burden_no_age","gcs"]:
        d[v+"_missing"] = d[v].isna().astype(int)
        d[v+"_imp"] = d[v].fillna(d[v].median()).astype(float)
    d["age_numeric_sel"] = (d["age_numeric_imp"]-65)/10
    d["cci_chronic_burden_no_age_sel"] = d["cci_chronic_burden_no_age_imp"]-1
    d["gcs_sel"] = d["gcs_imp"]-15
    for v in ["sex_female","invasive_ventilation_day1","vasopressor_use_firstday"]:
        d[v+"_missing"] = d[v].isna().astype(int)
        d[v+"_sel"] = d[v].fillna(mode01(d[v])).astype(float)
    return d

def fit_prop(d):
    d = prep(d)
    core = ["age_numeric_sel","sex_female_sel","cci_chronic_burden_no_age_sel",
            "gcs_sel","invasive_ventilation_day1_sel","vasopressor_use_firstday_sel"]
    allmiss = ["age_numeric_missing","sex_female_missing","cci_chronic_burden_no_age_missing",
               "gcs_missing","invasive_ventilation_day1_missing","vasopressor_use_firstday_missing"]
    miss = [v for v in allmiss if d[v].nunique()>1]
    X = d[core+miss].copy()
    hd = pd.get_dummies(d["hospitalid"].astype("category"),prefix="hospital",drop_first=True,dtype=float)
    X = pd.concat([X,hd],axis=1)
    X = sm.add_constant(X,has_constant="add")
    fit = sm.GLM(d["FI_valid"],X,family=sm.families.Binomial()).fit(maxiter=200,tol=1e-8,disp=0)
    p = np.clip(fit.predict(X),0.005,0.995)
    num = d["FI_valid"].mean()
    d["sw"] = np.where(d["FI_valid"]==1,num/p,(1-num)/(1-p))
    v = d[d["FI_valid"]==1].copy()
    q = np.quantile(v["sw"],[.01,.99])
    v["sw_trim"] = np.clip(v["sw"],q[0],q[1])
    return d,v,core,miss

def wmean(x,w):
    x=np.asarray(x,float); w=np.asarray(w,float)
    ok=np.isfinite(x)&np.isfinite(w)
    return np.sum(w[ok]*x[ok])/np.sum(w[ok])

def wvar(x,w):
    x=np.asarray(x,float); w=np.asarray(w,float)
    ok=np.isfinite(x)&np.isfinite(w)
    x=x[ok]; w=w[ok]
    mu=np.sum(w*x)/np.sum(w)
    return np.sum(w*(x-mu)**2)/np.sum(w)

def smd(sample,target,w=None):
    sample=np.asarray(sample,float); target=np.asarray(target,float)
    if w is None:
        ms=np.nanmean(sample); vs=np.nanvar(sample,ddof=1)
    else:
        ms=wmean(sample,w); vs=wvar(sample,w)
    mt=np.nanmean(target); vt=np.nanvar(target,ddof=1)
    den=np.sqrt((vs+vt)/2)
    return 0.0 if (not np.isfinite(den) or den==0) else (ms-mt)/den

h = d0.groupby("hospitalid")["FI_valid"].agg(["sum","count"])
mixed = h[(h["sum"]>0)&(h["sum"]<h["count"])].index

labels = {
 "age_numeric_sel":"Age","sex_female_sel":"Female sex",
 "cci_chronic_burden_no_age_sel":"Modified CCI","gcs_sel":"GCS",
 "invasive_ventilation_day1_sel":"Invasive ventilation",
 "vasopressor_use_firstday_sel":"Vasopressor",
 "sex_female_missing":"Sex missing indicator","gcs_missing":"GCS missing indicator",
 "invasive_ventilation_day1_missing":"Ventilation missing indicator",
}

def analyze(target,pop):
    d,v,core,miss=fit_prop(target)
    detail=[]
    for x in core+miss:
        detail.append({
          "Population":pop,"Variable":labels.get(x,x),
          "Domain":"Core clinical covariate" if x in core else "Missingness indicator",
          "SMD_unweighted":smd(v[x],d[x]),
          "SMD_weighted_untrimmed":smd(v[x],d[x],v["sw"]),
          "SMD_weighted_1_99_trim":smd(v[x],d[x],v["sw_trim"])
        })
    detail=pd.DataFrame(detail)

    hrows=[]
    for hid in sorted(d["hospitalid"].unique()):
        t=(d["hospitalid"].values==hid).astype(float)
        s=(v["hospitalid"].values==hid).astype(float)
        hrows.append({
          "SMD_unweighted":smd(s,t),
          "SMD_weighted_untrimmed":smd(s,t,v["sw"]),
          "SMD_weighted_1_99_trim":smd(s,t,v["sw_trim"])
        })
    hb=pd.DataFrame(hrows)

    summ=[]
    for dom in ["Core clinical covariate","Missingness indicator"]:
        x=detail[detail["Domain"]==dom]
        summ.append({
          "Population":pop,"Domain":dom,
          "Max_abs_SMD_unweighted":x["SMD_unweighted"].abs().max(),
          "Max_abs_SMD_weighted_untrimmed":x["SMD_weighted_untrimmed"].abs().max(),
          "Max_abs_SMD_weighted_1_99_trim":x["SMD_weighted_1_99_trim"].abs().max()
        })
    summ.append({
      "Population":pop,"Domain":"Hospital indicator",
      "Max_abs_SMD_unweighted":hb["SMD_unweighted"].abs().max(),
      "Max_abs_SMD_weighted_untrimmed":hb["SMD_weighted_untrimmed"].abs().max(),
      "Max_abs_SMD_weighted_1_99_trim":hb["SMD_weighted_1_99_trim"].abs().max()
    })
    return detail,pd.DataFrame(summ)

a1,a2=analyze(d0,"All 149 hospitals")
b1,b2=analyze(d0[d0["hospitalid"].isin(mixed)].copy(),"92 overlap hospitals")
pd.concat([a1,b1],ignore_index=True).to_csv(OUT_DIR/"eICU_IPW_balance_details.csv",index=False)
pd.concat([a2,b2],ignore_index=True).to_csv(OUT_DIR/"eICU_IPW_balance_summary.csv",index=False)
