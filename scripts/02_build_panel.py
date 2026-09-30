"""Builds the student-level panel: nursing examinees in Saber Pro 2018-2024 (2020 excluded).

Joins, by student:
- Saber Pro generic modules (one .txt per year): student, program and institution characteristics and generic scores.
- Saber Pro specific modules (long format): Nursing care, Health promotion and disease prevention, Health care.
- Official Saber 11 -> Saber Pro linkage file.
- Saber 11 2011-1 to 2020-2 (parquet files from scripts/01_convert_saber11.py).

Output: data/processed/panel_enfermeria.parquet and a summary in results/exploratory/panel_resumen.json.
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[1]
SP_GEN = ROOT / "data" / "raw" / "saberpro_genericas"
SP_ESP = ROOT / "data" / "raw" / "saberpro_especificas"
CRUCE = ROOT / "data" / "raw" / "cruce" / "Cruce Examen Saber 11 - Examen Saber Pro.txt"
SB11 = ROOT / "data" / "interim"
OUT_DATA = ROOT / "data" / "processed"
OUT_RES = ROOT / "results" / "exploratory"
OUT_DATA.mkdir(parents=True, exist_ok=True)
OUT_RES.mkdir(parents=True, exist_ok=True)

YEARS = [2018, 2019, 2021, 2022, 2023, 2024]
GEN_COLS = [
    "periodo", "estu_consecutivo", "estu_genero", "estu_fechanacimiento", "estu_estadocivil",
    "estu_areareside", "estu_tieneetnia", "estu_horassemanatrabaja", "estu_pagomatriculabeca",
    "estu_pagomatriculacredito", "estu_pagomatriculapadres", "estu_pagomatriculapropio",
    "estu_valormatriculauniversidad", "estu_semestrecursa", "estu_inse_individual",
    "fami_estratovivienda", "fami_educacionmadre", "fami_educacionpadre", "fami_tieneinternet",
    "fami_tienecomputador", "estu_prgm_departamento", "estu_prgm_codmunicipio",
    "estu_snies_prgmacademico", "estu_prgm_academico", "inst_cod_institucion", "inst_nombre_institucion",
    "inst_origen", "inst_caracter_academico", "estu_metodo_prgm", "estu_nucleo_pregrado",
    "estu_nivel_prgm_academico", "mod_razona_cuantitat_punt", "mod_lectura_critica_punt",
    "mod_competen_ciudada_punt", "mod_comuni_escrita_punt", "mod_ingles_punt",
]
MODULES = {
    "CUIDADO DE ENFERMERÍA EN LOS ÁMBITOS CLÍNICO Y COMUNITARIO": "esp_cuidado",
    "PROMOCIÓN DE LA SALUD Y PREVENCIÓN DE LA ENFERMEDAD": "esp_promocion",
    "ATENCIÓN EN SALUD": "esp_atencion",
}

summary = {}

# 1. Generic modules: examinees in the nursing knowledge area
frames = []
for y in YEARS:
    f = SP_GEN / f"Examen_Saber_Pro_Genericas_{y}.txt"
    cols = pd.read_csv(f, sep=";", nrows=0).columns
    d = pd.read_csv(f, sep=";", usecols=[c for c in GEN_COLS if c in cols], dtype=str, encoding="utf-8")
    d = d[d["estu_nucleo_pregrado"].str.upper().str.contains("ENFERMER", na=False)].copy()
    d["anio"] = y
    frames.append(d)
gen = pd.concat(frames, ignore_index=True)
summary["genericas_enfermeria"] = int(len(gen))
summary["duplicados_consecutivo"] = int(gen["estu_consecutivo"].duplicated().sum())

# 2. Specific modules in wide format
esp = []
for y in YEARS:
    e = pd.read_csv(SP_ESP / f"Examen_Saber_Pro_Especificas_{y}.txt", sep=";", dtype=str, encoding="utf-8")
    e["modulo"] = e["result_nombreprueba"].str.strip().str.upper().map(MODULES)
    e = e.dropna(subset=["modulo"])
    e["result_puntaje"] = pd.to_numeric(e["result_puntaje"], errors="coerce")
    esp.append(e[["estu_consecutivo", "modulo", "result_puntaje"]])
esp = pd.concat(esp, ignore_index=True)
summary["especificas_duplicados_estudiante_modulo"] = int(esp.duplicated(["estu_consecutivo", "modulo"]).sum())
esp_w = esp.pivot_table(index="estu_consecutivo", columns="modulo", values="result_puntaje", aggfunc="first").reset_index()
panel = gen.merge(esp_w, on="estu_consecutivo", how="left")

# 3. Linkage with Saber 11 and entry scores
cruce = pd.read_csv(CRUCE, sep=";", dtype=str, encoding="utf-8")
summary["cruce_duplicados_sbpro"] = int(cruce["estu_consecutivo_sbpro"].duplicated().sum())
panel = panel.merge(cruce[["estu_consecutivo_sbpro", "estu_consecutivo_sb11", "periodo_sb11"]],
                    left_on="estu_consecutivo", right_on="estu_consecutivo_sbpro", how="left")
needed = set(panel["estu_consecutivo_sb11"].dropna().unique())

# Saber 11 changed its structure in 2014-2. Five components with comparable content are harmonized:
#   new scale (files with punt_global): critical reading, mathematics, natural sciences, social studies and
#   citizenship, English
#   previous scale: language, mathematics, mean of biology/chemistry/physics, mean of social sciences/philosophy, English
# Each component is standardized within its period using all examinees of the period (population scale).
# The main entry measure is the composite: mean of the five z scores, restandardized within the period.
OLD = {"lectura": ["punt_lenguaje"], "matematicas": ["punt_matematicas"],
       "ciencias": ["punt_biologia", "punt_quimica", "punt_fisica"],
       "sociales": ["punt_ciencias_sociales", "punt_filosofia"], "ingles": ["punt_ingles"]}
NEW = {"lectura": ["punt_lectura_critica"], "matematicas": ["punt_matematicas"],
       "ciencias": ["punt_c_naturales"], "sociales": ["punt_sociales_ciudadanas"], "ingles": ["punt_ingles"]}
COMP = list(NEW)
sb, escala = [], {}
for f in sorted(SB11.glob("saber11_20*.parquet")):
    names = pq.read_schema(f).names
    spec = NEW if "punt_global" in names else OLD
    cols = sorted({c for v in spec.values() for c in v})
    s = pd.read_parquet(f, columns=["periodo", "estu_consecutivo"] + cols)
    for c in cols:
        s[c] = pd.to_numeric(s[c], errors="coerce")
    for k, v in spec.items():
        s[k] = s[v].mean(axis=1, skipna=False)
    for k in COMP:  # z within the file (period), with the whole population
        s[f"sb11_z_{k}"] = (s[k] - s[k].mean()) / s[k].std()
    comp = s[[f"sb11_z_{k}" for k in COMP]].mean(axis=1, skipna=False)
    s["sb11_z_comp"] = (comp - comp.mean()) / comp.std()
    escala[f.stem] = "nueva" if spec is NEW else "anterior"
    s["sb11_escala_nueva"] = spec is NEW
    sb.append(s[s["estu_consecutivo"].isin(needed)][["estu_consecutivo", "periodo", "sb11_escala_nueva", "sb11_z_comp"] + [f"sb11_z_{k}" for k in COMP]])
sb = pd.concat(sb, ignore_index=True).drop_duplicates("estu_consecutivo")
summary["sb11_escala_por_archivo"] = escala
sb = sb.rename(columns={"estu_consecutivo": "estu_consecutivo_sb11", "periodo": "periodo_sb11_file"})
panel = panel.merge(sb, on="estu_consecutivo_sb11", how="left")

# 4. Derived variables
num = ["mod_razona_cuantitat_punt", "mod_lectura_critica_punt", "mod_competen_ciudada_punt",
       "mod_comuni_escrita_punt", "mod_ingles_punt", "estu_inse_individual"]
for c in num:
    panel[c] = pd.to_numeric(panel[c], errors="coerce")
panel["anio_sb11"] = pd.to_numeric(panel["periodo_sb11"].str[:4], errors="coerce")
panel["brecha_anios"] = panel["anio"] - panel["anio_sb11"]
nac = pd.to_datetime(panel["estu_fechanacimiento"], errors="coerce", dayfirst=True)
panel["edad"] = panel["anio"] - nac.dt.year
panel.loc[(panel["edad"] < 16) | (panel["edad"] > 70), "edad"] = np.nan
panel["oficial"] = panel["inst_origen"].str.upper().str.startswith("OFICIAL").astype("Int64")
panel["universidad"] = (panel["inst_caracter_academico"].str.upper() == "UNIVERSIDAD").astype("Int64")
panel["tiene_cuidado"] = panel["esp_cuidado"].notna()
panel["enlazado_sb11"] = panel["estu_consecutivo_sb11"].notna()
panel["sb11_en_disco"] = panel["sb11_z_comp"].notna()
panel = panel.drop(columns=["estu_consecutivo_sbpro", "estu_fechanacimiento"])
panel.to_parquet(OUT_DATA / "panel_enfermeria.parquet", index=False)

# 5. Construction summary
by = panel.groupby("anio").agg(
    examinados=("estu_consecutivo", "size"),
    con_cuidado=("tiene_cuidado", "sum"),
    enlazados=("enlazado_sb11", "sum"),
    con_sb11_en_disco=("sb11_en_disco", "sum"),
    analitica=("tiene_cuidado", lambda s: int((s & panel.loc[s.index, "sb11_en_disco"]).sum())),
    programas=("estu_snies_prgmacademico", "nunique"),
    instituciones=("inst_cod_institucion", "nunique"),
)
summary["por_anio"] = by.reset_index().to_dict(orient="records")
ana = panel[panel["tiene_cuidado"] & panel["sb11_en_disco"]]
summary["muestra_analitica"] = int(len(ana))
summary["programas_analitica"] = int(ana["estu_snies_prgmacademico"].nunique())
summary["instituciones_analitica"] = int(ana["inst_cod_institucion"].nunique())
summary["programas_por_institucion_max"] = int(ana.groupby("inst_cod_institucion")["estu_snies_prgmacademico"].nunique().max())
summary["brecha_anios_distribucion"] = ana["brecha_anios"].value_counts().sort_index().to_dict()
summary["faltantes_pct_analitica"] = {c: round(100 * ana[c].isna().mean(), 1) for c in
    ["estu_genero", "edad", "fami_estratovivienda", "fami_educacionmadre", "estu_horassemanatrabaja",
     "estu_inse_individual", "estu_areareside", "estu_tieneetnia", "esp_promocion", "esp_atencion",
     "mod_razona_cuantitat_punt", "mod_lectura_critica_punt", "sb11_z_lectura", "estu_prgm_departamento"]
    if c in ana}
(OUT_RES / "panel_resumen.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False, default=str), encoding="utf-8")
print(json.dumps(summary, indent=1, ensure_ascii=False, default=str))
