# Codigo extraido verbatim do prompt Prompt_EXTRACAO_DADOS_BACEN.md
# Trechos na ordem em que aparecem no documento (00_setup.R + leitura + esqueleto).

   periodo_coberto <- range(painel$mes)              # c(min, max) das datas reais
   anos_disponiveis <- sort(unique(lubridate::year(painel$mes)))
   meses_por_serie  <- painel |> count(codigo)       # cobertura assimétrica
   

# ---- bloco seguinte ----

# --- 0. Semente e opcoes globais ---------------------------------------------
set.seed(2026)
options(stringsAsFactors = FALSE, scipen = 999)

# --- 1. Pacotes ---------------------------------------------------------------
suppressPackageStartupMessages({
  library(here); library(fs); library(jsonlite); library(dplyr)
  library(tidyr); library(lubridate); library(zoo); library(ggplot2)
  library(scales); library(tibble); library(purrr)
})
optional_pkgs <- c("readr", "data.table", "viridis", "RColorBrewer",
                   "patchwork", "openxlsx", "writexl", "janitor")
for (p in optional_pkgs) {
  if (requireNamespace(p, quietly = TRUE))
    suppressPackageStartupMessages(tryCatch(library(p, character.only = TRUE),
                                            error = function(e) NULL))
}

# --- 2. Caminhos --------------------------------------------------------------
path_study_root   <- here::here()
path_dictionaries <- here::here("data", "dictionaries")
path_processed    <- here::here("data", "processed")
path_tables       <- here::here("outputs", "tables")
path_figures      <- here::here("outputs", "figures")
path_docs         <- here::here("docs")

# Caminho da base bruta (compartilhada entre projetos):
path_raw_sgs <- here::here("..", "databases", "p1", "05_bacen_scr")

for (p in c(path_dictionaries, path_processed, path_tables, path_figures))
  if (!dir.exists(p)) dir.create(p, recursive = TRUE)

# --- 3. Helpers ---------------------------------------------------------------
log_msg <- function(...) cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ..., "\n")
save_rds <- function(obj, name, folder = path_processed) {
  saveRDS(obj, file.path(folder, name), compress = "xz")
  log_msg("Salvo: ", file.path(folder, name)); invisible(name)
}
read_rds <- function(name, folder = path_processed) {
  path <- file.path(folder, name)
  if (!file.exists(path)) stop("Arquivo nao encontrado: ", path)
  readRDS(path)
}
save_csv <- function(df, name, folder = path_tables) {
  readr::write_excel_csv(df, file.path(folder, name), na = "")
  log_msg("Salvo: ", file.path(folder, name)); invisible(name)
}


# ---- bloco seguinte ----

   ler_serie_json <- function(codigo, nome_arquivo, descricao) {
     path_json <- file.path(path_raw_sgs, nome_arquivo)
     if (!file.exists(path_json)) { log_msg("WARN: arquivo ausente: ", nome_arquivo); return(NULL) }
     raw <- jsonlite::fromJSON(path_json, simplifyDataFrame = TRUE)
     if (!is.data.frame(raw)) { log_msg("WARN: formato inesperado em ", nome_arquivo); return(NULL) }
     tibble::tibble(
       codigo      = as.integer(codigo),
       descricao   = descricao,
       nome_arquivo= nome_arquivo,
       data_chr    = as.character(raw$data),
       valor_chr   = as.character(raw$valor)
     )
   }
   

# ---- bloco seguinte ----

   diag_series <- series_long |>
     dplyr::group_by(codigo, descricao, nome_arquivo) |>
     dplyr::summarise(
       n_obs      = dplyr::n(),
       data_min   = min(data_chr, na.rm = TRUE),   # descoberta dinâmica!
       data_max   = max(data_chr, na.rm = TRUE),
       n_na_valor = sum(is.na(valor_chr) | valor_chr %in% c("null", "")),
       .groups    = "drop")
   

# ---- bloco seguinte ----

   painel <- series_long |>
     dplyr::mutate(
       data      = lubridate::dmy(data_chr),          # DD/MM/YYYY!
       mes       = lubridate::floor_date(data, "month"),
       ano       = lubridate::year(mes),
       valor_num = suppressWarnings(as.numeric(valor_chr))
     ) |> dplyr::filter(!is.na(mes))
   n_na <- sum(is.na(painel$valor_num))
   if (n_na > 0) log_msg("WARN: ", n_na, " observacoes com valor NA")
   

# ---- bloco seguinte ----

# ============================================================================
# 0X_<etapa>_<tema>.R
# <Objetivo do script em uma linha>
# Entradas: <arquivos/painéis esperados>
# Saidas:   data/processed/<saida>.rds ; outputs/tables/<saida>.csv
# ============================================================================
source(here::here("code", "utils", "00_setup.R"))

# --- 1. Entrada ---------------------------------------------------------------
series_long <- read_rds("series_long.rds")

# --- 2. Descoberta dinamica (nunca hardcode) ----------------------------------
meses_disponiveis <- sort(unique(series_long$data_chr))
log_msg("Cobertura declarada pelos dados: ",
        min(series_long$data_chr), " a ", max(series_long$data_chr))

# --- 3. Transformacao tipica --------------------------------------------------
# dmy() para datas, as.numeric() para valores, pivot/padronizacao por tema

# --- 4. QA obrigatoria (secao 7) ----------------------------------------------

# --- 5. Persistencia ----------------------------------------------------------
# save_rds(...); save_csv(...); log_msg("Concluido: 0X_<etapa>_<tema>.R")
