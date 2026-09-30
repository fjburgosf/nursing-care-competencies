# Program effects of M2 (nursing care) estimated separately in 2018-2019 and 2021-2024.
# Same specification as M2 in scripts/04_models.R. Output: results/models/efectos_programa_periodos.csv
# Run from the repository root: Rscript scripts/05_period_effects.R
suppressPackageStartupMessages({library(arrow); library(lme4)})
dir.create("results/models", showWarnings = FALSE, recursive = TRUE)
d <- as.data.frame(read_parquet("data/processed/modelo_enfermeria.parquet"))
d <- subset(d, analitica & !is.na(edad_c) & !is.na(esp_cuidado))
for (v in c("estrato", "educ_madre", "area", "horas_trabajo", "programa", "anio")) d[[v]] <- factor(d[[v]])
d$estrato <- relevel(d$estrato, "E1"); d$educ_madre <- relevel(d$educ_madre, "Primaria_o_menos")
d$area <- relevel(d$area, "Cabecera"); d$horas_trabajo <- relevel(d$horas_trabajo, "h0"); d$y <- d$esp_cuidado
f <- y ~ anio + mujer + edad_c + edad_c2 + estrato + educ_madre + internet + area + horas_trabajo + beca + credito +
  sb11_z_comp + sb11_escala_nueva + brecha_anios + (1 | programa)
eff <- lapply(split(d, d$periodo), function(x) { x <- droplevels(x); r <- ranef(lmer(f, data = x))$programa
  data.frame(programa = rownames(r), efecto = r[, 1]) })
cnt <- as.data.frame.matrix(table(d$programa, d$periodo))
out <- merge(setNames(eff[["2018_2019"]], c("programa", "p2018_2019")), setNames(eff[["2021_2024"]], c("programa", "p2021_2024")))
out <- out[out$programa %in% rownames(cnt)[cnt[, 1] >= 30 & cnt[, 2] >= 30], ]
write.csv(out, "results/models/efectos_programa_periodos.csv", row.names = FALSE)
cat("programas:", nrow(out), " rho:", cor(out$p2018_2019, out$p2021_2024, method = "spearman"), "\n")
