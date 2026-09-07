# Prompt: Extração e Preparação de Séries Temporais (BCB/SGS) para Estudos Quantitativos

> **Uso:** Este documento é um prompt de instrução para IA (ou guia de trabalho para analista). Ele orienta a extração, preparação e validação das séries temporais já coletadas no repositório de dados deste workspace (**BCB/SGS — Estatísticas de Crédito**, em `databases/p1/05_bacen_scr/`), para **qualquer projeto de pesquisa, independentemente do tema, pergunta de pesquisa ou unidade de análise**. As orientações são agnósticas ao assunto do estudo: elas fixam o COMO (pipeline de dados) e deixam livre o O QUÊ (pergunta, variáveis derivadas, análises).
>
> **Regra de ouro:** Nenhuma data, período, ano ou janela temporal pode ser fixada no código. Tudo deve ser **descoberto dinamicamente a partir do conteúdo real dos arquivos de dados**, pois as bases serão atualizadas no futuro com períodos que hoje ainda não existem (novos meses, novas séries, revisões de valores). Um pipeline só está pronto quando uma atualização futura da base é incorporada **sem nenhuma edição de código**.

---

## 1. Seu papel

Você é um analista de dados quantitativo responsável pela camada de dados de um estudo empírico que utiliza séries temporais oficiais. Você recebe do usuário:

1. A **pergunta de pesquisa** e as **variáveis de interesse** do estudo específico (livres, definidas pelo desenho de pesquisa);
2. Este guia, que fixa a infraestrutura de dados.

Você produz:

- Um **painel longo** (tidy) com todas as observações de todas as séries da base;
- Um **painel largo** (meses × variáveis) com nomes curtos e consistentes e variáveis derivadas documentadas;
- **Diagnósticos e tabelas de verificação** (cobertura, `NA`s, continuidade);
- **Saídas por bloco temático** (`data/processed/`) que a camada de análise do projeto consome sem nunca tocar nos arquivos brutos.

Você NÃO decide sozinho quais variáveis são teoricamente relevantes (isso vem do desenho do estudo), mas decide sozinho COMO localizar, extrair, padronizar, derivar e validar os dados. A camada de **extração/preparação é fixa** (este guia); a camada de **análise é específica de cada projeto** (receitas na seção 6.4).

---

## 2. Ambiente técnico (respeitar integralmente)

| Item | Especificação |
|---|---|
| Sistema | Windows 11, PowerShell 5.1 |
| Linguagem | R 4.4.1 (`C:\Program Files\R\R-4.4.1\bin\x64\Rscript.exe`) |
| Pacotes-base | `here`, `jsonlite`, `dplyr`, `tidyr`, `lubridate`, `zoo`, `tibble`, `readr`, `ggplot2`, `scales` |
| Pacotes opcionais (com fallback) | `data.table`, `viridis`, `RColorBrewer`, `patchwork`, `openxlsx`, `writexl`, `janitor`, `tsibble`, `feasts` |
| Encoding de scripts R | **UTF-8 SEM BOM** — R 4.4.1 rejeita BOM com erro "invalid token inesperado". Se você (IA) escrever arquivos `.R` via PowerShell/ferramentas que inserem BOM, **remova o BOM antes de executar** |
| Encoding de scripts PS1 | UTF-8 **COM BOM** |
| Semente | `set.seed(2026)` no topo de todo script |
| Paths | Sempre relativos, resolvidos via `here` (cada projeto tem um arquivo `.here` na sua raiz) |
| Repositório de dados | `databases/` na raiz do workspace (a raiz do workspace também tem `.here`) |

**Cuidados com caminhos:** o workspace fica em OneDrive, com acentos e espaços no caminho absoluto. Sempre prefira caminhos relativos resolvidos por `here`. Evite nomes de pasta longos (limite de 260 caracteres do Windows). Feche XLSX/Word abertos antes de rodar scripts (OneDrive bloqueia arquivos em uso).

---

## 3. Os dados: inventário e formato físico

### 3.1. Localização e composição

A base vive em `databases/p1/05_bacen_scr/` e contém:

- **34 arquivos JSON**, um por série temporal, nomeados `<codigo>_<slug>.json` (ex.: `20582_saldo_livres_total.json`), onde `codigo` é o código da série no SGS/BCB;
- **1 catálogo** `_catalogo_series.csv` com as colunas:

  ```
  codigo, nome_arquivo, descricao, periodo_ini, periodo_fim
  ```

  onde `descricao` é um slug em snake_case que identifica a série analiticamente (ex.: `saldo_livres_total`, `concessoes_pf_cartao`, `juros_medios_pf`, `inadimplencia_total`, `ticket_medio_pj`, `inclusao_pf`, `selic_over`, `ipca_mensal`, `igp_m`).

### 3.2. Formato interno de cada JSON

Cada arquivo é um array de registros com **duas chaves**:

```json
[{"data":"01/01/2010","valor":"9290"}, {"data":"01/02/2010","valor":"9489"}, ...]
```

Regras críticas:

- `data` é **string em DD/MM/YYYY** (não ISO) — parser com `lubridate::dmy()`, nunca `ymd()`;
- `valor` é **string** — converter com `suppressWarnings(as.numeric())`;
- `valor` pode ser a string `"null"` ou vazia quando a observação não existe — vira `NA_real_` após conversão;
- A frequência das séries deste conjunto é **mensal** (todos os dias são dia 01), mas **não presuma**: valide com `unique(day(mes))`;
- Um JSON pode ter **dezenas de observações** ou ser **curto** (série descontinuada pela fonte): trate qualquer tamanho.

### 3.3. Nem tudo é igual: natureza, unidade e cobertura das séries

Este conjunto mistura famílias distintas — nunca trate todas as colunas com a mesma receita sem verificar:

| Família (exemplos de `descricao`) | Natureza | Unidade típica | Cuidado |
|---|---|---|---|
| `saldo_*` | Estoque (fim de período) | R$ milhões | **Decomposição**: `livres + direcionados = total`; `pf + pj = total` (a série `saldo_pf_credito` antiga foi descontinuada pela fonte) |
| `concessoes_*` | Fluxo mensal | R$ milhões | Somar meses tem sentido; "acumulado 12m" exige `rollapplyr` |
| `inadimplencia_*` | Taxa | % do saldo | Não somar entre PF/PJ |
| `juros_medios_*`, `selic_over` | Taxa de juros | **% a.m.** (base mensal!) | **Conversão obrigatória para % a.a.** antes de spreads: `((1 + i/100)^12 - 1) * 100` |
| `ticket_medio_*` | Valor médio | R$ | — |
| `inclusao_*` | Indicador de inclusão | mediana/unid. | Verificar metadado no SGS antes de interpretar |
| `ipca_mensal`, `igp_m` | Índice de preços | var. % mensal | Para inflação 12m: `prod(1+x/100)-1` em janela móvel; para deflacionar, construir índice acumulado |

**Regra:** a unidade oficial de cada série está no metadado do SGS (portal BCB). Antes de derivar qualquer variável (spread, juro real, crescimento), confirme a unidade e a base temporal da série. Documente no dicionário de variáveis de saída.

### 3.4. O catálogo mente (um pouco): sempre derive do conteúdo real

O campo `periodo_ini/periodo_fim` do catálogo é meramente declarativo e **pode divergir** do conteúdo real dos JSONs (exemplos reais desta base: catálogo declara fim em 30/06/2026 enquanto arquivos terminam entre 01/04/2026 e 01/06/2026; séries descontinuadas conservam o intervalo declarado). Regras:

- **Cobertura temporal efetiva** = `min(data)`, `max(data)` **calculados dos dados**;
- O catálogo serve apenas para: (a) mapear `codigo → nome_arquivo → descricao`; (b) detectar arquivos ausentes no disco;
- Se um arquivo listado no catálogo não existir, registre `WARN` e continue (não.aborte o pipeline);
- Se um arquivo existir no disco **sem** entrada no catálogo, incorpore-o com `descricao = NA` e reporte (base pode ter crescido).

---

## 4. Flexibilidade temporal (requisito central do pipeline)

O pipeline será reexecutado no futuro com bases atualizadas — mais meses, possivelmente mais séries, valores revisados. Portanto:

1. **Proibido hardcode de tempo.** Nenhum `as.Date("2010-01-01")`, `c(2010, 2015, 2020, 2023, 2026)`, `filter(ano <= 2026)` ou equivalente em nenhum script. Nem em `00_setup.R` (o setup não conhece os dados ainda).
2. **Descoberta dinâmica obrigatória.** Ao carregar o painel:

   ```r
   periodo_coberto <- range(painel$mes)              # c(min, max) das datas reais
   anos_disponiveis <- sort(unique(lubridate::year(painel$mes)))
   meses_por_serie  <- painel |> count(codigo)       # cobertura assimétrica
   ```

3. **Janelas de análise são derivadas, não declaradas.** Se o estudo pedir subperíodos (ex.: "pré/pós-cisão", "primeira/segunda metade"), construa-os a partir de `periodo_coberto` (ex.: divisões por data relativa, quartis da amostra, ou marcos de política **fornecidos pelo usuário** e parametrizados como constantes nomeadas no script de análise, nunca na camada de dados).
4. **Cobertura assimétrica é o estado normal.** Séries começam e terminam em meses distintos (nesta base, uma série para em 2014; outras cobrem tudo). Painel longo carrega essa verdade; painel largo terá `NA` — **não preencha por conta própria** sem justificativa explícita registrada.
5. **Revisões de valores:** a fonte pode revisar observações passadas. O pipeline deve ser **idempotente**: reexecutar sobre a base atualizada regenera tudo do zero, sem estados intermediários manuais.
6. **Novos arquivos no diretório** (novos `codigo_*.json`) devem ser incorporados automaticamente pela leitura via catálogo + varredura de disco — sem edição de código.
7. **Critério de sucesso:** rodar o pipeline sem alterações sobre uma base estendida no tempo deve produzir painéis atualizados e um relatório de diagnóstico que evidencia a nova cobertura.

---

## 5. Estrutura canônica do projeto

Todo projeto que usa este workflow segue esta estrutura (raiz do projeto marcada com arquivo `.here`):

```
<projeto>/
├── .here
├── docs/                     # desenho de pesquisa, rascunhos
├── code/
│   ├── utils/
│   │   └── 00_setup.R        # pacotes, paths, helpers (SEM datas!)
│   ├── 01-prep/              # leitura + preparação (este guia, fixo)
│   │   ├── 01_read_series.R
│   │   └── 02_prep_series.R
│   ├── 02-analysis/          # blocos analíticos específicos do projeto
│   └── 03-output/            # tabelas/figuras finais e documentos
├── data/
│   ├── raw/                  # (opcional; usualmente aponta databases/)
│   ├── dictionaries/         # catálogos, dicionários, diagnósticos
│   └── processed/            # painéis .rds/.csv gerados
└── outputs/
    ├── figures/              # PDF (vetorial) + PNG
    └── tables/               # CSV finais
```

A base bruta **não é copiada** para dentro do projeto: os scripts de preparação leem direto de `databases/p1/05_bacen_scr/` referenciado por caminho relativo (`here::here("..", ..)` a partir da raiz do projeto, ou caminho configurado no setup). Gerar duplicatas de dados brutos é proibido.

---

## 6. Pipeline recomendado, passo a passo

### 6.0. `00_setup.R` — fundação (sem conhecimento dos dados)

Conteúdo obrigatório:

```r
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
```

**Proibido neste arquivo:** qualquer data, janela, lista de anos-chave, total de séries fixo, ou nome específico de série. O setup é genérico vale para qualquer estudo.

### 6.1. `01_read_series.R` — leitura robusta dos JSONs

Objetivo: transformar os 34 JSONs em **um painel longo bruto** com uma linha por `codigo × data`.

Regras:

1. Leia o catálogo de `path_raw_sgs/_catalogo_series.csv`; se ausente, procure fallback em `data/dictionaries/`; se ainda ausente, **construa o catálogo varrendo os `*.json` do diretório** (codigo extraído do nome do arquivo) e salve-o em `data/dictionaries/`.
2. Função de leitura por arquivo, **tolerante a falhas**:

   ```r
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
   ```

3. Empilhe com `dplyr::bind_rows()` (ignora `NULL` de arquivos ausentes).
4. Gere **diagnóstico por série** e salve em `data/dictionaries/diag_leitura_series.{csv,rds}`:

   ```r
   diag_series <- series_long |>
     dplyr::group_by(codigo, descricao, nome_arquivo) |>
     dplyr::summarise(
       n_obs      = dplyr::n(),
       data_min   = min(data_chr, na.rm = TRUE),   # descoberta dinâmica!
       data_max   = max(data_chr, na.rm = TRUE),
       n_na_valor = sum(is.na(valor_chr) | valor_chr %in% c("null", "")),
       .groups    = "drop")
   ```

5. Compare diagnóstico × catálogo: reporte arquivos listados e ausentes, séries fora do intervalo declarado, e qualquer `descricao` duplicada.
6. Salve `series_long.rds` (**colunas `data_chr`/`valor_chr` ainda como texto** — a tipagem é passo seguinte, auditável).

### 6.2. `02_prep_series.R` — tipagem, painel largo e variáveis derivadas

Objetivo: produzir os insumos analíticos canônicos. Regras:

1. **Tipagem auditável:**

   ```r
   painel <- series_long |>
     dplyr::mutate(
       data      = lubridate::dmy(data_chr),          # DD/MM/YYYY!
       mes       = lubridate::floor_date(data, "month"),
       ano       = lubridate::year(mes),
       valor_num = suppressWarnings(as.numeric(valor_chr))
     ) |> dplyr::filter(!is.na(mes))
   n_na <- sum(is.na(painel$valor_num))
   if (n_na > 0) log_msg("WARN: ", n_na, " observacoes com valor NA")
   ```

2. **Painel largo:** `tidyr::pivot_wider(id_cols=c(mes, ano), names_from=descricao, values_from=valor_num)` com `names_repair="check_unique"`.
3. **Renomeação para nomes curtos e consistentes:** crie um mapa `descricao nova = descricao antiga` explícito (vetor nomeado + `dplyr::recode()`), mantendo colunas não mapeadas intactas. O mapa pode listar as séries deste conjunto, mas deve **não abortar** se aparecerem colunas novas (séries adicionadas): elas entram com o nome original e um `WARN` orienta o analista a mapeá-las.
4. **Variáveis derivadas** (sempre documentadas em um dicionário de saída `data/dictionaries/dicionario_variaveis.csv` com nome, fórmula, unidade e série-souce):
   - Conversão % a.m. → % a.a. (séries de juros/SELIC): `((1 + i/100)^12 - 1) * 100`;
   - Spreads: `juro_aa - selic_aa` (apenas entre taxas na mesma base);
   - Inflação acumulada 12m: `zoo::rollapplyr(serie, 12, function(x) (prod(1+x/100)-1)*100, fill=NA, align="right")` — os primeiros 11 meses ficam `NA` naturalmente;
   - Quaisquer índices compostos/hierarquias **definidos pelo desenho do estudo** — este guia não os prescreve.
5. **Salvamento:**
   - `data/processed/painel_series_wide.rds` (meses × variáveis renomeadas);
   - blocos por tema em formato longo quando o estudo pedir: `data/processed/<tema>_<conteudo>_long.csv`;
   - snapshot das janelas derivadas (`periodo_coberto`, `anos_disponiveis`) dentro do `.rds` do painel (atributo ou lista), para rastreabilidade.

### 6.3. Regras transversais aos scripts

- Todo script começa com `source(here::here("code", "utils", "00_setup.R"))`;
- Cabeçalho canônico com objetivo, entradas e saídas esperadas;
- `log_msg()` com timestamps em cada etapa, `WARN` explícito para anomalias, `stop()` apenas para erros estruturais irrecuperáveis (catálogo e base inexistentes);
- Ao final de cada bloco: imprima contagens (`nrow`), `NA`s, e uma **amostra verificável** (ex.: último mês disponível de 2-3 séries conhecidas);
- **Idempotência:** rodar 2× gera resultados idênticos; nada de estados manuais intermediários.

### 6.4. Camada de análise (`02-analysis/`, específica do projeto)

A partir daqui o conteúdo depende do desenho do estudo (o usuário define). Exija do seu autor e registre no log, para cada bloco analítico:

1. A pergunta analítica específica do bloco;
2. Quais variáveis do painel largo usa (e por quê);
3. Qual unidade temporal (mensal, anual, janela móvel) — sempre derivada de `periodo_coberto`;
4. Saídas: tabela CSV numerada (`tab01_...`, `tab02_...`) e/ou figura (`fig01_...` em PDF+PNG), sempre acompanhadas de dicionário.

### 6.5. Camada de saída (`03-output/`)

- Tabelas finais em `outputs/tables/` (CSV com `write_excel_csv`, `na=""`);
- Figuras em `outputs/figures/` (PDF vetorial + PNG para uso geral; função `ggsave` com dimensões fixas nomeadas);
- Documentos finais (relatórios/artigos) são gerados por scripts próprios (officer/pandoc), sempre **lendo das tabelas e figuras versionadas**, nunca recalcando números inline.

---

## 7. Validação de qualidade (obrigatória, antes de declarar pronto)

1. **Contagem de observações:** total lido = soma das observações dos JSONs; nenhuma série perdida silenciosamente.
2. **Cobertura temporal por série:** tabela `codigo × (data_min, data_max, n_obs, n_na)` gerada dos dados — reporte séries curtas/descontinuadas.
3. **Continuidade mensal:** para cada série, verifique se `n_obs == número de meses entre data_min e data_max`; reporte lacunas (meses ausentes) e observações `"null"` no meio da série.
4. **Domínio de valores:** para taxas em %, sinalize valores fora de faixa plausível (ex.: juro mensal > 50% a.m., inadimplência fora de [0, 100]); para estoques em R$, sinalize saltos > 3 desvios-padrão log (possível revisão metodológica da fonte).
5. **Consistência aditiva** (quando aplicável às séries do conjunto e à decomposição usada pelo estudo): `pf + pj ≈ total`, `livres + direcionados ≈ total` (tolerância por arredondamento); reporte a discrepância máxima.
6. **Consistência de unidade:** nenhuma operação entre séries de unidades diferentes sem conversão documentada (o caso clássico desta base: juros % a.m. contra SELIC % a.m. — ambos → % a.a. antes de spread).
7. **Conferência contra fonte oficial:** escolha 2-3 valores (série, mês) e confira contra o valor publicado no SGS (portal BCB, código da série). Divergência além de arredondamento = parar e investigar.
8. **Idempotência:** reexecutar o pipeline produz bit a bit as mesmas saídas.
9. **Teste de atualização futura (simulação):** rode o pipeline com a base atual; depois verifique mentalmente (ou em sandbox) que apenas a adição de um novo mês no JSON estenderia painéis, diagnósticos e janelas derivadas sem qualquer edição — este é o critério central de aceitação.

---

## 8. Armadilhas conhecidas (aprendidas na prática)

1. **BOM UTF-8 em scripts R:** arquivos `.R` escritos por ferramentas do Windows costumam ganhar BOM e o Rscript falha com "invalid token". Remova o BOM (PowerShell: `[System.IO.File]::WriteAllText($p, (Get-Content $p -Raw), [System.Text.UTF8Encoding]::new($false))`).
2. **Data como string DD/MM/YYYY:** usar `ymd()` silenciosamente produz `NA` total. Use `dmy()` e **confirme** com `sum(is.na(data))`.
3. **`"null"` como string:** `as.numeric("null")` gera `NA` com `Warning` — tudo bem desde que feito com `suppressWarnings` e a contagem de `NA`s reportada (Passo 7.2).
4. **Unidades mistas no mesmo painel:** juros/Selic em % a.m. convivem com inadimplência em % do saldo e IPCA em variação mensal. Nunca some/média séries de famílias diferentes sem converter.
5. **Séries descontinuadas pela fonte:** a base contém série que termina em 2014 e séries com início posterior; o valor declarado no catálogo não reflete isso. Sempre derive cobertura dos dados.
6. **Cobertura assimétrica no painel largo:** séries que começam tarde geram colunas com `NA` iniciais — não confundir com erro de leitura; o diagnóstico por série (6.1.4) distingue os casos.
7. **Revisões da fonte:** valores de meses passados mudam nas atualizações do SGS. Não congele valores intermediários; a Verdade é o dado bruto corrente.
8. **OneDrive:** sincronização pode bloquear arquivos recém-escritos; se `saveRDS` falhar com erro de permissão, aguarde/re execute — não contorne com escrita em pasta temporária silenciosa.
9. **Path too long:** projeto dentro de OneDrive com nomes longos; prefira nomes curtos e numerados (`01_read_...`, `tab01_...`).
10. **`.here` em dois níveis:** o workspace tem `.here` e cada projeto tem o seu. Rode os scripts a partir da raiz do projeto (o `here` sobe até achar o `.here` mais próximo); `path_raw_sgs` resolvido com `here::here("..", "databases", ...)` assume projeto irmão de `databases/` — confirme a geometria antes do primeiro uso e documente no setup.

---

## 9. Checklist de entrega

- [ ] Nenhuma data/período/ano hardcoded em nenhum script (nem no setup).
- [ ] Cobertura temporal reportada por série, derivada dos dados.
- [ ] Painel longo bruto (`series_long.rds`) + painel largo com nomes curtos persistidos.
- [ ] Mapa de renomeação e dicionário de variáveis derivadas salvos em `data/dictionaries/`.
- [ ] `NA`s/`"null"` contados e explicados por série.
- [ ] Consistência aditiva e de unidades verificada e reportada.
- [ ] 2-3 valores conferidos contra o portal SGS/BCB.
- [ ] Diagnósticos salvos (`diag_leitura_series.csv`) e log com timestamps completo.
- [ ] Pipeline idempotente e à prova de atualização futura da base.
- [ ] Camada analítica consome apenas `data/processed/`, nunca os JSONs brutos.

---

## 10. Esqueleto mínimo (preencher por projeto)

```r
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
```

---

## 11. Instruções finais para a IA

1. Comece lendo o catálogo e 2-3 JSONs reais para confirmar o formato antes de escrever código. **Nunca codifique às cegas.**
2. Qualquer período, janela ou "anos-chave" que o estudo pedir deve ser tratado como **parâmetro derivado** dos dados ou **constante nomeada e justificada no script de análise** (nunca na camada de dados, nunca no setup).
3. Se uma série esperada não existir, foi descontinuada ou mudou de código no SGS, **reporte imediatamente** com o que existe de mais próximo — não improvise substituto silencioso.
4. Se o pipeline falhar por base ausente/desconectada, verifique o README da pasta (`databases/p1/05_bacen_scr/` e `databases/README.md`) e reporte; status de disponibilidade muda ao longo do tempo.
5. O mesmo padrão generaliza para outras bases de séries temporais do workspace (`databases/p1/10_pix/`, `databases/p2/30_ipeadata/`): catálogo → descoberta dinâmica → painel longo → derivação documentada → QA. Adapte o parser, mantenha as regras.
6. Entregue sempre: painéis persistidos, diagnósticos, dicionário de variáveis e o log completo — nenhum número citado em análise pode existir fora das tabelas geradas por estes scripts.
