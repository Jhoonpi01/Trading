# Trading Repository

Repositorio personal con código para **TradingView** (Pine Script) y **MetaTrader 5** (MQL5).

---

## Estructura

```
Trading/
├── TradingView/
│   └── Indicators/          ← Scripts Pine Script (.pine)
│
├── MT5/
│   ├── Experts/             ← Expert Advisors (.mq5)
│   │   ├── AsianRange/      ← Variantes del EA de Rango Asiático
│   │   ├── Asesor_Experto.mq5
│   │   ├── PriceAction_MarketStructure.mq5
│   │   ├── EA_DFManipulator_Bot.mq5
│   │   └── EA_DFManipulator_Bot_Optimized.mq5
│   │
│   ├── Indicators/          ← Indicadores compilados de terceros (.ex5)
│   │   ├── ICT_Concepts_Indicator_TFlab.ex5
│   │   ├── LuxAlgo_Adaptive_MACD.ex5
│   │   └── LuxAlgo_Trendlines_With_Breaks.ex5
│   │
│   └── Build/               ← [gitignored] .ex5 compilados desde código fuente
│
└── Curso/                   ← Material de aprendizaje
    ├── Videos/
    ├── PDF/
    └── ...
```

---

## TradingView — Indicadores Pine Script

| Archivo | Descripción |
|---|---|
| `CM_MacD_Ult_MTF.pine` | MACD multi-timeframe (CM) |
| `iFVG_BPR.pine` | Fair Value Gaps inversos + Balance Price Range |
| `Trendlines_with_Breaks_LuxAlgo.pine` | Trendlines con rupturas — LuxAlgo |
| `AIO_MACD_iFVG_Trendlines.pine` | **All-In-One**: combina los 3 indicadores anteriores |

### AIO — Funcionalidades combinadas

| Componente | Comportamiento en overlay |
|---|---|
| **MACD MTF** | Colorea las barras en 4 estados del histograma + flechas ▲▼ en cruce MACD/Señal |
| **iFVG / BPR** | Dibuja líneas de Fair Value Gaps inversos y cajas de Balance Price Range con mitigación |
| **Trendlines** | Líneas de tendencia dinámicas con etiquetas "B" al romper | 

---

## MT5 — Expert Advisors MQL5

### Asesor principal
| Archivo | Descripción |
|---|---|
| `Asesor_Experto.mq5` | EA Rango Asiático completo — versión principal |
| `PriceAction_MarketStructure.mq5` | EA basado en estructura de mercado / Price Action |
| `EA_DFManipulator_Bot.mq5` | Bot DF Manipulator (sesiones, EMA filter, pendientes) |
| `EA_DFManipulator_Bot_Optimized.mq5` | Versión optimizada del DF Manipulator |

### AsianRange/ — Variantes de desarrollo

Todas las variantes operan con la lógica de **Rango Asiático + Sweep** (H2).  
Se diferencian en parámetros clave:

| Archivo | `porcenlote` | `candleEntryDelay` | Características extra |
|---|---|---|---|
| `EA_AsianRange_HistoricalRanges.mq5` | 0.25% | 1 | Rangos históricos, multi-pos, DealInfo |
| `EA_AsianRange_MultiPos_0025pct.mq5` | 0.25% | 1 | Multi-posición, maxCandlesAfterSweep |
| `EA_AsianRange_MultiPos_10pct.mq5` | 10% | 1 | Multi-posición, alto riesgo |
| `EA_AsianRange_Delay2_5pct.mq5` | 5% | 2 | Entrada en 2ª vela post-sweep |
| `EA_AsianRange_Delay1_5pct.mq5` | 5% | 1 | Entrada inmediata post-sweep |
| `EA_AsianRange_AsiaWide_MA100.mq5` | 5% | 1 | Asia 04:00–10:00, filtro MA100 |
| `EA_AsianRange_Base_5pct.mq5` | 5% | 1 | Versión base / sin filtros extra |

---

## MT5 — Indicadores de terceros

| Archivo | Fuente |
|---|---|
| `ICT_Concepts_Indicator_TFlab.ex5` | TFlab |
| `LuxAlgo_Adaptive_MACD.ex5` | LuxAlgo |
| `LuxAlgo_Trendlines_With_Breaks.ex5` | LuxAlgo |

> Los archivos `.ex5` de terceros se incluyen como binarios ya que no se dispone del código fuente.

---

## Notas

- Los archivos `.ex5` compilados **desde código propio** (`MT5/Build/`) están en `.gitignore` y se regeneran compilando en MetaEditor.
- Los archivos Pine Script pasaron de `.txt` → `.pine` para mejor soporte en editores.
