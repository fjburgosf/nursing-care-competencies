"""Prepares the modeling variables.

Input: data/processed/panel_enfermeria.parquet (scripts/02_build_panel.py).
Output: data/processed/modelo_enfermeria.parquet, with all nursing examinees who took the nursing care module and a
flag `analitica` for the analytic sample (Saber 11 result from 2011 to 2020 and at least three years between the two
examinations). Departments are grouped into the six regions of the National Planning Department (DNP).
"""
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
REGIONS = {
    "Caribe": ["ATLANTICO", "BOLIVAR", "CESAR", "CORDOBA", "LA GUAJIRA", "MAGDALENA", "SUCRE", "SAN ANDRES"],
    "Pacifico": ["CHOCO", "VALLE", "CAUCA", "NARIÑO"],
    "Centro-Oriente": ["BOGOTÁ", "BOYACA", "CUNDINAMARCA", "SANTANDER", "NORTE SANTANDER"],
    "Eje Cafetero-Antioquia": ["ANTIOQUIA", "CALDAS", "RISARALDA", "QUINDIO"],
    "Centro-Sur-Amazonia": ["TOLIMA", "HUILA", "CAQUETA", "PUTUMAYO", "AMAZONAS"],
    "Llanos-Orinoquia": ["META", "CASANARE", "ARAUCA", "VICHADA", "GUAINIA", "GUAVIARE", "VAUPES"],
}
reg = pd.DataFrame([(dep, r) for r, deps in REGIONS.items() for dep in deps], columns=["departamento", "region"])

p = pd.read_parquet(ROOT / "data" / "processed" / "panel_enfermeria.parquet")
p = p[p["tiene_cuidado"]].copy()

p["mujer"] = (p["estu_genero"] == "F").astype(int)
p["edad_c"] = p["edad"] - p["edad"].median()
p["edad_c2"] = p["edad_c"] ** 2

estr = p["fami_estratovivienda"].fillna("Faltante")
p["estrato"] = np.select(
    [estr == "Estrato 1", estr == "Estrato 2", estr == "Estrato 3", estr.isin(["Estrato 4", "Estrato 5", "Estrato 6"])],
    ["E1", "E2", "E3", "E4mas"], "SinEstrato_Faltante")

m = p["fami_educacionmadre"].fillna("Faltante")
p["educ_madre"] = np.select(
    [m.isin(["Ninguno", "Primaria incompleta", "Primaria completa"]),
     m.isin(["Secundaria (Bachillerato) incompleta", "Secundaria (Bachillerato) completa"]),
     m.isin(["Técnica o tecnológica incompleta", "Técnica o tecnológica completa"]),
     m.isin(["Educación profesional incompleta", "Educación profesional completa", "Postgrado"])],
    ["Primaria_o_menos", "Secundaria", "Tecnica", "Profesional_posgrado"], "Faltante_NoSabe")

p["internet"] = (p["fami_tieneinternet"] == "Si").astype(int)
a = p["estu_areareside"].fillna("Faltante")
p["area"] = np.select([a == "Cabecera Municipal", a == "Area Rural"], ["Cabecera", "Rural"], "Faltante")
h = p["estu_horassemanatrabaja"].fillna("Faltante")
p["horas_trabajo"] = h.replace({"0": "h0", "Menos de 10 horas": "h_lt10", "Entre 11 y 20 horas": "h11_20",
                                "Entre 21 y 30 horas": "h21_30", "Más de 30 horas": "h_gt30"})
p["beca"] = (p["estu_pagomatriculabeca"] == "Si").astype(int)
p["credito"] = (p["estu_pagomatriculacredito"] == "Si").astype(int)

p = p.merge(reg, left_on="estu_prgm_departamento", right_on="departamento", how="left")
if p["region"].isna().any():
    raise SystemExit(f"Departments without region: {p.loc[p['region'].isna(), 'estu_prgm_departamento'].unique()}")

p["programa"] = p["estu_snies_prgmacademico"].astype(str)
p["institucion"] = p["inst_cod_institucion"].astype(str)
tam = p.groupby(["programa", "anio"]).size().groupby("programa").mean()
p["log_tamano"] = np.log(p["programa"].map(tam))
p["log_tamano_c"] = p["log_tamano"] - p["log_tamano"].mean()

for c, new in [("mod_lectura_critica_punt", "lc_z"), ("mod_razona_cuantitat_punt", "rc_z")]:
    p[new] = p.groupby("anio")[c].transform(lambda s: (s - s.mean()) / s.std())
p["cuidado_z"] = p.groupby("anio")["esp_cuidado"].transform(lambda s: (s - s.mean()) / s.std())

p["analitica"] = p["sb11_en_disco"] & (p["brecha_anios"] >= 3)
p["periodo"] = np.where(p["anio"] <= 2019, "2018_2019", "2021_2024")

keep = ["estu_consecutivo", "anio", "periodo", "programa", "institucion", "region", "oficial", "universidad",
        "log_tamano_c", "mujer", "edad_c", "edad_c2", "estrato", "educ_madre", "internet", "area", "horas_trabajo",
        "beca", "credito", "sb11_z_comp", "sb11_escala_nueva", "brecha_anios", "esp_cuidado", "esp_promocion",
        "esp_atencion", "cuidado_z", "lc_z", "rc_z", "analitica", "enlazado_sb11"]
out = p[keep].copy()
out["sb11_escala_nueva"] = out["sb11_escala_nueva"].astype("float")
out.to_parquet(ROOT / "data" / "processed" / "modelo_enfermeria.parquet", index=False)

ana = out[out["analitica"]]
print("with nursing care:", len(out), "| analytic:", len(ana), "| programs:", ana["programa"].nunique())
print("missing in analytic sample:", ana[["edad_c", "sb11_z_comp", "esp_promocion", "esp_atencion"]].isna().sum().to_dict())
print(ana["region"].value_counts().to_dict())
