# High-quality accreditation as a program covariate (exploratory).
# Accreditation status is the current one in the public program registry of the National Higher Education Information
# System (SNIES), not the status during the examination years.
# Inputs: data/processed/modelo_enfermeria.parquet and data/raw/acreditacion/snies_programas.csv (see README).
# Outputs: results/models/additional/acreditacion*.csv
# Run from the repository root: Rscript scripts/12_accreditation_model.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
d0 <- as.data.frame(read_parquet("data/processed/modelo_enfermeria.parquet"))
d <- subset(d0, analitica & !is.na(edad_c))
acr <- read.csv("data/raw/acreditacion/snies_programas.csv", encoding = "UTF-8", na.strings = "")
acr$acreditado <- as.integer(acr$reconocimiento_ministerio %in% "Acreditación de alta calidad")
acr$inactivo <- as.integer(acr$estado_programa == "Inactivo")
d <- merge(d, acr[, c("codigo_snies", "acreditado", "inactivo")], by.x = "programa", by.y = "codigo_snies", all.x = TRUE)
stopifnot(!anyNA(d$acreditado))
for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "region", "programa", "anio")) d[[v]] <- factor(d[[v]])
d$estrato <- relevel(d$estrato, "E1"); d$educ_madre <- relevel(d$educ_madre, "Primaria_o_menos")
d$area <- relevel(d$area, "Cabecera"); d$horas_trabajo <- relevel(d$horas_trabajo, "h0"); d$region <- relevel(d$region, "Centro-Oriente")
f_est <- "mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo + beca + credito"
f_ing <- "sb11_z_comp + sb11_escala_nueva + brecha_anios"
f_prog <- "oficial + universidad + region + log_tamano_c"
F <- function(...) as.formula(paste("esp_cuidado ~ anio +", paste(c(...), collapse = " + "), "+ (1 | programa)"))
vc <- function(m) { v <- as.data.frame(VarCorr(m)); c(prog = v$vcov[v$grp == "programa"], res = v$vcov[v$grp == "Residual"]) }
co <- function(m, t) { s <- summary(m)$coefficients; if (t %in% rownames(s)) s[t, 1:2] else c(NA, NA) }
prog <- unique(d[, c("programa", "acreditado", "inactivo", "oficial", "region")])
tab <- data.frame(programas = nrow(prog), acreditados = sum(prog$acreditado), inactivos = sum(prog$inactivo),
                  acred_publicos = mean(prog$acreditado[prog$oficial == 1]), acred_privados = mean(prog$acreditado[prog$oficial == 0]),
                  acred_caribe = mean(prog$acreditado[prog$region == "Caribe"]), acred_otras = mean(prog$acreditado[prog$region != "Caribe"]),
                  estudiantes_acreditados = mean(d$acreditado))
res <- list()
for (k in c("M2", "M2+acred", "M3", "M3+acred", "M3+acred sin inactivos")) {
  dat <- if (grepl("sin inactivos", k)) d[d$inactivo == 0, ] else d
  form <- switch(k, "M2" = F(f_est, f_ing), "M2+acred" = F(f_est, f_ing, "acreditado"), "M3" = F(f_est, f_ing, f_prog),
                 "M3+acred" = F(f_est, f_ing, f_prog, "acreditado"), "M3+acred sin inactivos" = F(f_est, f_ing, f_prog, "acreditado"))
  m <- lmer(form, data = dat, REML = TRUE); x <- vc(m)
  res[[k]] <- data.frame(modelo = k, n = nobs(m), programas = ngrps(m)[["programa"]], tau2 = x["prog"], icc = x["prog"] / sum(x),
    acreditado = co(m, "acreditado")[1], acreditado_ee = co(m, "acreditado")[2], oficial = co(m, "oficial")[1], oficial_ee = co(m, "oficial")[2],
    caribe = co(m, "regionCaribe")[1], caribe_ee = co(m, "regionCaribe")[2])
}
res <- do.call(rbind, res); rownames(res) <- NULL
dir.create("results/models/additional", showWarnings = FALSE, recursive = TRUE)
write.csv(res, "results/models/additional/acreditacion.csv", row.names = FALSE)
write.csv(tab, "results/models/additional/acreditacion_descriptivos.csv", row.names = FALSE)
print(tab, digits = 3); print(res, digits = 3)
