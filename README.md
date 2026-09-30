# Care competencies of nursing students: how much do programs matter?

Analysis code for the article *Care competencies of nursing students: how much do programs matter?* by Keidy Lucía
Gómez-Otero, Juan Guillermo Popayán-Hernández and Francisco Javier Burgos-Florez.

The study analyzes the three specific care modules of Saber Pro taken by students of Colombian nursing programs in
2018, 2019 and 2021 to 2024 (nursing care in clinical and community settings, health promotion and disease
prevention, and health care). Multilevel models with students nested in programs estimate how much of the variation
between programs remains after adjusting for student characteristics and entry achievement in Saber 11, whether
program differences are consistent across modules and stable over time, and whether they are associated with clinical
training capacity, accreditation and the territory of origin of students.

**No microdata are included in this repository.** The scripts run only if the user already has the ICFES files
described below.

## Requirements

### 1. ICFES microdata (DataIcfes)

The individual results are administered by the Colombian Institute for Educational Evaluation (ICFES) and are
available through the [DataIcfes](https://www.icfes.gov.co/web/guest/datos-abiertos) repository, which requires
registration and a data request. Having these files is a requirement to run the analysis:

| File | Years or periods | Folder |
|---|---|---|
| `Examen_Saber_Pro_Genericas_YYYY.txt` (Saber Pro, generic modules) | 2018, 2019, 2021, 2022, 2023, 2024 | `data/raw/saberpro_genericas/` |
| `Examen_Saber_Pro_Especificas_YYYY.txt` (Saber Pro, specific modules) | 2018, 2019, 2021, 2022, 2023, 2024 | `data/raw/saberpro_especificas/` |
| `Cruce Examen Saber 11 - Examen Saber Pro.txt` (official linkage file) | all | `data/raw/cruce/` |
| Saber 11 results, one `.txt` per period, with the period at the end of the name (for example `Examen_Saber_11_20111.txt`) | 2011-1 to 2020-2 | `data/raw/saber11/` |

The files are used as distributed by DataIcfes (semicolon separated). Specific module results are not published for
2020, so that year is not analyzed.

### 2. Accreditation status (public)

`data/raw/acreditacion/snies_programas.csv` holds the current status of each program in the public program
consultation of the National Higher Education Information System (SNIES,
[hecaa.mineducacion.gov.co/consultaspublicas/programas](https://hecaa.mineducacion.gov.co/consultaspublicas/programas)).
It has one row per program of the analytic sample and the columns:

| Column | Content |
|---|---|
| `codigo_snies` | SNIES code of the program (the same as `estu_snies_prgmacademico` in Saber Pro) |
| `institucion` | Institution name |
| `estado_programa` | Program status as shown by SNIES (`Activo` or `Inactivo`) |
| `reconocimiento_ministerio` | Recognition as shown by SNIES (`Acreditación de alta calidad` or `Registro calificado`) |

The article used the status consulted on September 29, 2026. This file is needed only for
`scripts/12_accreditation_model.R`.

### 3. Territorial data (public)

`scripts/06_download_territorial.py` downloads them automatically: installed capacity of health service providers
(REPS, datos.gov.co), municipalities with Development Programs with a Territorial Approach (PDET), multidimensional
poverty index from the 2018 census and municipal population projections (DANE). The REPS file is updated by its
publisher. The article used the cut-off of November 5, 2022, so a later download can give slightly different results
in the territorial models.

### 4. Software

- Python 3.12 with `pandas`, `numpy`, `pyarrow` and `openpyxl`:

  ```bash
  pip install pandas numpy pyarrow openpyxl
  ```

- R 4.6 with `lme4` and `arrow`:

  ```bash
  Rscript -e "install.packages(c('lme4', 'arrow'))"
  ```

The versions used were Python 3.12.10 (pandas 3.0.5, numpy 2.5.2, pyarrow 25.0.1, openpyxl 3.1.5) and R 4.6.1
(lme4 2.0.6, arrow 25.0.0).

## Folder structure

```
data/
  raw/
    saberpro_genericas/     Examen_Saber_Pro_Genericas_YYYY.txt
    saberpro_especificas/   Examen_Saber_Pro_Especificas_YYYY.txt
    cruce/                  Cruce Examen Saber 11 - Examen Saber Pro.txt
    saber11/                Saber 11 .txt files, 2011-1 to 2020-2
    acreditacion/           snies_programas.csv
    territorial/            created by scripts/06_download_territorial.py
  interim/                  created by scripts/01_convert_saber11.py
  processed/                analysis datasets created by the scripts
results/                    estimates written by the scripts (.csv and .json)
scripts/
```

## How to run

All commands are run from the root of the repository, in this order:

```bash
python scripts/01_convert_saber11.py
python scripts/02_build_panel.py
python scripts/03_prepare_model_data.py
Rscript scripts/04_models.R
Rscript scripts/05_period_effects.R
python scripts/06_download_territorial.py
python scripts/07_territorial_vars.py
Rscript scripts/08_models_territorial.R
Rscript scripts/09_sensitivity.R
Rscript scripts/10_additional_analyses.R
python scripts/11_included_excluded.py
Rscript scripts/12_accreditation_model.R
```

| Script | What it does |
|---|---|
| `01_convert_saber11.py` | Converts the Saber 11 files of each period to parquet. |
| `02_build_panel.py` | Selects nursing examinees in the Saber Pro generic files, adds the three specific care modules, links Saber 11 through the official linkage file and builds the entry achievement composite (five components standardized within period, harmonized across the 2014 change of the examination). |
| `03_prepare_model_data.py` | Codes student and program variables, assigns departments to the six regions of the National Planning Department and flags the analytic sample (Saber 11 from 2011 to 2020 and at least three years between the two examinations). |
| `04_models.R` | Fits the multilevel models M0 to M4 for the three modules, decomposes the variance between programs with bootstrap confidence intervals for the intraclass correlation, tests the program variance, estimates program effects and their correlations between modules and periods. |
| `05_period_effects.R` | Estimates program effects separately for 2018 to 2019 and 2021 to 2024. |
| `06_download_territorial.py` | Downloads the public territorial sources. |
| `07_territorial_vars.py` | Builds hospital bed indicators for the municipality of the program and poverty, PDET and rural indicators for the municipality of origin. |
| `08_models_territorial.R` | Adds the territorial indicators to the models, with Holm correction for the prespecified contrasts. |
| `09_sensitivity.R` | Sensitivity analyses (Saber 11 scale, time between examinations, years, program size, institution level, standardized outcome), random slope of entry achievement and linkage bias. |
| `10_additional_analyses.R` | Contextual effect of program mean entry achievement, program effects in the generic modules (discriminant validity), common sample of the three modules, program by period variance and model diagnostics. |
| `11_included_excluded.py` | Compares included and excluded examinees and counts the sample at each selection step. |
| `12_accreditation_model.R` | Adds current high-quality accreditation as a program covariate. |

The scripts write their estimates to `results/`. The bootstrap procedures use fixed seeds, so repeated runs with the
same data give the same results. `04_models.R` and `10_additional_analyses.R` take the longest because of the
parametric bootstrap and the leave-one-program-out refits.

## Data protection

Programs and institutions are identified only by their SNIES and ICFES codes. The ICFES microdata and every dataset
derived from them in `data/interim/` and `data/processed/` must not be redistributed and must be used under the terms
of DataIcfes.
