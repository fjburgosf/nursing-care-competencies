# Territorial models: T1 clinical training capacity in the municipality of the program and T2 territory of origin.
# Input: data/processed/modelo_enfermeria_territorial.parquet (scripts/07_territorial_vars.py).
# Outputs: results/models/territorial_*.csv
# Run from the repository root: Rscript scripts/08_models_territorial.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
set.seed(20260928)
d <- as.data.frame(read_parquet("data/processed/modelo_enfermeria_territorial.parquet"))
d <- subset(d, analitica & !is.na(edad_c) & !is.na(esp_cuidado))
for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "region", "programa", "anio", "cod_origen"))
  d[[v]] <- factor(d[[v]])
d$estrato <- relevel(d$estrato, "E1"); d$educ_madre <- relevel(d$educ_madre, "Primaria_o_menos")
d$area <- relevel(d$area, "Cabecera"); d$horas_trabajo <- relevel(d$horas_trabajo, "h0")
d$region <- relevel(d$region, "Centro-Oriente"); d$y <- d$esp_cuidado

# Program indicators scaled in SD between programs (T1) and origin indicators in SD between students (T2)
prog <- d[!duplicated(d$programa), ]
zp <- function(v) (d[[v]] - mean(prog[[v]])) / sd(prog[[v]])
d$t1a <- zp("t1a_log_camas_por_estudiante"); d$t1b <- zp("t1b_log_criticas_por_1000")
d$t1a_dep <- zp("t1a_dep"); d$t1b_dep <- zp("t1b_dep")
d$ipm_z <- as.numeric(scale(d$ipm_origen)); d$rural_z <- as.numeric(scale(d$rural_origen))

base <- paste("y ~ anio + mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo +",
              "beca + credito + sb11_z_comp + sb11_escala_nueva + brecha_anios + oficial + universidad + region + log_tamano_c")
fm <- list(
  M3   = paste(base, "+ (1 | programa)"),
  T1a  = paste(base, "+ t1a + (1 | programa)"),
  T1b  = paste(base, "+ t1b + (1 | programa)"),
  T1a_dep = paste(base, "+ t1a_dep + (1 | programa)"),
  T1b_dep = paste(base, "+ t1b_dep + (1 | programa)"),
  M5   = paste(base, "+ ipm_z + pdet_origen + rural_z + (1 | programa) + (1 | cod_origen)"),
  M5_T1a = paste(base, "+ t1a + ipm_z + pdet_origen + rural_z + (1 | programa) + (1 | cod_origen)"))
dd <- d[complete.cases(d[, c("ipm_z", "rural_z")]), ]
fits <- lapply(fm, function(f) lmer(as.formula(f), data = dd, REML = TRUE))

get <- function(m, term) { s <- summary(m)$coefficients
  if (!term %in% rownames(s)) return(c(NA, NA)); s[term, 1:2] }
vprog <- function(m) { v <- as.data.frame(VarCorr(m)); v$vcov[v$grp == "programa"] }
vorig <- function(m) { v <- as.data.frame(VarCorr(m)); x <- v$vcov[v$grp == "cod_origen"]; if (length(x)) x else NA }
tab <- do.call(rbind, lapply(names(fits), function(k) { m <- fits[[k]]
  data.frame(modelo = k, n = nobs(m), var_programa = vprog(m), var_origen = vorig(m),
    caribe = get(m, "regionCaribe")[1], caribe_ee = get(m, "regionCaribe")[2]) }))
terms <- c("t1a", "t1b", "t1a_dep", "t1b_dep", "ipm_z", "pdet_origen", "rural_z")
co <- do.call(rbind, lapply(names(fits), function(k) do.call(rbind, lapply(terms, function(t) {
  g <- get(fits[[k]], t); if (is.na(g[1])) NULL else data.frame(modelo = k, termino = t, estimado = g[1], ee = g[2],
    p = 2 * pnorm(-abs(g[1] / g[2]))) }))))
# Holm correction across the four prespecified contrasts: T1a (model T1a) and poverty, PDET, rural (model M5)
pre <- rbind(co[co$modelo == "T1a" & co$termino == "t1a", ], co[co$modelo == "M5" & co$termino %in% c("ipm_z", "pdet_origen", "rural_z"), ])
pre$p_holm <- p.adjust(pre$p, "holm")
dir.create("results/models", showWarnings = FALSE)
write.csv(tab, "results/models/territorial_varianza_caribe.csv", row.names = FALSE)
write.csv(co, "results/models/territorial_coeficientes.csv", row.names = FALSE)
write.csv(pre, "results/models/territorial_predefinidos_holm.csv", row.names = FALSE)
print(tab, digits = 3); print(co, digits = 3); print(pre, digits = 3)
