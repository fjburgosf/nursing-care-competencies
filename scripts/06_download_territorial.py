"""Downloads the public sources of the territorial variables.

- Special Registry of Health Service Providers (REPS), installed capacity (datos.gov.co s2ru-bqt6).
- Municipalities with Development Programs with a Territorial Approach, PDET (datos.gov.co idrk-ba8y).
- DIVIPOLA populated centers with municipality codes (datos.gov.co xaxy-8nri).
- Municipal multidimensional poverty index, 2018 census, and municipal population projections by area 2018-2042 (DANE).

Saves the files in data/raw/territorial/ and logs URL, date, size and SHA-256 in data/raw/territorial/DOWNLOAD_LOG.csv.
The DANE sites require a relaxed TLS configuration from Python on Windows.
Note: the REPS file is updated by its publisher. The analysis used the cut-off of November 5, 2022.
"""
import csv
import hashlib
import ssl
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "raw" / "territorial"
OUT.mkdir(parents=True, exist_ok=True)
CTX = ssl.create_default_context()
CTX.set_ciphers("DEFAULT@SECLEVEL=1")

FILES = {
    "reps_capacidad_instalada.csv": "https://www.datos.gov.co/api/views/s2ru-bqt6/rows.csv?accessType=DOWNLOAD",
    "municipios_pdet.csv": "https://www.datos.gov.co/api/views/idrk-ba8y/rows.csv?accessType=DOWNLOAD",
    "divipola_centros_poblados.csv": "https://www.datos.gov.co/api/views/xaxy-8nri/rows.csv?accessType=DOWNLOAD",
    "anexo-censal-pobreza-municipal-2018.xlsx": "https://www.dane.gov.co/files/investigaciones/condiciones_vida/pobreza/2018/informacion-censal/anexo-censal-pobreza-municipal-2018.xlsx",
    "PPED-AreaMun-2018-2042_VP.xlsx": "https://www.dane.gov.co/files/censo2018/proyecciones-de-poblacion/Municipal/PPED-AreaMun-2018-2042_VP.xlsx",
}

log = OUT / "DOWNLOAD_LOG.csv"
new = not log.exists()
with open(log, "a", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    if new:
        w.writerow(["fecha_utc", "archivo", "url", "bytes", "sha256"])
    for name, url in FILES.items():
        dest = OUT / name
        if dest.exists():
            print("ya existe:", name)
            continue
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(req, context=CTX, timeout=300).read()
        dest.write_bytes(data)
        w.writerow([datetime.now(timezone.utc).isoformat(timespec="seconds"), name, url, len(data), hashlib.sha256(data).hexdigest()])
        print("descargado:", name, len(data))
