"""Comparison of included and excluded examinees and the sample flow.

Inputs: data/processed/modelo_enfermeria.parquet and data/processed/panel_enfermeria.parquet.
Outputs: results/exploratory/incluidos_excluidos.csv and results/exploratory/flujo_muestra.csv.
"""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
d = pd.read_parquet(ROOT / "data" / "processed" / "modelo_enfermeria.parquet")
p = pd.read_parquet(ROOT / "data" / "processed" / "panel_enfermeria.parquet", columns=["estu_consecutivo", "edad", "sb11_en_disco"])
d = d.merge(p, on="estu_consecutivo", how="left")
d["grupo"] = (d["analitica"] & d["edad_c"].notna()).map({True: "Incluidos", False: "Excluidos"})
rows = []
def pct(s): return round(100 * s.mean(), 1)
for g, x in d.groupby("grupo"):
    rows.append({"grupo": g, "n": len(x), "edad_mediana": x["edad"].median(), "mujeres_%": pct(x["mujer"] == 1),
                 "estrato_1_2_%": pct(x["estrato"].isin(["E1", "E2"])),
                 "trabaja_mas_20h_%": pct(x["horas_trabajo"].isin(["h21_30", "h_gt30"])),
                 "rural_%": pct(x["area"] == "Rural"), "oficial_%": pct(x["oficial"] == 1),
                 "caribe_%": pct(x["region"] == "Caribe"), "credito_%": pct(x["credito"] == 1), "beca_%": pct(x["beca"] == 1),
                 "cuidado_media": round(x["esp_cuidado"].mean(), 1), "cuidado_de": round(x["esp_cuidado"].std(), 1)})
t = pd.DataFrame(rows)
out = ROOT / "results" / "exploratory"; out.mkdir(parents=True, exist_ok=True)
t.to_csv(out / "incluidos_excluidos.csv", index=False)
flujo = {"examinados_con_cuidado": len(d), "en_archivo_de_enlace": int(d["enlazado_sb11"].sum()),
         "con_saber11_2011_2020": int((d["enlazado_sb11"] & d["sb11_en_disco"].fillna(False)).sum()),
         "brecha_3_o_mas": int(d["analitica"].sum()), "con_edad_completa": int((d["analitica"] & d["edad_c"].notna()).sum())}
pd.Series(flujo).to_csv(out / "flujo_muestra.csv", header=["n"])
print(t.T.to_string()); print(flujo)
