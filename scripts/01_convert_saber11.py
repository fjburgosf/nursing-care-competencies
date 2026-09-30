"""Converts the Saber 11 files downloaded from DataIcfes (.txt, one per period) to parquet.

Input: data/raw/saber11/*_PPPPP.txt, where PPPPP is the period (20111, 20112, ..., 20202).
Output: data/interim/saber11_PPPPP.parquet (same rows and columns, column names in lower case).
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw" / "saber11"
OUT = ROOT / "data" / "interim"
OUT.mkdir(parents=True, exist_ok=True)

files = sorted(RAW.glob("*.txt"))
if not files:
    raise SystemExit(f"No Saber 11 files found in {RAW}")
for f in files:
    period = f.stem.split("_")[-1]
    out = OUT / f"saber11_{period}.parquet"
    if out.exists():
        print("exists:", out.name)
        continue
    d = pd.read_csv(f, sep=";", encoding="latin-1", low_memory=False, dtype=str)
    d.columns = d.columns.str.strip().str.lower()
    d.to_parquet(out, index=False)
    print(f"{f.name}: {len(d):,} rows -> {out.name}")
