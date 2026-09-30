# Multilevel models for the three specific care modules (students nested in programs).
#   M0 year only, M1 + student characteristics, M2 + entry achievement (Saber 11), M3 + program characteristics,
#   M4 + concurrent critical reading and quantitative reasoning (nursing care only).
# Variance decomposition with parametric bootstrap of the ICC, LRT for the program variance, program effects (BLUPs),
# consistency between modules and stability between periods (Spearman with bootstrap), coefficients.
# Input: data/processed/modelo_enfermeria.parquet (scripts/03_prepare_model_data.py). Outputs: results/models/*.csv
# Run from the repository root: Rscript scripts/04_models.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
set.seed(20260928)
dir.create("results/models", showWarnings = FALSE, recursive = TRUE)

d0 <- as.data.frame(read_parquet("data/processed/modelo_enfermeria.parquet"))
d <- subset(d0, analitica & !is.na(edad_c))
for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "region", "programa", "institucion", "anio"))
  d[[v]] <- factor(d[[v]])
d$estrato <- relevel(d$estrato, "E1"); d$educ_madre <- relevel(d$educ_madre, "Primaria_o_menos")
d$area <- relevel(d$area, "Cabecera"); d$horas_trabajo <- relevel(d$horas_trabajo, "h0")
d$region <- relevel(d$region, "Centro-Oriente")

f_est <- "mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo + beca + credito"
f_ing <- "sb11_z_comp + sb11_escala_nueva + brecha_anios"
f_prog <- "oficial + universidad + region + log_tamano_c"
forms <- list(
  M0 = "y ~ anio + (1 | programa)",
  M1 = paste("y ~ anio +", f_est, "+ (1 | programa)"),
  M2 = paste("y ~ anio +", f_est, "+", f_ing, "+ (1 | programa)"),
  M3 = paste("y ~ anio +", f_est, "+", f_ing, "+", f_prog, "+ (1 | programa)"),
  M4 = paste("y ~ anio +", f_est, "+", f_ing, "+", f_prog, "+ lc_z + rc_z + (1 | programa)"))

vc <- function(m) { v <- as.data.frame(VarCorr(m)); c(prog = v$vcov[v$grp == "programa"], res = v$vcov[v$grp == "Residual"]) }
icc <- function(m) { x <- vc(m); unname(x["prog"] / (x["prog"] + x["res"])) }

fit_set <- function(outcome, dat, models = names(forms)) {
  dat$y <- dat[[outcome]]; dat <- dat[!is.na(dat$y), ]
  lapply(setNames(models, models), function(k) lmer(as.formula(forms[[k]]), data = dat, REML = TRUE))
}

# Parametric bootstrap of the ICC (500 replicates)
boot_icc <- function(m, B = 500) {
  b <- bootMer(m, FUN = icc, nsim = B, type = "parametric", use.u = FALSE, seed = 20260928)
  quantile(b$t, c(.025, .975), na.rm = TRUE)
}

outcomes <- c(cuidado = "esp_cuidado", promocion = "esp_promocion", atencion = "esp_atencion")
vd_rows <- list(); fits <- list()
for (o in names(outcomes)) {
  mods <- if (o == "cuidado") names(forms) else c("M0", "M1", "M2", "M3")
  fs <- fit_set(outcomes[[o]], d, mods); fits[[o]] <- fs
  for (k in names(fs)) {
    x <- vc(fs[[k]]); ci <- boot_icc(fs[[k]], B = if (o == "cuidado") 500 else 200)
    vd_rows[[paste(o, k)]] <- data.frame(modulo = o, modelo = k, n = nobs(fs[[k]]),
      programas = ngrps(fs[[k]])[["programa"]], var_programa = x["prog"], var_residual = x["res"],
      icc = icc(fs[[k]]), icc_li = ci[1], icc_ls = ci[2])
  }
}
vd <- do.call(rbind, vd_rows); rownames(vd) <- NULL
vd$reduccion_vs_M1 <- NA
for (o in unique(vd$modulo)) {
  base <- vd$var_programa[vd$modulo == o & vd$modelo == "M1"]
  idx <- vd$modulo == o; vd$reduccion_vs_M1[idx] <- 1 - vd$var_programa[idx] / base
}
write.csv(vd, "results/models/descomposicion_varianza.csv", row.names = FALSE)
print(vd, digits = 3)

# H1: program variance > 0 in M2 (LRT with a chi2(0)/chi2(1) mixture: p = 0.5 * P(chi2_1 > LRT))
dd <- d[!is.na(d$esp_cuidado), ]; dd$y <- dd$esp_cuidado
m2_ml <- lmer(as.formula(forms$M2), data = dd, REML = FALSE)
lm2 <- lm(as.formula(sub("\\+ \\(1 \\| programa\\)", "", forms$M2)), data = dd)
lrt <- as.numeric(2 * (logLik(m2_ml) - logLik(lm2))); p_h1 <- 0.5 * pchisq(lrt, 1, lower.tail = FALSE)

# Program effects (BLUPs) with conditional standard errors
blup <- function(m) { r <- ranef(m, condVar = TRUE)$programa
  data.frame(programa = rownames(r), efecto = r[, 1], se = sqrt(attr(r, "postVar")[1, 1, ])) }
pe <- merge(merge(setNames(blup(fits$cuidado$M2), c("programa", "cuidado_M2", "cuidado_M2_se")),
                  setNames(blup(fits$cuidado$M0), c("programa", "cuidado_M0", "cuidado_M0_se"))),
            merge(setNames(blup(fits$promocion$M2), c("programa", "promocion_M2", "promocion_M2_se")),
                  setNames(blup(fits$atencion$M2), c("programa", "atencion_M2", "atencion_M2_se")), all = TRUE), all = TRUE)
nprog <- aggregate(estu_consecutivo ~ programa, data = d, FUN = length); names(nprog)[2] <- "n"
pe <- merge(pe, nprog)
write.csv(pe, "results/models/efectos_programa.csv", row.names = FALSE)
excl0 <- function(e, s) sum(abs(e / s) > 1.96, na.rm = TRUE)

# H3: consistency between modules (Spearman with bootstrap over programs)
sp_boot <- function(x, y, B = 2000) {
  ok <- complete.cases(x, y); x <- x[ok]; y <- y[ok]
  r <- cor(x, y, method = "spearman")
  bs <- replicate(B, { i <- sample(seq_along(x), replace = TRUE); cor(x[i], y[i], method = "spearman") })
  c(rho = r, li = unname(quantile(bs, .025)), ls = unname(quantile(bs, .975)), n = length(x),
    p = max(2 * min(mean(bs <= 0), mean(bs >= 0)), 1 / B))  # lower bound 1/B: the bootstrap cannot resolve smaller p values
}
h3a <- sp_boot(pe$cuidado_M2, pe$promocion_M2); h3b <- sp_boot(pe$cuidado_M2, pe$atencion_M2)

# H4: stability between periods (programs with >= 30 students in each period)
per <- lapply(split(dd, dd$periodo), function(x) { x$anio <- droplevels(x$anio)
  m <- lmer(as.formula(forms$M2), data = x, REML = TRUE); blup(m) })
cnt <- table(dd$programa, dd$periodo); keep <- rownames(cnt)[cnt[, 1] >= 30 & cnt[, 2] >= 30]
st <- merge(per[["2018_2019"]], per[["2021_2024"]], by = "programa"); st <- st[st$programa %in% keep, ]
h4 <- sp_boot(st$efecto.x, st$efecto.y)

# Coefficients (M2, M3, M4) for nursing care
coefs <- function(m, k) { s <- summary(m)$coefficients
  data.frame(modelo = k, termino = rownames(s), estimado = s[, 1], ee = s[, 2], t = s[, 3]) }
cf <- do.call(rbind, lapply(c("M2", "M3", "M4"), function(k) coefs(fits$cuidado[[k]], k)))
write.csv(cf, "results/models/coeficientes_cuidado.csv", row.names = FALSE)
getp <- function(k, term) { r <- cf[cf$modelo == k & cf$termino == term, ]; 2 * pnorm(-abs(r$t)) }
h5 <- cf[cf$modelo == "M2" & cf$termino %in% c("horas_trabajoh21_30", "horas_trabajoh_gt30"), ]
tests <- data.frame(
  hipotesis = c("H1 var programa>0 (M2)", "H3a Cuidado~Promocion", "H3b Cuidado~Atencion", "H4 estabilidad",
                "H5a trabajo 21-30h", "H5b trabajo >30h", "H6a lectura critica", "H6b razonamiento cuantitativo"),
  estimado = c(lrt, h3a["rho"], h3b["rho"], h4["rho"], h5$estimado, cf$estimado[cf$modelo == "M4" & cf$termino == "lc_z"],
               cf$estimado[cf$modelo == "M4" & cf$termino == "rc_z"]),
  p = c(p_h1, h3a["p"], h3b["p"], h4["p"], getp("M2", "horas_trabajoh21_30"), getp("M2", "horas_trabajoh_gt30"),
        getp("M4", "lc_z"), getp("M4", "rc_z")))
tests$p_holm <- p.adjust(tests$p, "holm")
write.csv(tests, "results/models/hipotesis.csv", row.names = FALSE)
corr <- rbind(H3a = h3a, H3b = h3b, H4 = h4)
write.csv(corr, "results/models/correlaciones_programa.csv")

cat("\n== H1 LRT:", round(lrt, 1), "p =", signif(p_h1, 3), "\n")
cat("Programas con intervalo que excluye el promedio (Cuidado): M0 =", excl0(pe$cuidado_M0, pe$cuidado_M0_se),
    "| M2 =", excl0(pe$cuidado_M2, pe$cuidado_M2_se), "de", nrow(pe), "\n")
print(corr, digits = 3); print(tests, digits = 3)
print(cf[cf$modelo %in% c("M3", "M4") & !grepl("^anio|Intercept", cf$termino), c(1, 2, 3, 4)], digits = 3)
writeLines(capture.output(sessionInfo()), "results/models/sessionInfo.txt")
