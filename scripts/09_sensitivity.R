# Sensitivity analyses and exploratory check of T2 (territory of origin) without Saber 11.
# Also: random slope of entry achievement by program and comparison of program effects between all examinees and the
# analytic sample (linkage bias).
# Input: data/processed/modelo_enfermeria_territorial.parquet. Outputs: results/models/*.csv
# Run from the repository root: Rscript scripts/09_sensitivity.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
dir.create("results/models", showWarnings = FALSE, recursive = TRUE)
set.seed(20260928)
d0 <- as.data.frame(read_parquet("data/processed/modelo_enfermeria_territorial.parquet"))
prep <- function(x) {
  for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "region", "programa", "institucion", "anio", "cod_origen"))
    x[[v]] <- factor(x[[v]])
  x$estrato <- relevel(x$estrato, "E1"); x$educ_madre <- relevel(x$educ_madre, "Primaria_o_menos")
  x$area <- relevel(x$area, "Cabecera"); x$horas_trabajo <- relevel(x$horas_trabajo, "h0")
  x$region <- relevel(x$region, "Centro-Oriente"); droplevels(x) }
d <- prep(subset(d0, analitica & !is.na(edad_c)))
d$y <- d$esp_cuidado

est <- "mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo + beca + credito"
ing <- "sb11_z_comp + sb11_escala_nueva + brecha_anios"
prg <- "oficial + universidad + region + log_tamano_c"
re <- "(1 | programa)"
f <- function(...) as.formula(paste("y ~ anio +", paste(c(...), collapse = " + ")))
vprog <- function(m) { v <- as.data.frame(VarCorr(m)); sum(v$vcov[v$grp %in% c("programa", "institucion", "programa:institucion")]) }
vres <- function(m) { v <- as.data.frame(VarCorr(m)); v$vcov[v$grp == "Residual"] }
blup <- function(m) { r <- ranef(m)$programa; setNames(r[, 1], rownames(r)) }
caribe <- function(m) { s <- summary(m)$coefficients; if ("regionCaribe" %in% rownames(s)) s["regionCaribe", 1] else NA }

main_M2 <- lmer(f(est, ing, re), data = d); ref <- blup(main_M2)
run <- function(name, x, re_term = re, esc = TRUE) {
  x <- droplevels(x)
  ing_t <- if (esc) ing else "sb11_z_comp + brecha_anios"
  m1 <- lmer(f(est, re_term), data = x); m2 <- lmer(f(est, ing_t, re_term), data = x)
  m3 <- lmer(f(est, ing_t, prg, re_term), data = x)
  b <- if ("programa" %in% names(ranef(m2))) blup(m2) else NULL
  common <- intersect(names(b), names(ref))
  data.frame(analisis = name, n = nobs(m2), programas = length(unique(x$programa)),
    icc_M2 = vprog(m2) / (vprog(m2) + vres(m2)), reduccion_M1_M2 = 1 - vprog(m2) / vprog(m1),
    rho_con_principal = if (length(common) > 5) cor(b[common], ref[common], method = "spearman") else NA,
    caribe_M3 = caribe(m3), ingreso_coef = summary(m2)$coefficients["sb11_z_comp", 1])
}
tamano <- table(d$programa)
out <- rbind(
  run("principal", d),
  run("solo escala nueva Saber 11", subset(d, sb11_escala_nueva == 1), esc = FALSE),
  run("brecha 4-8 anios", subset(d, brecha_anios >= 4 & brecha_anios <= 8)),
  run("sin 2021", subset(d, anio != "2021")),
  run("programas >= 30 estudiantes", subset(d, programa %in% names(tamano)[tamano >= 30])),
  run("institucion + programa", d, re_term = "(1 | institucion) + (1 | programa)"),
  run("solo 2018-2019 (cobertura casi completa)", subset(d, periodo == "2018_2019")),
  run("solo 2021-2024", subset(d, periodo == "2021_2024")))
# Outcome standardized within year
dz <- d; dz$y <- dz$cuidado_z; zr <- run("desenlace estandarizado por ano", dz); out <- rbind(out, zr)

# Random slope of entry achievement by program (exploratory)
m_rs <- lmer(f(est, ing, "(1 + sb11_z_comp | programa)"), data = d)
vc_rs <- as.data.frame(VarCorr(m_rs))
rs <- data.frame(componente = paste(vc_rs$grp, vc_rs$var1, vc_rs$var2), valor = vc_rs$vcov, sdcor = vc_rs$sdcor)
lr_rs <- anova(update(main_M2, REML = FALSE), update(m_rs, REML = FALSE))

# Linkage bias: M1 program effects in all examinees with nursing care versus the analytic sample
all_c <- prep(subset(d0, !is.na(esp_cuidado) & !is.na(edad_c))); all_c$y <- all_c$esp_cuidado
b_all <- blup(lmer(f(est, re), data = all_c)); b_ana <- blup(lmer(f(est, re), data = d))
cm <- intersect(names(b_all), names(b_ana))
enlace <- data.frame(rho_M1_todos_vs_analitica = cor(b_all[cm], b_ana[cm], method = "spearman"),
  n_todos = nrow(all_c), n_analitica = nrow(d))
tasas <- aggregate(analitica ~ region, data = transform(all_c, analitica = as.numeric(analitica)), FUN = mean)

# Exploratory: T2 without Saber 11, to check whether origin operates through entry achievement
dd <- d[complete.cases(d[, c("ipm_origen", "rural_origen")]), ]
dd$ipm_z <- as.numeric(scale(dd$ipm_origen)); dd$rural_z <- as.numeric(scale(dd$rural_origen))
t2_sin <- lmer(f(est, prg, "ipm_z + pdet_origen + rural_z + (1 | programa) + (1 | cod_origen)"), data = dd)
t2_con <- lmer(f(est, ing, prg, "ipm_z + pdet_origen + rural_z + (1 | programa) + (1 | cod_origen)"), data = dd)
pick <- function(m, k) { s <- summary(m)$coefficients[c("ipm_z", "pdet_origen", "rural_z"), 1:2]
  data.frame(modelo = k, termino = rownames(s), estimado = s[, 1], ee = s[, 2]) }
t2m <- rbind(pick(t2_sin, "sin Saber 11"), pick(t2_con, "con Saber 11"))

write.csv(out, "results/models/sensibilidad.csv", row.names = FALSE)
write.csv(rs, "results/models/pendiente_aleatoria_ingreso.csv", row.names = FALSE)
write.csv(enlace, "results/models/sesgo_enlace.csv", row.names = FALSE)
write.csv(tasas, "results/models/tasa_enlace_region.csv", row.names = FALSE)
write.csv(t2m, "results/models/t2_mediacion_exploratoria.csv", row.names = FALSE)
print(out, digits = 3); print(rs, digits = 3); print(lr_rs); print(enlace, digits = 3); print(tasas, digits = 3); print(t2m, digits = 3)
