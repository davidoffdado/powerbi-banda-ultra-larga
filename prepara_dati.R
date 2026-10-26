# Prepara i dati del Piano Banda Ultra Larga (aree bianche) per Power BI
# Fonte: relazioni MIMIT sullo stato di avanzamento, dataset costruito durante l'assegno UnivPM
# Output: schema a stella in dati/ (2 tabelle dei fatti, 3 dimensioni)

library(haven)
library(dplyr)
library(tidyr)
library(stringr)

SRC <- "C:/Users/David/Desktop/Lavoro/UNIVPM/Lavoro/Banda Ultra Larga/dataset-bul-v2.dta"
OUT <- "C:/Users/David/Desktop/powerbi-banda-ultra-larga/dati"

d <- read_dta(SRC) %>% zap_labels()

#### DIMENSIONE REGIONI ####
regioni <- tribble(
  ~regio,                  ~regione,                ~codice_istat, ~nuts2,  ~macroarea,
  "Piedmont",              "Piemonte",              "01", "ITC1", "Nord-ovest",
  "Aosta Valley",          "Valle d'Aosta",         "02", "ITC2", "Nord-ovest",
  "Lombardy",              "Lombardia",             "03", "ITC4", "Nord-ovest",
  "Trentino-South Tyrol",  "Trentino-Alto Adige",   "04", "ITH2", "Nord-est",
  "Veneto",                "Veneto",                "05", "ITH3", "Nord-est",
  "Friuli-Venezia Giulia", "Friuli-Venezia Giulia", "06", "ITH4", "Nord-est",
  "Liguria",               "Liguria",               "07", "ITC3", "Nord-ovest",
  "Emilia-Romagna",        "Emilia-Romagna",        "08", "ITH5", "Nord-est",
  "Tuscany",               "Toscana",               "09", "ITI1", "Centro",
  "Umbria",                "Umbria",                "10", "ITI2", "Centro",
  "Marche",                "Marche",                "11", "ITI3", "Centro",
  "Lazio",                 "Lazio",                 "12", "ITI4", "Centro",
  "Abruzzo",               "Abruzzo",               "13", "ITF1", "Sud",
  "Molise",                "Molise",                "14", "ITF2", "Sud",
  "Campania",              "Campania",              "15", "ITF3", "Sud",
  "Apulia",                "Puglia",                "16", "ITF4", "Sud",
  "Basilicata",            "Basilicata",            "17", "ITF5", "Sud",
  "Calabria",              "Calabria",              "18", "ITF6", "Sud",
  "Sicily",                "Sicilia",               "19", "ITG1", "Isole",
  "Sardinia",              "Sardegna",              "20", "ITG2", "Isole")

dim_regione <- d %>%
  select(regio, bando = cft, programmati_apr2020 = previsti_ap20,
         programmati_apr2023 = previsti_ap23, programmati_dic2023 = previsti_d23) %>%
  inner_join(regioni, by = "regio") %>%
  transmute(codice_istat, regione, nuts2, macroarea, bando = paste("Bando", bando),
            programmati_apr2020, programmati_apr2023, programmati_dic2023) %>%
  arrange(codice_istat)
stopifnot(nrow(dim_regione) == 20)

#### PERIODI ####
mesi <- c(ap = 4, a = 4, jan = 1, ja = 1, f = 2, mar = 3, may = 5, jun = 6, j = 7, jul = 7,
          au = 8, d = 12)
nomi_mesi <- c("gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic")
a_data <- function(codice) {
  m <- str_match(codice, "^([a-z]+)(\\d{2})$")
  as.Date(sprintf("20%s-%02d-01", m[, 3], mesi[m[, 2]]))
}

#### FATTI: AVANZAMENTO PER FASE ####
# os = progetti consegnati / cantieri aperti, cs = progetti approvati / cantieri chiusi
fasi <- c(fin = "Progetto definitivo", exe = "Progetto esecutivo", con = "Lavori")
fatti_avanzamento <- d %>%
  select(regio, matches("^(os|cs)_[a-z]+\\d{2}_(fin|exe|con)$")) %>%
  pivot_longer(-regio, names_to = c("stato", "periodo", "fase"),
               names_pattern = "(os|cs)_([a-z]+\\d{2})_(fin|exe|con)", values_to = "n") %>%
  pivot_wider(names_from = stato, values_from = n) %>%
  inner_join(regioni %>% select(regio, codice_istat), by = "regio") %>%
  transmute(codice_istat, data = a_data(periodo), fase_id = match(fase, names(fasi)),
            consegnati_o_aperti = as.integer(os), approvati_o_chiusi = as.integer(cs)) %>%
  arrange(codice_istat, data, fase_id)
stopifnot(nrow(fatti_avanzamento) == 20 * 15 * 3, !anyNA(fatti_avanzamento$data))

#### FATTI: VALORI ECONOMICI ####
economico <- function(prefisso, nome) d %>%
  select(regio, starts_with(paste0(prefisso, "_"))) %>%
  pivot_longer(-regio, names_to = "periodo", values_to = nome) %>%
  # unione per data e non per codice: gennaio 2023 è "jan23" in vocs e pow ma "ja23" in bw
  mutate(data = a_data(sub(paste0("^", prefisso, "_"), "", periodo)), .keep = "unused")
fatti_economico <- economico("vocs", "valore_cantieri_avviati") %>%
  full_join(economico("pow", "avanzamento_lavori"), by = c("regio", "data")) %>%
  full_join(economico("bw", "lavori_contabilizzati"), by = c("regio", "data")) %>%
  inner_join(regioni %>% select(regio, codice_istat), by = "regio") %>%
  transmute(codice_istat, data,
            across(c(valore_cantieri_avviati, avanzamento_lavori, lavori_contabilizzati), ~ round(.x))) %>%
  arrange(codice_istat, data)
stopifnot(!anyNA(fatti_economico$data), !anyDuplicated(fatti_economico[, c("codice_istat", "data")]))

#### DIMENSIONI FASE E DATA ####
dim_fase <- tibble(fase_id = 1:3, fase = unname(fasi),
                   consegnati_o_aperti_significa = c("progetti consegnati", "progetti consegnati", "cantieri aperti"),
                   approvati_o_chiusi_significa = c("progetti approvati", "progetti approvati", "cantieri chiusi"))

date <- sort(unique(c(fatti_avanzamento$data, fatti_economico$data)))
dim_data <- tibble(data = date, anno = as.integer(format(date, "%Y")),
                   mese = as.integer(format(date, "%m"))) %>%
  mutate(periodo = paste(nomi_mesi[mese], anno),
         ordine = row_number(),
         rilevazione_fasi = data %in% fatti_avanzamento$data,
         fine_anno = mese == 12)

#### SCRITTURA ####
scrivi <- function(x, nome) write.csv(x, file.path(OUT, paste0(nome, ".csv")), row.names = FALSE,
                                      fileEncoding = "UTF-8", na = "")
scrivi(dim_regione, "dim_regione")
scrivi(dim_fase, "dim_fase")
scrivi(dim_data, "dim_data")
scrivi(fatti_avanzamento, "fatti_avanzamento")
scrivi(fatti_economico, "fatti_economico")

# controlli rapidi, confrontabili con i numeri del caso studio
ultimo <- fatti_avanzamento %>% filter(data == max(data), fase_id == 3)
cat("cantieri chiusi a dic 2024:", sum(ultimo$approvati_o_chiusi), "su", sum(dim_regione$programmati_dic2023),
    sprintf("(%.1f%%)\n", 100 * sum(ultimo$approvati_o_chiusi) / sum(dim_regione$programmati_dic2023)))
cat("righe:", nrow(fatti_avanzamento), "avanzamento,", nrow(fatti_economico), "economico,",
    nrow(dim_data), "date\n")
cat("valore cantieri avviati dic 2024 (mln):",
    round(sum(fatti_economico$valore_cantieri_avviati[fatti_economico$data == max(fatti_economico$data)]) / 1e6), "\n")
cat("NA economico:", sum(is.na(fatti_economico[, 3:5])), "\n")
