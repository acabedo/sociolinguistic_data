
paquetes <- c("tidyverse", "glmmTMB", "emmeans", "moments", "writexl", "ggridges")
nuevos <- paquetes[!paquetes %in% installed.packages()[,"Package"]]
if (length(nuevos)) install.packages(nuevos, repos="https://cloud.r-project.org")
suppressMessages(invisible(lapply(paquetes, library, character.only=TRUE)))

dir.create("analisis", showWarnings=FALSE)
dir.create("imagenes", showWarnings=FALSE)

CONF_THRESHOLD     <- 0.80   # umbral para IPs (pitch + articulación)
CONF_TURN_MEDIAN   <- 0.70   # umbral de MEDIANA de confianza por turno (speech rate)

RUN_DIAGNOSTICOS_OPCIONALES <- FALSE

format_p <- function(p)
  ifelse(p < .001, "< .001", sub("^0", "", formatC(p, format="f", digits=3)))

normalizar_emm <- function(df)
  df %>% rename(emmean=response) %>%
    rename_with(~"lower.CL", any_of(c("lower.CL","asymp.LCL","lwr","lower"))) %>%
    rename_with(~"upper.CL", any_of(c("upper.CL","asymp.UCL","upr","upper")))

add_social_vars <- function(df, file_col="file") {
  df %>% mutate(
    code = str_extract(.data[[file_col]], "(?<=VAL_)[HM][123][ABM]"),
    sex  = factor(case_when(str_sub(code,1,1)=="H"~"male", TRUE~"female"),
                  levels=c("female","male")),
    age  = factor(case_when(str_sub(code,2,2)=="1"~"18-35",
                            str_sub(code,2,2)=="2"~"35-55", TRUE~"55+"),
                  levels=c("18-35","35-55","55+")),
    education = factor(case_when(str_sub(code,3,3)=="A"~"high",
                                 str_sub(code,3,3)=="B"~"low", TRUE~"medium"),
                       levels=c("high","medium","low")),
    source = .data[[file_col]])
}

leer_tsv <- function(path) {
  raw <- read_tsv(path, col_types=cols(.default="c"), show_col_types=FALSE)
  if (names(raw)[1]=="...1") raw <- raw[,-1]
  raw
}

df_ip <- leer_tsv("analisis_prosodico.tsv") %>%
  mutate(n_vowel_phones = as.integer(n_vowel_phones),
         art_rate_vps   = as.numeric(speech_rate_vps),
         duration_s     = as.numeric(duration_s),
         start          = as.numeric(start),
         end            = as.numeric(end),
         confidence     = as.numeric(confidence),
         voiced_frames  = as.numeric(voiced_frames),
         pitch_P10_st   = as.numeric(pitch_P10_st),
         pitch_P90_st   = as.numeric(pitch_P90_st),
         pitch_range_st = as.numeric(pitch_range_st),
         pitch_level_st = (pitch_P10_st + pitch_P90_st)/2) %>%
  add_social_vars()

df_turns <- leer_tsv("analisis_turnos.tsv") %>%
  mutate(across(c(turn_duration_s, n_ips, n_vowels, speech_time_s, pause_time_s,
                  n_pauses, mean_pause_s, speech_rate_vps, speaking_proportion),
                as.numeric),
         turn_start = as.numeric(turn_start),
         turn_end   = as.numeric(turn_end)) %>%
  add_social_vars()

df_spk <- leer_tsv("analisis_hablante.tsv") %>%
  mutate(across(-c(file, speaker), ~suppressWarnings(as.numeric(.x)))) %>%
  add_social_vars()

cat(sprintf("Cargado — IP: %d | Turnos: %d | Hablantes: %d\n",
            nrow(df_ip), nrow(df_turns), nrow(df_spk)))

informante <- df_ip %>% group_by(source, speaker) %>%
  summarise(n=n(), .groups="drop") %>%
  group_by(source) %>% slice_max(n, n=1, with_ties=FALSE) %>%
  select(source, informant=speaker)

df_ip    <- df_ip    %>% inner_join(informante, by="source") %>% filter(speaker==informant)
df_turns <- df_turns %>% inner_join(informante, by="source") %>% filter(speaker==informant)
df_spk   <- df_spk   %>% inner_join(informante, by="source") %>% filter(speaker==informant)

conf_all <- df_ip %>% filter(!is.na(confidence)) %>% pull(confidence)

conf_stats <- tibble(
  conjunto    = c("Todas las IP del informante",
                  sprintf("IP con confidence >= %.2f (pitch + articulación)", CONF_THRESHOLD)),
  n           = c(length(conf_all),
                  sum(conf_all >= CONF_THRESHOLD)),
  media       = round(c(mean(conf_all),
                        mean(conf_all[conf_all >= CONF_THRESHOLD])), 3),
  mediana     = round(c(median(conf_all),
                        median(conf_all[conf_all >= CONF_THRESHOLD])), 3),
  P10         = round(c(quantile(conf_all, .10),
                        quantile(conf_all[conf_all >= CONF_THRESHOLD], .10)), 3),
  P90         = round(c(quantile(conf_all, .90),
                        quantile(conf_all[conf_all >= CONF_THRESHOLD], .90)), 3),
  minimo      = round(c(min(conf_all),
                        min(conf_all[conf_all >= CONF_THRESHOLD])), 3),
  maximo      = round(c(max(conf_all),
                        max(conf_all[conf_all >= CONF_THRESHOLD])), 3),
  pct_ge_090  = round(c(mean(conf_all >= .90),
                        NA_real_), 3),
  pct_ge_080  = round(c(mean(conf_all >= .80),
                        NA_real_), 3))

cat("\n=== Estadísticos de confianza de transcripción Whisper ===\n")
print(as.data.frame(conf_stats), digits=3, row.names=FALSE)
write_csv(conf_stats, "analisis/confidence_stats_v5.csv")


df_pitch <- df_ip %>%
  filter(confidence >= CONF_THRESHOLD,
         !is.na(pitch_range_st), pitch_range_st > 0)

# 4b. Articulation rate: confidence >= CONF_THRESHOLD + tasa válida
df_art <- df_ip %>%
  filter(confidence >= CONF_THRESHOLD,
         !is.na(art_rate_vps), art_rate_vps > 0,
         !is.na(n_vowel_phones), n_vowel_phones > 0)

ip_conf <- df_ip %>%
  filter(!is.na(confidence), !is.na(start), !is.na(end)) %>%
  select(source, start, end, confidence)

conf_por_turno <- df_turns %>%
  filter(!is.na(turn_start), !is.na(turn_end)) %>%
  select(source, turn_id, turn_start, turn_end) %>%
  inner_join(ip_conf, by="source", relationship="many-to-many") %>%
  filter(start >= turn_start - 0.05, end <= turn_end + 0.05) %>%
  group_by(source, turn_id) %>%
  summarise(conf_media_turno  = mean(confidence),
            conf_median_turno = median(confidence),
            .groups="drop")

df_turns_c <- df_turns %>%
  left_join(conf_por_turno, by=c("source","turn_id"))


df_sr <- df_turns_c %>%
  filter(conf_median_turno >= CONF_TURN_MEDIAN,
         !is.na(speech_rate_vps), speech_rate_vps > 0,
         turn_duration_s > 1, n_ips >= 2)

df_pause <- df_turns_c %>%
  filter(conf_median_turno >= CONF_TURN_MEDIAN,
         n_pauses > 0, !is.na(mean_pause_s), mean_pause_s > 0)

conf_turnos <- conf_por_turno %>% pull(conf_media_turno)
conf_turnos_median <- conf_por_turno$conf_median_turno
conf_turno_stats <- tibble(
  conjunto  = c("Todos los turnos del informante (mediana de conf. de IPs)",
                sprintf("Turnos con mediana de conf. >= %.2f (speech rate)", CONF_TURN_MEDIAN)),
  n         = c(nrow(conf_por_turno), nrow(df_sr)),
  media_conf_median = round(c(mean(conf_turnos_median, na.rm=TRUE),
                               mean(conf_turnos_median[conf_turnos_median >= CONF_TURN_MEDIAN], na.rm=TRUE)), 3),
  mediana_conf_median = round(c(median(conf_turnos_median, na.rm=TRUE),
                                 median(conf_turnos_median[conf_turnos_median >= CONF_TURN_MEDIAN], na.rm=TRUE)), 3),
  P10       = round(c(quantile(conf_turnos_median, .10, na.rm=TRUE),
                      quantile(conf_turnos_median[conf_turnos_median >= CONF_TURN_MEDIAN], .10, na.rm=TRUE)), 3),
  P90       = round(c(quantile(conf_turnos_median, .90, na.rm=TRUE),
                      quantile(conf_turnos_median[conf_turnos_median >= CONF_TURN_MEDIAN], .90, na.rm=TRUE)), 3))

cat("\n=== Confianza media por turno ===\n")
print(as.data.frame(conf_turno_stats), digits=3, row.names=FALSE)
write_csv(conf_turno_stats, "analisis/confidence_turns_v5.csv")

cat(sprintf("\nInformantes — IP pitch: %d | IP art: %d | turnos SR: %d | hablantes: %d\n",
            nrow(df_pitch), nrow(df_art), nrow(df_sr), n_distinct(df_spk$source)))


n_celda <- df_spk %>% group_by(sex, age, education) %>%
  summarise(n_hab=n(), .groups="drop") %>% arrange(sex, education, age)
cat("\n--- N de informantes por celda ---\n"); print(n_celda, n=100)
write_csv(n_celda, "analisis/n_por_celda_v5.csv")


desc_fn <- function(data, var, ...) {
  v <- sym(var); g <- enquos(...)
  data %>% group_by(!!!g) %>%
    summarise(n_obs=n(), n_hab=n_distinct(source),
              mean=round(mean(!!v, na.rm=TRUE), 3),
              median=round(median(!!v, na.rm=TRUE), 3),
              sd=round(sd(!!v, na.rm=TRUE), 3),
              IQR=round(IQR(!!v, na.rm=TRUE), 3),
              .groups="drop")
}

resumen_corpus <- tibble(
  variable = c("pitch range (st)","pitch level (st)","articulation rate (vps)",
               "speech rate (vps)","mean pause (s)"),
  mean   = round(c(mean(df_pitch$pitch_range_st), mean(df_pitch$pitch_level_st),
                   mean(df_art$art_rate_vps), mean(df_sr$speech_rate_vps),
                   mean(df_pause$mean_pause_s)), 3),
  median = round(c(median(df_pitch$pitch_range_st), median(df_pitch$pitch_level_st),
                   median(df_art$art_rate_vps), median(df_sr$speech_rate_vps),
                   median(df_pause$mean_pause_s)), 3))
write_csv(resumen_corpus, "analisis/resumen_corpus_v5.csv")
cat("\n--- Resumen del corpus (medias globales) ---\n")
print(resumen_corpus, n=10)

tabla_kendall <- df_spk %>%
  select(file, sex, age, education,
         art_rate_median, art_rate_mean, art_rate_sd,
         n_pauses, pause_median_ms, pause_mean_ms,
         overall_art_rate, overall_spk_rate,
         pitch_range_median, pitch_range_mean, pitch_level_median) %>%
  arrange(sex, education, age)
write_csv(tabla_kendall, "analisis/tabla_hablantes_v5.csv")

writexl::write_xlsx(list(
  pitch_range_by_group  = desc_fn(df_pitch, "pitch_range_st", sex, age, education),
  articulation_by_group = desc_fn(df_art,   "art_rate_vps",   sex, age, education),
  speech_rate_by_group  = desc_fn(df_sr,    "speech_rate_vps",sex, age, education),
  mean_pause_by_group   = desc_fn(df_pause, "mean_pause_s",   sex, age, education),
  n_per_cell            = n_celda,
  per_speaker           = tabla_kendall,
  confidence_stats      = conf_stats,
  confidence_turns      = conf_turno_stats
), path="analisis/descriptivos_v5.xlsx")


ajustar <- function(data, dv, cov=NULL, etq="") {
  ct <- if (!is.null(cov)) paste0(" + ", cov) else ""
  fam <- Gamma(link="log")
  m0 <- glmmTMB(as.formula(paste0(dv,"~sex+education+age",ct,"+(1|source)")), data, family=fam)
  m2 <- glmmTMB(as.formula(paste0(dv,"~(sex+education+age)^2",ct,"+(1|source)")), data, family=fam)
  m3 <- glmmTMB(as.formula(paste0(dv,"~sex*education*age",ct,"+(1|source)")), data, family=fam)
  aic <- tibble(model=c("additive","two-way","three-way"),
                AIC=round(c(AIC(m0),AIC(m2),AIC(m3)),1)) %>%
    mutate(delta_AIC=round(AIC - min(AIC),1))
  cat(sprintf("\n=== AIC (%s) ===\n", etq)); print(aic)
  write_csv(aic, sprintf("analisis/aic_%s_v5.csv", etq))
  m0   # modelo aditivo si sigue siendo el preferido; revisar AIC
}

tabla_coef <- function(m, archivo) {
  as.data.frame(coef(summary(m))$cond) %>%
    tibble::rownames_to_column("term") %>%
    rename(estimate=Estimate, std.error=`Std. Error`, stat=`z value`, p=`Pr(>|z|)`) %>%
    mutate(estimate=round(estimate,3), std.error=round(std.error,3),
           stat=round(stat,2), p_apa=format_p(p)) %>%
    select(-p) %>% write_csv(archivo)
}

modelo_pitch <- ajustar(df_pitch, "pitch_range_st", "log(voiced_frames)", "pitch_range")
modelo_art   <- ajustar(df_art,   "art_rate_vps",   "log(n_vowel_phones)", "articulation")
modelo_sr    <- ajustar(df_sr,    "speech_rate_vps", "log(n_ips)",          "speech_rate")

tabla_coef(modelo_pitch, "analisis/glmm_pitch_range_v5.csv")
tabla_coef(modelo_art,   "analisis/glmm_articulation_v5.csv")
tabla_coef(modelo_sr,    "analisis/glmm_speech_rate_v5.csv")

cor_rn <- cor.test(df_pitch$pitch_range_st, df_pitch$pitch_level_st)
cat(sprintf("\nCorrelación rango-nivel: r = %.3f, p %s\n",
            cor_rn$estimate, format_p(cor_rn$p.value)))
writeLines(sprintf("r = %.3f; p %s; n = %d",
                   cor_rn$estimate, format_p(cor_rn$p.value), nrow(df_pitch)),
           "analisis/correlation_range_level_v5.txt")

emm_de <- function(m)
  as.data.frame(emmeans(m, ~sex*education*age, type="response")) %>%
  normalizar_emm() %>% mutate(across(where(is.numeric), ~round(.x,3)))

emm_pitch <- emm_de(modelo_pitch); write_csv(emm_pitch, "analisis/emmeans_pitch_range_v5.csv")
emm_art   <- emm_de(modelo_art);   write_csv(emm_art,   "analisis/emmeans_articulation_v5.csv")
emm_sr    <- emm_de(modelo_sr);    write_csv(emm_sr,    "analisis/emmeans_speech_rate_v5.csv")

write_csv(as.data.frame(pairs(emmeans(modelo_pitch, ~education|sex*age))),
          "analisis/contrasts_pitch_range_v5.csv")

pal_edu  <- c("high"="#08519c","medium"="#4292c6","low"="#9ecae1")
sex_labs <- c("female"="Sex: female","male"="Sex: male")
age_labs <- c("18-35"="Age 18-35","35-55"="Age 35-55","55+"="Age 55+")
tema <- theme_bw(base_size=9) +
  theme(strip.background=element_rect(fill="grey90", color="grey60"),
        strip.text=element_text(size=8),
        legend.title=element_text(size=8), legend.text=element_text(size=7.5),
        plot.title=element_text(size=10, margin=margin(b=4)))

emm_plot <- function(d, ylab, titulo)
  ggplot(d, aes(age, emmean, color=education, group=education)) +
    geom_errorbar(aes(ymin=lower.CL, ymax=upper.CL), width=.12, linewidth=.5, alpha=.6) +
    geom_line(linewidth=.9) + geom_point(size=2.5) +
    facet_wrap(~sex, labeller=labeller(sex=sex_labs)) +
    scale_color_manual(values=pal_edu, name="Education") +
    labs(title=titulo, x="Age group", y=ylab) + tema

ggsave("imagenes/v4_violin_pitch_range.png",
  ggplot(df_pitch, aes(age, pitch_range_st, fill=education)) +
    geom_violin(position=position_dodge(.8), alpha=.4, color=NA, scale="width") +
    geom_boxplot(position=position_dodge(.8), width=.18, outlier.size=.4, linewidth=.3) +
    facet_wrap(~sex, labeller=labeller(sex=sex_labs)) +
    scale_fill_manual(values=pal_edu, name="Education") +
    labs(title="Pitch range by group (median + spread)",
         x="Age group", y="Pitch range (st)") + tema,
  width=9, height=4.5, dpi=300, bg="white")

ggsave("imagenes/v4_ridgeline_pitch_range.png",
  ggplot(df_pitch, aes(pitch_range_st, age, fill=education)) +
    ggridges::geom_density_ridges(quantile_lines=TRUE, quantiles=2,
                                  alpha=.85, scale=1.1, linewidth=.3, color="grey30") +
    facet_grid(education~sex, labeller=labeller(sex=sex_labs)) +
    scale_fill_manual(values=pal_edu, name="Education") +
    labs(title="Distribution of pitch range", x="Pitch range (st)", y="Age group") + tema,
  width=9, height=6, dpi=300, bg="white")

ggsave("imagenes/v4_emmeans_pitch_range.png",
  emm_plot(emm_pitch, "Pitch range (st)", "Pitch range — estimated marginal means"),
  width=8, height=4, dpi=300, bg="white")

ggsave("imagenes/v4_range_vs_level.png",
  ggplot(df_pitch, aes(pitch_level_st, pitch_range_st, color=education)) +
    geom_point(alpha=.2, size=.7) +
    geom_smooth(method="lm", se=FALSE, linewidth=.8) +
    facet_grid(sex~age, labeller=labeller(sex=sex_labs, age=age_labs)) +
    scale_color_manual(values=pal_edu, name="Education") +
    labs(title="Pitch range vs pitch level",
         x="Pitch level (st)", y="Pitch range (st)") + tema,
  width=8, height=5, dpi=300, bg="white")

ggsave("imagenes/v4_violin_articulation.png",
  ggplot(df_art, aes(age, art_rate_vps, fill=education)) +
    geom_violin(position=position_dodge(.8), alpha=.4, color=NA, scale="width") +
    geom_boxplot(position=position_dodge(.8), width=.18, outlier.size=.4, linewidth=.3) +
    facet_wrap(~sex, labeller=labeller(sex=sex_labs)) +
    scale_fill_manual(values=pal_edu, name="Education") +
    labs(title="Articulation rate by group", x="Age group", y="Vowels/s") + tema,
  width=9, height=4.5, dpi=300, bg="white")

ggsave("imagenes/v4_emmeans_articulation.png",
  emm_plot(emm_art, "Vowels/s", "Articulation rate — estimated marginal means"),
  width=8, height=4, dpi=300, bg="white")

ggsave("imagenes/v4_articulation_vs_length.png",
  ggplot(df_art, aes(n_vowel_phones, art_rate_vps)) +
    geom_point(alpha=.12, size=.6, color="grey40") +
    geom_smooth(method="loess", se=TRUE, color="#08519c", linewidth=.9) +
    labs(title="Articulation rate vs phrase length",
         x="IP length (vowel nuclei)", y="Vowels/s") + tema,
  width=6, height=4, dpi=300, bg="white")

ggsave("imagenes/v4_emmeans_speech_rate.png",
  emm_plot(emm_sr, "Vowels/s", "Speech rate (turn) — estimated marginal means"),
  width=8, height=4, dpi=300, bg="white")

ggsave("imagenes/v4_articulation_vs_speech_rate.png",
  ggplot(df_spk, aes(art_rate_median, overall_spk_rate, color=education)) +
    geom_abline(slope=1, intercept=0, linetype=2, color="grey60") +
    geom_point(alpha=.8, size=1.8) +
    facet_grid(sex~age, labeller=labeller(sex=sex_labs, age=age_labs)) +
    scale_color_manual(values=pal_edu, name="Education") +
    labs(title="Articulation vs speech rate per speaker (dashed = equality)",
         x="Articulation rate (vowels/s, no pauses)",
         y="Speech rate (vowels/s, with pauses)") + tema,
  width=8, height=5, dpi=300, bg="white")

ggsave("imagenes/v4_n_per_cell.png",
  ggplot(n_celda, aes(age, education, fill=n_hab)) +
    geom_tile(color="white", linewidth=.8) + geom_text(aes(label=n_hab), size=3.2) +
    facet_wrap(~sex, labeller=labeller(sex=sex_labs)) +
    scale_fill_viridis_c(option="C", direction=-1, name="N speakers") +
    labs(title="Number of speakers per cell", x="Age group", y="Education") + tema,
  width=8, height=3.5, dpi=300, bg="white")

cat("\n=== v5 completado. Salidas en analisis/ e imagenes/ ===\n")
cat("Revisa analisis/aic_*_v5.csv: si el modelo aditivo NO es el mejor por AIC,\n")
cat("cambia la última línea de ajustar() para devolver m2 o m3.\n")
