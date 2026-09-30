"""Territorial variables.

T1 (municipality of the program): general and critical care beds from REPS (cut-off 2022-11-05).
T1a = log(total beds per nursing examinee in the municipality) and T1b = log(critical care beds per 1,000 inhabitants).
Both are also computed at the department level for sensitivity.
T2 (municipality of the school where Saber 11 was taken): multidimensional poverty index 2018, PDET and rural share 2018.

Inputs: data/raw/territorial/* (scripts/06_download_territorial.py), data/processed/panel_enfermeria.parquet,
data/processed/modelo_enfermeria.parquet and the Saber 11 parquet files in data/interim.
Output: data/processed/modelo_enfermeria_territorial.parquet.
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
TER = ROOT / "data" / "raw" / "territorial"
SB11 = ROOT / "data" / "interim"
res = {}

# --- REPS: beds by municipality ---
r = pd.read_csv(TER / "reps_capacidad_instalada.csv", dtype=str)
r.columns = [c.strip() for c in r.columns]
r = r[r["nom grupo capacidad"].str.strip() == "CAMAS"].copy()
r["cod_mpio"] = r["Código sede"].str.zfill(10).str[:5]
r["n"] = pd.to_numeric(r["num cantidad capacidad instalada"], errors="coerce").fillna(0)
desc = r["nom descripcion capacidad"].str.strip()
GENERALES = {"Adultos", "Pediátrica", "Obstetricia", "TPR", "Atención del Parto"}
crit = desc.str.contains("Intensiv|Intermedi", case=False, regex=True)
r["tipo"] = np.where(desc.isin(GENERALES), "generales", np.where(crit, "criticas", "otras"))
camas = r.pivot_table(index="cod_mpio", columns="tipo", values="n", aggfunc="sum", fill_value=0)
camas = camas.reindex(columns=["generales", "criticas", "otras"], fill_value=0).reset_index()
res["camas_nacionales"] = {k: float(camas[k].sum()) for k in ["generales", "criticas", "otras"]}

# --- Population 2018 by municipality and area ---
pp = pd.read_excel(TER / "PPED-AreaMun-2018-2042_VP.xlsx", sheet_name="PobMunicipalxÁrea", header=None, skiprows=8)
pp = pp.iloc[:, :7]
pp.columns = ["DP", "DPNOM", "MPIO", "DPMP", "ANO", "AREA", "TOTAL"]
pp = pp[pd.to_numeric(pp["ANO"], errors="coerce") == 2018].copy()
pp["MPIO"] = pp["MPIO"].astype(float).astype(int).astype(str).str.zfill(5)
pob = pp.pivot_table(index="MPIO", columns="AREA", values="TOTAL", aggfunc="sum")
res["areas_poblacion"] = list(pob.columns)
tot_col = [c for c in pob.columns if str(c).strip().lower() == "total"][0]
rur_col = [c for c in pob.columns if "rural" in str(c).lower()][0]
pob = pd.DataFrame({"cod_mpio": pob.index, "pob2018": pob[tot_col].values, "prop_rural": (pob[rur_col] / pob[tot_col]).values})

# --- Multidimensional poverty index 2018 and PDET ---
ipm = pd.read_excel(TER / "anexo-censal-pobreza-municipal-2018.xlsx", sheet_name="2_IPM Mpio y Dpt", dtype={"ID": str})
ipm = ipm.rename(columns={"ID": "cod_mpio", "IPM Municipal": "ipm2018"})[["cod_mpio", "ipm2018"]]
ipm = ipm[ipm["cod_mpio"].str.len() == 5]
ipm["ipm2018"] = pd.to_numeric(ipm["ipm2018"], errors="coerce")
pdet = pd.read_csv(TER / "municipios_pdet.csv", dtype=str)
pdet_set = set(pdet["CodigoMunicipio"].str.zfill(5))
res["municipios_pdet"] = len(pdet_set)

# --- Nursing examinees by municipality of the program (denominator of T1a) ---
panel = pd.read_parquet(ROOT / "data" / "processed" / "panel_enfermeria.parquet")
panel["cod_prgm"] = panel["estu_prgm_codmunicipio"].astype(str).str.split(".").str[0].str.zfill(5)
exam = panel.groupby(["cod_prgm", "anio"]).size().groupby("cod_prgm").mean().rename("examinados_anio").reset_index()

mun = exam.merge(camas, left_on="cod_prgm", right_on="cod_mpio", how="left").drop(columns="cod_mpio")
mun = mun.merge(pob, left_on="cod_prgm", right_on="cod_mpio", how="left").drop(columns="cod_mpio")
for c in ["generales", "criticas"]:
    mun[c] = mun[c].fillna(0)
mun["t1a_log_camas_por_estudiante"] = np.log((mun["generales"] + mun["criticas"] + 1) / mun["examinados_anio"])
mun["t1b_log_criticas_por_1000"] = np.log(1000 * mun["criticas"] / mun["pob2018"] + 0.01)
# department level
mun["dpto"] = mun["cod_prgm"].str[:2]
dep = mun.groupby("dpto")[["generales", "criticas", "examinados_anio"]].sum()
dep_pob = pob.assign(dpto=pob["cod_mpio"].str[:2]).groupby("dpto")["pob2018"].sum()
dep["t1a_dep"] = np.log((dep["generales"] + dep["criticas"] + 1) / dep["examinados_anio"])
dep["t1b_dep"] = np.log(1000 * dep["criticas"] / dep_pob.reindex(dep.index) + 0.01)
mun = mun.merge(dep[["t1a_dep", "t1b_dep"]], left_on="dpto", right_index=True, how="left")
res["municipios_programa"] = int(len(mun))
res["municipios_programa_sin_camas"] = int(((mun["generales"] + mun["criticas"]) == 0).sum())

# --- Municipality of origin (school in Saber 11) ---
need = set(panel["estu_consecutivo_sb11"].dropna())
orig = []
for f in sorted(SB11.glob("saber11_20*.parquet")):
    s = pd.read_parquet(f, columns=["estu_consecutivo", "cole_cod_mcpio_ubicacion"])
    orig.append(s[s["estu_consecutivo"].isin(need)])
orig = pd.concat(orig).drop_duplicates("estu_consecutivo")
orig["cod_origen"] = orig["cole_cod_mcpio_ubicacion"].astype(str).str.split(".").str[0].str.zfill(5)
orig = orig.rename(columns={"estu_consecutivo": "estu_consecutivo_sb11"})[["estu_consecutivo_sb11", "cod_origen"]]

# --- Merge with the modeling data ---
mod = pd.read_parquet(ROOT / "data" / "processed" / "modelo_enfermeria.parquet")
key = panel[["estu_consecutivo", "cod_prgm", "estu_consecutivo_sb11"]]
mod = mod.merge(key, on="estu_consecutivo", how="left").merge(orig, on="estu_consecutivo_sb11", how="left")
mod = mod.merge(mun[["cod_prgm", "generales", "criticas", "examinados_anio", "t1a_log_camas_por_estudiante",
                     "t1b_log_criticas_por_1000", "t1a_dep", "t1b_dep"]], on="cod_prgm", how="left")
mod = mod.merge(ipm.rename(columns={"cod_mpio": "cod_origen", "ipm2018": "ipm_origen"}), on="cod_origen", how="left")
mod = mod.merge(pob[["cod_mpio", "prop_rural"]].rename(columns={"cod_mpio": "cod_origen", "prop_rural": "rural_origen"}),
                on="cod_origen", how="left")
mod["pdet_origen"] = mod["cod_origen"].isin(pdet_set).astype(int)
mod.loc[mod["cod_origen"].isna(), "pdet_origen"] = np.nan

ana = mod[mod["analitica"]]
res["faltantes_analitica_pct"] = {c: round(100 * ana[c].isna().mean(), 2) for c in
    ["cod_prgm", "t1a_log_camas_por_estudiante", "t1b_log_criticas_por_1000", "cod_origen", "ipm_origen", "rural_origen", "pdet_origen"]}
res["pct_origen_pdet"] = round(100 * ana["pdet_origen"].mean(), 1)
res["municipios_origen"] = int(ana["cod_origen"].nunique())
res["programas_con_t1"] = int(ana.dropna(subset=["t1a_log_camas_por_estudiante"])["programa"].nunique())
mod.drop(columns=["estu_consecutivo_sb11"]).to_parquet(ROOT / "data" / "processed" / "modelo_enfermeria_territorial.parquet", index=False)
(ROOT / "results" / "exploratory" / "territorial_resumen.json").write_text(json.dumps(res, indent=1, ensure_ascii=False, default=str), encoding="utf-8")
print(json.dumps(res, indent=1, ensure_ascii=False, default=str))
