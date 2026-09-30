# Additional sensitivity and exploratory analyses of the main model (nursing care).
#   1. Contextual effect: mean Saber 11 of the program (type A versus type B effects, Raudenbush and Willms 1995).
#   2. Discriminant validity: program effects in generic modules not specific to care.
#   3. Common sample of the three specific modules.
#   4. Program x period random effect.
#   5. Program sizes and diagnostics of the main model.
# Inputs: data/processed/modelo_enfermeria.parquet and data/processed/panel_enfermeria.parquet.
# Outputs: results/models/additional/*.csv
# Run from the repository root: Rscript scripts/10_additional_analyses.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
set.seed(20260929)
out <- "results/models/additional"; dir.create(out, showWarnings = FALSE, recursive = TRUE)

d0 <- as.data.frame(read_parquet("data/processed/modelo_enfermeria.parquet"))
d <- subset(d0, analitica & !is.na(edad_c))
pan <- as.data.frame(read_parquet("data/processed/panel_enfermeria.parquet",
  col_select = c("estu_consecutivo", "mod_ingles_punt", "mod_competen_ciudada_punt", "mod_comuni_escrita_punt")))
d <- merge(d, pan, by = "estu_consecutivo", all.x = TRUE)
zyear <- function(v) ave(v, d$anio, FUN = function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE))
d$ing_z <- zyear(d$mod_ingles_punt); d$ciu_z <- zyear(d$mod_competen_ciudada_punt); d$esc_z <- zyear(d$mod_comuni_escrita_punt)
for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "region", "programa", "institucion", "anio", "periodo"))
  d[[v]] <- factor(d[[v]])
d$estrato <- relevel(d$estrato, "E1"); d$educ_madre <- relevel(d$educ_madre, "Primaria_o_menos")
d$area <- relevel(d$area, "Cabecera"); d$horas_trabajo <- relevel(d$horas_trabajo, "h0")
d$region <- relevel(d$region, "Centro-Oriente")
d$sb11_media_prog <- ave(d$sb11_z_comp, d$programa)          # mean entry achievement of the program in the analytic sample
d$sb11_media_prog <- d$sb11_media_prog - mean(d$sb11_media_prog)

f_est <- "mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo + beca + credito"
f_ing <- "sb11_z_comp + sb11_escala_nueva + brecha_anios"
f_prog <- "oficial + universidad + region + log_tamano_c"
F <- function(...) as.formula(paste("y ~ anio +", paste(c(...), collapse = " + "), "+ (1 | programa)"))
vc <- function(m) { v <- as.data.frame(VarCorr(m)); c(prog = v$vcov[v$grp == "programa"], res = v$vcov[v$grp == "Residual"]) }
blup <- function(m) { r <- ranef(m)$programa; setNames(r[, 1], rownames(r)) }
sp_boot <- function(x, y, B = 2000) {
  k <- intersect(names(x), names(y)); x <- x[k]; y <- y[k]
  bs <- replicate(B, { i <- sample(seq_along(x), replace = TRUE); cor(x[i], y[i], method = "spearman") })
  c(rho = cor(x, y, method = "spearman"), li = unname(quantile(bs, .025)), ls = unname(quantile(bs, .975)), n = length(x))
}
fit <- function(outcome, form, dat = d) { dat$y <- dat[[outcome]]; lmer(form, data = dat[!is.na(dat$y), ], REML = TRUE) }

# 1. Contextual effect
m1 <- fit("esp_cuidado", F(f_est)); m2 <- fit("esp_cuidado", F(f_est, f_ing)); m3 <- fit("esp_cuidado", F(f_est, f_ing, f_prog))
m2c <- fit("esp_cuidado", F(f_est, f_ing, "sb11_media_prog")); m3c <- fit("esp_cuidado", F(f_est, f_ing, f_prog, "sb11_media_prog"))
cx <- function(m, k) { s <- summary(m)$coefficients; x <- vc(m)
  data.frame(modelo = k, tau2 = x["prog"], sigma2 = x["res"], icc = x["prog"] / sum(x),
             reduccion_tau2_vs_M1 = 1 - x["prog"] / vc(m1)["prog"],
             contextual = if ("sb11_media_prog" %in% rownames(s)) s["sb11_media_prog", 1] else NA,
             contextual_ee = if ("sb11_media_prog" %in% rownames(s)) s["sb11_media_prog", 2] else NA,
             caribe = if ("regionCaribe" %in% rownames(s)) s["regionCaribe", 1] else NA,
             caribe_ee = if ("regionCaribe" %in% rownames(s)) s["regionCaribe", 2] else NA,
             individual_sb11 = s["sb11_z_comp", 1]) }
ctx <- rbind(cx(m2, "M2"), cx(m2c, "M2 + media del programa"), cx(m3, "M3"), cx(m3c, "M3 + media del programa"))
ctx$rho_efectos_vs_M2 <- c(1, cor(blup(m2), blup(m2c)[names(blup(m2))], method = "spearman"), NA, NA)
write.csv(ctx, file.path(out, "efecto_contextual.csv"), row.names = FALSE)

# 2. Discriminant validity: program effects (M2 specification) in each module
mods <- c(cuidado = "esp_cuidado", promocion = "esp_promocion", atencion = "esp_atencion", lectura = "lc_z",
          razonamiento = "rc_z", ingles = "ing_z", ciudadanas = "ciu_z", escritura = "esc_z")
eff <- lapply(mods, function(o) { m <- fit(o, F(f_est, f_ing)); list(b = blup(m), icc = vc(m)["prog"] / sum(vc(m))) })
disc <- do.call(rbind, lapply(names(mods)[-1], function(k) data.frame(modulo = k, icc_M2 = unname(eff[[k]]$icc),
  t(sp_boot(eff$cuidado$b, eff[[k]]$b)))))
write.csv(disc, file.path(out, "validez_discriminante.csv"), row.names = FALSE)

# 3. Common sample of the three specific modules
dc <- d[complete.cases(d[, c("esp_cuidado", "esp_promocion", "esp_atencion")]), ]
com <- do.call(rbind, lapply(c(cuidado = "esp_cuidado", promocion = "esp_promocion", atencion = "esp_atencion"), function(o) {
  a <- fit(o, F(f_est), dc); b <- fit(o, F(f_est, f_ing), dc)
  data.frame(modulo = o, n = nobs(b), programas = ngrps(b)[["programa"]], icc_M1 = vc(a)["prog"] / sum(vc(a)),
             icc_M2 = vc(b)["prog"] / sum(vc(b)), reduccion_tau2 = 1 - vc(b)["prog"] / vc(a)["prog"]) }))
bc <- lapply(c("esp_cuidado", "esp_promocion", "esp_atencion"), function(o) blup(fit(o, F(f_est, f_ing), dc)))
com_cor <- rbind(cuidado_promocion = sp_boot(bc[[1]], bc[[2]]), cuidado_atencion = sp_boot(bc[[1]], bc[[3]]))
write.csv(com, file.path(out, "muestra_comun_icc.csv"), row.names = FALSE)
write.csv(com_cor, file.path(out, "muestra_comun_correlaciones.csv"))
cob <- data.frame(modulo = c("cuidado", "promocion", "atencion"),
  estudiantes = sapply(c("esp_cuidado", "esp_promocion", "esp_atencion"), function(v) sum(!is.na(d[[v]]))),
  programas = sapply(c("esp_cuidado", "esp_promocion", "esp_atencion"), function(v) length(unique(d$programa[!is.na(d[[v]])]))),
  estudiantes_tres_modulos = nrow(dc))
write.csv(cob, file.path(out, "cobertura_modulos.csv"), row.names = FALSE)

# 4. Program x period
dd <- d; dd$y <- dd$esp_cuidado
mpp <- lmer(update(F(f_est, f_ing), . ~ . + (1 | programa:periodo)), data = dd, REML = TRUE)
v <- as.data.frame(VarCorr(mpp))
pp <- data.frame(tau2_programa = v$vcov[v$grp == "programa"], var_programa_periodo = v$vcov[v$grp == "programa:periodo"],
                 sigma2 = v$vcov[v$grp == "Residual"], tau2_M2 = vc(m2)["prog"])
pp$icc_programa <- pp$tau2_programa / (pp$tau2_programa + pp$var_programa_periodo + pp$sigma2)
write.csv(pp, file.path(out, "programa_periodo.csv"), row.names = FALSE)

# 5. Program sizes and diagnostics
n_prog <- as.vector(table(droplevels(d$programa)))
r <- resid(m2)
dg <- data.frame(programas = length(n_prog), n_min = min(n_prog), n_p25 = quantile(n_prog, .25), n_mediana = median(n_prog),
  n_p75 = quantile(n_prog, .75), n_max = max(n_prog), singular_M2 = isSingular(m2), singular_M3 = isSingular(m3),
  asimetria_residuos = mean((r - mean(r))^3) / sd(r)^3, curtosis_residuos = mean((r - mean(r))^4) / sd(r)^4,
  cor_residuos_ajustados = cor(abs(r), fitted(m2)))
# influence: ICC of M2 leaving out one program at a time
loo <- sapply(levels(droplevels(d$programa)), function(p) { x <- droplevels(d[d$programa != p, ]); x$y <- x$esp_cuidado
  m <- lmer(F(f_est, f_ing), data = x, REML = TRUE); vc(m)["prog"] / sum(vc(m)) })
dg$icc_loo_min <- min(loo); dg$icc_loo_max <- max(loo)
write.csv(dg, file.path(out, "diagnosticos.csv"), row.names = FALSE)

print(ctx, digits = 3); print(disc, digits = 3); print(com, digits = 3); print(com_cor, digits = 3)
print(cob); print(pp, digits = 3); print(dg, digits = 3)
