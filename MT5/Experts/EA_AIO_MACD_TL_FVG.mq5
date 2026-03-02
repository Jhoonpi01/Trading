//+------------------------------------------------------------------+
//|                          EA_AIO_MACD_TL_FVG.mq5                 |
//|      Estrategia AIO: MACD MTF + Trendline Breaks + iFVG + ATR SL|
//|                                                                  |
//|  Lógica:                                                         |
//|   1. Trendline dinámica con pendiente ATR/Stdev sobre pivots     |
//|   2. Ruptura de TL + cruce MACD en ventana de N velas            |
//|   3. Entrada: Limit(FVG) / Mercado(cierre) / Mercado(sig.vela)  |
//|   4. SL = ATR Stop Loss Finder (high+ATR / low-ATR)             |
//|   5. BE y TP proporcionales al riesgo real                       |
//|------------------------------------------------------------------||
//|  PARÁMETROS ÓPTIMOS — backtest USDJPY (AIO_Strategy_Backtest)   |
//|    TF  : M30   RR : 4.0   ATR Mult : 1.5   Entry : Limit(FVG)  |
//+------------------------------------------------------------------+
#property copyright "AIO Trade"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input: MACD
input ENUM_TIMEFRAMES InpMacdTF       = PERIOD_CURRENT; // MACD Timeframe
input int             InpFastLen      = 12;              // EMA rápida
input int             InpSlowLen      = 26;              // EMA lenta
input int             InpSignalLen    = 9;               // Señal (SMA)

//--- Input: Trendlines
input int             InpTLLength     = 14;              // Swing Detection Lookback
input double          InpTLMult       = 1.0;             // Slope Multiplier
input string          InpTLMethod     = "Atr";           // Slope Method: Atr/Stdev

//--- Input: FVG
input ENUM_TIMEFRAMES InpFvgTF        = PERIOD_CURRENT;  // FVG Timeframe
input bool            InpUseEntryMid  = false;            // Entrada en mid FVG
input double          InpFvgGapPct    = 0.009;            // % mín gap para FVG

//--- Input: ATR Stop Loss
input int             InpAtrSlLen     = 14;               // ATR Period para SL
input ENUM_MA_METHOD  InpAtrSmoothing = MODE_SMMA;        // ATR Smoothing (RMA = Wilder = SMMA en MQL5)
input double          InpAtrSlMult    = 1.5;              // ATR Multiplier para SL  [óptimo: 1.5]

//--- Input: Señales
input int             InpEntryWindow  = 3;                // Ventana de confirmación (velas)
input double          InpRRRatio      = 4.0;              // Ratio R:R  [óptimo: 4.0]
input double          InpBEMult       = 2.0;              // Multiplicador Break Even
input bool            InpUseBE        = true;             // Activar Break Even
input string          InpEntryType    = "Limit";          // Tipo entrada: Limit / Market / NextOpen  [óptimo: Limit]

//--- Input: Kill Zones (horas UTC)
input bool            InpKZAsia       = true;              // Activar Asia KZ
input int             InpKZAsiaStart  = 20;                // Asia inicio (hora UTC)
input int             InpKZAsiaEnd    = 0;                 // Asia fin (hora UTC)
input bool            InpKZLondon     = true;              // Activar London KZ
input int             InpKZLDNStart   = 2;                 // London inicio (hora UTC)
input int             InpKZLDNEnd     = 5;                 // London fin (hora UTC)
input bool            InpKZNYAM       = true;              // Activar NY AM KZ
input int             InpKZNYAMStart  = 12;                // NY AM inicio (hora UTC)
input int             InpKZNYAMEnd    = 15;                // NY AM fin (hora UTC)
input bool            InpKZNYPM       = false;             // Activar NY PM KZ
input int             InpKZNYPMStart  = 17;                // NY PM inicio (hora UTC)
input int             InpKZNYPMEnd    = 20;                // NY PM fin (hora UTC)

//--- Input: Money Management
input double          InpRiskPct      = 2.0;              // % de riesgo por trade (base)
input double          InpMinRiskPct   = 0.5;              // % riesgo mínimo permitido
input double          InpMaxRiskPct   = 3.0;              // % riesgo máximo permitido
input double          InpCommission   = 0.0;              // Comisión por lote (un lado, divisa cuenta) [PositionSizer]
input ulong           InpMagic        = 202602;           // Magic Number
input int             InpSlippage     = 10;               // Slippage (points)

//--- Input: Debug
input bool            InpDebug        = true;             // Imprimir logs de diagnóstico

//--- Global
CTrade trade;
int    hMacd;
int    hAtr;
int    hAtrSl;

// Buffers de estado
double gTL_upper, gTL_lower, gTL_slope_ph, gTL_slope_pl;
int    gTL_upos, gTL_dnos;
int    gBarsTlDn, gBarsTlUp, gBarsMcDn, gBarsMcUp;
double gLastBullTop, gLastBullBtm, gLastBearTop, gLastBearBtm;
bool   gBEActivatedBuy, gBEActivatedSell;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    hMacd = iMACD(_Symbol, InpMacdTF, InpFastLen, InpSlowLen, InpSignalLen, PRICE_CLOSE);
    hAtr  = iATR(_Symbol, PERIOD_CURRENT, InpTLLength);
    hAtrSl = iATR(_Symbol, PERIOD_CURRENT, InpAtrSlLen);

    if(hMacd == INVALID_HANDLE || hAtr == INVALID_HANDLE || hAtrSl == INVALID_HANDLE)
    {
        Print("Error creando indicadores");
        return INIT_FAILED;
    }

    gTL_upper = 0; gTL_lower = 0;
    gTL_slope_ph = 0; gTL_slope_pl = 0;
    gTL_upos = 0; gTL_dnos = 0;
    gBarsTlDn = 999; gBarsTlUp = 999;
    gBarsMcDn = 999; gBarsMcUp = 999;
    gLastBullTop = 0; gLastBullBtm = 0;
    gLastBearTop = 0; gLastBearBtm = 0;
    gBEActivatedBuy = false; gBEActivatedSell = false;

    Print("EA AIO iniciado — Símbolo: ", _Symbol, "  TF: ", EnumToString(Period()),
          "  EntryType: ", InpEntryType, "  RR: ", InpRRRatio,
          "  KZ Asia: ", InpKZAsia, " (", InpKZAsiaStart, "-", InpKZAsiaEnd,
          ")  London: ", InpKZLondon, " (", InpKZLDNStart, "-", InpKZLDNEnd, ")");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(hMacd  != INVALID_HANDLE) IndicatorRelease(hMacd);
    if(hAtr   != INVALID_HANDLE) IndicatorRelease(hAtr);
    if(hAtrSl != INVALID_HANDLE) IndicatorRelease(hAtrSl);
}

//+------------------------------------------------------------------+
//| Kill Zone check — returns true if current UTC hour is in a KZ     |
//+------------------------------------------------------------------+
bool InRange(int h, int startH, int endH)
{
    if(startH <= endH)
        return (h >= startH && h < endH);
    else  // cruza medianoche (ej. Asia 20→0)
        return (h >= startH || h < endH);
}

bool IsInKillZone()
{
    MqlDateTime dt;
    TimeGMT(dt);
    int h = dt.hour;
    
    if(InpKZAsia   && InRange(h, InpKZAsiaStart, InpKZAsiaEnd))   return true;
    if(InpKZLondon && InRange(h, InpKZLDNStart,  InpKZLDNEnd))    return true;
    if(InpKZNYAM   && InRange(h, InpKZNYAMStart, InpKZNYAMEnd))   return true;
    if(InpKZNYPM   && InRange(h, InpKZNYPMStart, InpKZNYPMEnd))   return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Pivot High/Low detection                                          |
//+------------------------------------------------------------------+
double PivotHigh(int lookback)
{
    int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback*2+1, 1);
    if(idx == lookback + 1)
        return iHigh(_Symbol, PERIOD_CURRENT, lookback + 1);
    return 0;
}

double PivotLow(int lookback)
{
    int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback*2+1, 1);
    if(idx == lookback + 1)
        return iLow(_Symbol, PERIOD_CURRENT, lookback + 1);
    return 0;
}

//+------------------------------------------------------------------+
//| Count open positions with magic                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE posType)
{
    int count = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic)
                if(PositionGetInteger(POSITION_TYPE) == posType)
                    count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Conversión entre pips y precio                                    |
//+------------------------------------------------------------------+
double PipToPrice(double pips)
{
    double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double pipUnit = (digits == 3 || digits == 5) ? point * 10.0 : point;
    return pips * pipUnit;
}

double PriceToPips(double priceDistance)
{
    double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double pipUnit = (digits == 3 || digits == 5) ? point * 10.0 : point;
    if(pipUnit <= 0) return 0;
    return priceDistance / pipUnit;
}

//+------------------------------------------------------------------+
//| Calcula lotes por riesgo en % usando tick value (correcto JPY)   |
//+------------------------------------------------------------------+
double CalcLotsByRisk(double riskPercent, double sl_pips)
{
    if(sl_pips <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    // Clampar riesgo dentro del rango configurado
    riskPercent = MathMax(InpMinRiskPct, MathMin(InpMaxRiskPct, riskPercent));

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (riskPercent / 100.0);
    if(riskMoney <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    // Valor monetario de 1 tick (pérdida) en la divisa de la cuenta — PositionSizer: UnitCost = TICK_VALUE_LOSS
    double tickValueLoss = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
    double tickSize      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pipSize       = PipToPrice(1.0);

    if(tickValueLoss <= 0 || tickSize <= 0 || pipSize <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    // PositionSizer formula: lots = riskMoney / (slPriceDist * UnitCost / TickSize + 2 * commission)
    // slPriceDist = sl_pips * pipSize
    double pipValueLoss  = tickValueLoss * (pipSize / tickSize); // valor de 1 pip (pérdida) en cuenta
    double slValueAcct   = pipValueLoss * sl_pips;               // costo del SL por lote
    double commBothSides = 2.0 * InpCommission;                  // comisión entrada + salida
    double denominator   = slValueAcct + commBothSides;
    if(denominator <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double rawLots = riskMoney / denominator;

    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(step  <= 0) step  = 0.01;
    if(minLot <= 0) minLot = 0.01;
    if(maxLot <= 0) maxLot = 100.0;

    double lots = MathFloor(rawLots / step) * step;
    lots = MathMax(minLot, MathMin(maxLot, lots));

    int digitsVol = (int)MathMax(0.0, MathRound(-MathLog10(step)));
    return NormalizeDouble(lots, digitsVol);
}

//+------------------------------------------------------------------+
//| Detect FVG on current or specified timeframe                      |
//+------------------------------------------------------------------+
void DetectFVG()
{
    double h0  = iHigh(_Symbol, InpFvgTF, 1);
    double l0  = iLow(_Symbol, InpFvgTF, 1);
    double c0  = iClose(_Symbol, InpFvgTF, 1);
    double h2  = iHigh(_Symbol, InpFvgTF, 3);
    double l2  = iLow(_Symbol, InpFvgTF, 3);
    double c1  = iClose(_Symbol, InpFvgTF, 2);

    // Bullish FVG: low[0] > high[2]
    bool isBull = (l0 > h2) && (c1 > h2) && ((l0 - h2) / h2 * 100 > InpFvgGapPct);
    // Bearish FVG: high[0] < low[2]
    bool isBear = (h0 < l2) && (c1 < l2) && ((l2 - h0) / h0 * 100 > InpFvgGapPct);

    if(isBull)
    {
        gLastBullTop = l0;    // top del gap
        gLastBullBtm = h2;    // bottom del gap
    }
    if(isBear)
    {
        gLastBearTop = l2;    // top del gap
        gLastBearBtm = h0;    // bottom del gap
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Solo operar en nueva barra
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBar == lastBar) 
    {
        // Aún así, verificar BE en cada tick
        ManageBreakEven();
        return;
    }
    lastBar = currentBar;
    if(InpDebug) Print("[Nueva barra] ", TimeToString(currentBar));

    // ── Obtener datos MACD ──
    double macdMain[], macdSignal[];
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    if(CopyBuffer(hMacd, 0, 0, 3, macdMain) < 3) return;
    if(CopyBuffer(hMacd, 1, 0, 3, macdSignal) < 3) return;

    bool macdAbove   = macdMain[0] >= macdSignal[0];
    bool macdAboveP  = macdMain[1] >= macdSignal[1];
    bool crossUpNow  = macdAbove && !macdAboveP;
    bool crossDnNow  = !macdAbove && macdAboveP;

    // ── Obtener ATR ──
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if(CopyBuffer(hAtr, 0, 0, 2, atrBuf) < 2) return;

    double atrSlBuf[];
    ArraySetAsSeries(atrSlBuf, true);
    if(CopyBuffer(hAtrSl, 0, 0, 2, atrSlBuf) < 2) return;

    // ── Trendline: Pivot + Slope ──
    double ph = PivotHigh(InpTLLength);
    double pl = PivotLow(InpTLLength);

    double tl_slope = 0;
    if(InpTLMethod == "Atr")
        tl_slope = atrBuf[0] / InpTLLength * InpTLMult;
    else
        tl_slope = atrBuf[0] / InpTLLength * InpTLMult; // fallback

    if(ph > 0)
    {
        gTL_slope_ph = tl_slope;
        gTL_upper    = ph;
        gTL_upos     = 0;
    }
    else
    {
        gTL_upper -= gTL_slope_ph;
        double curClose = iClose(_Symbol, PERIOD_CURRENT, 0);
        if(curClose > gTL_upper - gTL_slope_ph * InpTLLength)
        {
            if(gTL_upos == 0) gTL_upos = 1;
        }
    }

    if(pl > 0)
    {
        gTL_slope_pl = tl_slope;
        gTL_lower    = pl;
        gTL_dnos     = 0;
    }
    else
    {
        gTL_lower += gTL_slope_pl;
        double curClose = iClose(_Symbol, PERIOD_CURRENT, 0);
        if(curClose < gTL_lower + gTL_slope_pl * InpTLLength)
        {
            if(gTL_dnos == 0) gTL_dnos = 1;
        }
    }

    // ── Detectar rupturas de TL ──
    static int prevUpos = 0, prevDnos = 0;
    bool tlBreakUp = (gTL_upos > prevUpos);
    bool tlBreakDn = (gTL_dnos > prevDnos);
    prevUpos = gTL_upos;
    prevDnos = gTL_dnos;

    // ── Contadores ──
    gBarsTlDn = tlBreakDn ? 0 : MathMin(gBarsTlDn + 1, 999);
    gBarsTlUp = tlBreakUp ? 0 : MathMin(gBarsTlUp + 1, 999);
    gBarsMcDn = crossDnNow ? 0 : MathMin(gBarsMcDn + 1, 999);
    gBarsMcUp = crossUpNow ? 0 : MathMin(gBarsMcUp + 1, 999);

    // ── Detectar FVG ──
    DetectFVG();

    // ── Señales de confluencia ──
    bool sellSig = (tlBreakDn && gBarsMcDn <= InpEntryWindow) ||
                   (crossDnNow && gBarsTlDn <= InpEntryWindow && gBarsTlDn > 0);
    bool buySig  = (tlBreakUp && gBarsMcUp <= InpEntryWindow) ||
                   (crossUpNow && gBarsTlUp <= InpEntryWindow && gBarsTlUp > 0);

    if(InpDebug)
    {
        MqlDateTime dbgDt; TimeGMT(dbgDt);
        Print("[DEBUG] UTC=", dbgDt.hour, ":", dbgDt.min,
              "  InKZ=", IsInKillZone(),
              "  macdAbove=", macdAbove, "  crossUp=", crossUpNow, "  crossDn=", crossDnNow,
              "  tlBreakUp=", tlBreakUp, "  tlBreakDn=", tlBreakDn,
              "  barsTlUp=", gBarsTlUp, "  barsTlDn=", gBarsTlDn,
              "  barsMcUp=", gBarsMcUp, "  barsMcDn=", gBarsMcDn,
              "  buySig=", buySig, "  sellSig=", sellSig,
              "  FVGbull=[", gLastBullBtm, "-", gLastBullTop,
              "]  FVGbear=[", gLastBearBtm, "-", gLastBearTop, "]");
    }

    // ── ATR SL Finder ──
    double curHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
    double curLow  = iLow(_Symbol, PERIOD_CURRENT, 0);
    double atrSlVal = atrSlBuf[0] * InpAtrSlMult;
    double shortSL  = curHigh + atrSlVal;
    double longSL   = curLow - atrSlVal;

    // ── Filtro Kill Zone ──
    if(!IsInKillZone())
    {
        // Fuera de Kill Zone: no abrir posiciones nuevas
        ManageBreakEven();  // pero seguir gestionando posiciones abiertas
        return;
    }

    // ── Ejecutar SELL ──
    if(sellSig && CountPositions(POSITION_TYPE_SELL) == 0 && CountPositions(POSITION_TYPE_BUY) == 0)
    {
        double entryPx;
        if(InpEntryType == "Limit" && gLastBearBtm > 0)
            entryPx = InpUseEntryMid ? (gLastBearTop + gLastBearBtm) / 2.0 : gLastBearBtm;
        else
            entryPx = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Para Limit(FVG): anclar SL al entry del FVG para garantizar SL > entryPx
        double sl;
        if(InpEntryType == "Limit" && gLastBearBtm > 0)
            sl = entryPx + atrSlBuf[0] * InpAtrSlMult;
        else
            sl = shortSL;

        // Validación: SL debe estar por ENCIMA de la entrada (SELL)
        if(sl <= entryPx)
        {
            if(InpDebug) Print("[SELL SKIP] SL=", sl, " <= Entry=", entryPx, " — stops inválidos");
            goto skip_sell;
        }

        double risk    = MathAbs(sl - entryPx);
        if(risk <= 0) goto skip_sell;
        double sl_pips = PriceToPips(risk);
        double tp      = entryPx - risk * InpRRRatio;
        double lots    = CalcLotsByRisk(InpRiskPct, sl_pips);

        // Normalizar precios
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        entryPx = NormalizeDouble(entryPx, digits);
        sl      = NormalizeDouble(sl, digits);
        tp      = NormalizeDouble(tp, digits);

        if(InpEntryType == "Limit" && gLastBearBtm > 0)
            trade.SellLimit(lots, entryPx, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "AIO SELL");
        else
            trade.Sell(lots, _Symbol, 0, sl, tp, "AIO SELL MKT");

        gBEActivatedSell = false;
        Print("SELL signal: Entry=", entryPx, " SL=", sl, " TP=", tp, " Lots=", lots, " SL_pips=", sl_pips);
    }
    skip_sell:;

    // ── Ejecutar BUY ──
    if(buySig && CountPositions(POSITION_TYPE_BUY) == 0 && CountPositions(POSITION_TYPE_SELL) == 0)
    {
        double entryPx;
        if(InpEntryType == "Limit" && gLastBullTop > 0)
            entryPx = InpUseEntryMid ? (gLastBullTop + gLastBullBtm) / 2.0 : gLastBullTop;
        else
            entryPx = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Para Limit(FVG): anclar SL al entry del FVG para garantizar SL < entryPx
        double sl;
        if(InpEntryType == "Limit" && gLastBullTop > 0)
            sl = entryPx - atrSlBuf[0] * InpAtrSlMult;
        else
            sl = longSL;

        // Validación: SL debe estar por DEBAJO de la entrada (BUY)
        if(sl >= entryPx)
        {
            if(InpDebug) Print("[BUY SKIP] SL=", sl, " >= Entry=", entryPx, " — stops inválidos");
            return;
        }

        double risk    = MathAbs(entryPx - sl);
        if(risk <= 0) return;
        double sl_pips = PriceToPips(risk);
        double tp      = entryPx + risk * InpRRRatio;
        double lots    = CalcLotsByRisk(InpRiskPct, sl_pips);

        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        entryPx = NormalizeDouble(entryPx, digits);
        sl      = NormalizeDouble(sl, digits);
        tp      = NormalizeDouble(tp, digits);

        if(InpEntryType == "Limit" && gLastBullTop > 0)
            trade.BuyLimit(lots, entryPx, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "AIO BUY");
        else
            trade.Buy(lots, _Symbol, 0, sl, tp, "AIO BUY MKT");

        gBEActivatedBuy = false;
        Print("BUY signal: Entry=", entryPx, " SL=", sl, " TP=", tp, " Lots=", lots, " SL_pips=", sl_pips);
    }
}

//+------------------------------------------------------------------+
//| Manage Break Even on every tick                                   |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
    if(!InpUseBE) return;

    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
        double curSL  = PositionGetDouble(POSITION_SL);
        double curTP  = PositionGetDouble(POSITION_TP);
        double risk   = MathAbs(openPx - curSL);
        double beTarget = 0;

        if(posType == POSITION_TYPE_BUY)
        {
            beTarget = openPx + risk * InpBEMult;
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(bid >= beTarget && curSL < openPx)
            {
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                double newSL = NormalizeDouble(openPx + SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point, digits);
                trade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, curTP);
                Print("BUY BE activated: SL moved to ", newSL);
            }
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            beTarget = openPx - risk * InpBEMult;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(ask <= beTarget && (curSL > openPx || curSL == 0))
            {
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                double newSL = NormalizeDouble(openPx - SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point, digits);
                trade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, curTP);
                Print("SELL BE activated: SL moved to ", newSL);
            }
        }
    }
}
//+------------------------------------------------------------------+
