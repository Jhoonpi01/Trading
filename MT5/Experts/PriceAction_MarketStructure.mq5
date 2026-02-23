//+------------------------------------------------------------------+
//|                                   PriceAction_MarketStructure.mq5 |
//|                     Basado en la lógica de estructura de mercado  |
//|                          Transcripción de estrategia Price Action |
//+------------------------------------------------------------------+
#property copyright "Trading EA - Price Action Structure"
#property version   "1.00"
#property description "EA basado en estructura de mercado y Price Action"
#property description "- Break of Structure (BOS)"
#property description "- Change of Character (ChoCH)"  
#property description "- Mínimo/Máximo: último extremo antes de la ruptura"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS - Configuración Principal                                  |
//+------------------------------------------------------------------+
input group "=== CONFIGURACIÓN DE TEMPORALIDAD ==="
input ENUM_TIMEFRAMES TradingTimeframe = PERIOD_H1;  // Temporalidad de operación

input group "=== GESTIÓN DE RIESGO ==="
input double RiskPercent = 1.0;           // % de riesgo por operación
input double RiskRewardRatio = 2.0;       // Ratio Riesgo:Beneficio
input bool UseFixedSL = false;            // Usar SL fijo (en pips)
input int FixedSLPips = 50;               // SL fijo en pips (si UseFixedSL=true)

input group "=== CONFIGURACIÓN DE ENTRADA ==="
input bool EnterOnBreakout = true;        // Entrar al romper estructura
input bool WaitForPullback = false;       // Esperar pullback después de ruptura
input int PullbackBars = 3;               // Velas máx para esperar pullback
input int MinBarsForSwing = 2;            // Velas mínimas para confirmar swing

input group "=== GESTIÓN DE POSICIONES ==="
input bool UseBreakeven = true;           // Mover SL a breakeven
input double BreakevenRR = 1.0;           // R:R para mover a breakeven
input bool UseTrailingStop = true;        // Usar trailing stop por estructura
input bool AllowMultiplePositions = false; // Permitir múltiples posiciones

input group "=== FILTROS ==="
input bool TradeLongOnly = false;         // Solo operar largos
input bool TradeShortOnly = false;        // Solo operar cortos
input int MinSwingDistancePips = 10;      // Distancia mínima del swing (pips)
input int MaxSwingDistancePips = 500;     // Distancia máxima del swing (pips)

input group "=== HORARIOS (Hora del servidor) ==="
input bool UseTimeFilter = false;         // Usar filtro de tiempo
input int TradingStartHour = 8;           // Hora de inicio de trading
input int TradingEndHour = 20;            // Hora de fin de trading

input group "=== VISUALIZACIÓN ==="
input bool ShowStructureLines = true;     // Mostrar líneas de estructura
input bool ShowSwingPoints = true;        // Mostrar puntos swing
input bool ShowTradeLabels = true;        // Mostrar etiquetas de trades
input color BullishColor = clrLime;       // Color para alcista
input color BearishColor = clrRed;        // Color para bajista
input color NeutralColor = clrYellow;     // Color para neutral

input group "=== DEBUG ==="
input bool EnableDebugMode = false;       // Mostrar mensajes de debug
input int MagicNumber = 888888;           // Magic Number del EA

//+------------------------------------------------------------------+
//| ESTRUCTURAS DE DATOS                                              |
//+------------------------------------------------------------------+

// Estado de la estructura de mercado
enum ENUM_MARKET_STRUCTURE
{
   STRUCTURE_BULLISH,    // Estructura Alcista
   STRUCTURE_BEARISH,    // Estructura Bajista  
   STRUCTURE_NEUTRAL     // Estructura Neutral (después de ChoCH, antes de confirmación)
};

// Tipo de evento de estructura
enum ENUM_STRUCTURE_EVENT
{
   EVENT_NONE,           // Sin evento
   EVENT_BOS_BULLISH,    // Break of Structure Alcista (nuevo máximo)
   EVENT_BOS_BEARISH,    // Break of Structure Bajista (nuevo mínimo)
   EVENT_CHOCH_UP,       // Change of Character hacia arriba
   EVENT_CHOCH_DOWN      // Change of Character hacia abajo
};

// Estructura para almacenar un punto swing
struct SwingPoint
{
   double price;         // Precio del swing
   datetime time;        // Tiempo del swing
   int barIndex;         // Índice de la vela
   bool isHigh;          // true = swing high, false = swing low
   bool isValid;         // Si el swing es válido/activo
};

// Estructura para gestión del trade
struct TradeInfo
{
   ulong ticket;         // Ticket de la posición
   double entryPrice;    // Precio de entrada
   double stopLoss;      // Stop Loss inicial
   double takeProfit;    // Take Profit
   double swingLevel;    // Nivel del swing para trailing
   bool isLong;          // true = compra, false = venta
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade trade;

// Estado de la estructura de mercado
ENUM_MARKET_STRUCTURE currentStructure = STRUCTURE_NEUTRAL;
ENUM_STRUCTURE_EVENT lastEvent = EVENT_NONE;

// Arrays de swings
SwingPoint swingHighs[];
SwingPoint swingLows[];

// Último swing válido (para SL)
SwingPoint lastValidSwingHigh;
SwingPoint lastValidSwingLow;

// Niveles de ruptura activos
double bullishBreakLevel = 0;    // Nivel a romper para BOS alcista
double bearishBreakLevel = 0;    // Nivel a romper para BOS bajista

// Control de tiempo
datetime lastBarTime = 0;

// Trade activo
TradeInfo activeTrade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar el objeto de trading
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Inicializar arrays
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);
   
   // Inicializar último swing
   ZeroMemory(lastValidSwingHigh);
   ZeroMemory(lastValidSwingLow);
   ZeroMemory(activeTrade);
   
   // Inicializar estructura como neutral
   currentStructure = STRUCTURE_NEUTRAL;
   
   Print("═══════════════════════════════════════════════════════════");
   Print("   PRICE ACTION - MARKET STRUCTURE EA INICIADO");
   Print("═══════════════════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: ", EnumToString(TradingTimeframe));
   Print("Riesgo por trade: ", RiskPercent, "%");
   Print("Risk:Reward: 1:", RiskRewardRatio);
   Print("═══════════════════════════════════════════════════════════");
   
   // Cargar estructura histórica
   LoadHistoricalStructure();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Limpiar objetos visuales
   if(ShowStructureLines || ShowSwingPoints || ShowTradeLabels)
   {
      ObjectsDeleteAll(0, "PA_");
   }
   
   Print("PRICE ACTION EA DETENIDO");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva vela
   datetime currentBarTime = iTime(_Symbol, TradingTimeframe, 0);
   if(currentBarTime == lastBarTime)
   {
      // Gestionar trades existentes (puede hacerse en cada tick)
      ManageOpenPositions();
      return;
   }
   
   lastBarTime = currentBarTime;
   
   // Verificar filtro de tiempo
   if(UseTimeFilter && !IsWithinTradingHours())
      return;
   
   // Actualizar estructura de mercado
   UpdateMarketStructure();
   
   // Detectar señales de trading
   CheckForTradeSignals();
   
   // Gestionar posiciones abiertas
   ManageOpenPositions();
   
   // Debug
   if(EnableDebugMode)
   {
      PrintStructureStatus();
   }
}

//+------------------------------------------------------------------+
//| Cargar estructura histórica inicial                               |
//+------------------------------------------------------------------+
void LoadHistoricalStructure()
{
   Print("Cargando estructura histórica...");
   
   // Analizar las últimas 200 velas para establecer estructura inicial
   int barsToAnalyze = 200;
   
   for(int i = barsToAnalyze; i >= 1; i--)
   {
      AnalyzeBarForSwing(i);
   }
   
   // Determinar estructura inicial
   DetermineInitialStructure();
   
   Print("Estructura inicial: ", GetStructureName(currentStructure));
   Print("Swing Highs encontrados: ", ArraySize(swingHighs));
   Print("Swing Lows encontrados: ", ArraySize(swingLows));
}

//+------------------------------------------------------------------+
//| Analizar una vela para detectar swing point                       |
//+------------------------------------------------------------------+
void AnalyzeBarForSwing(int barIndex)
{
   // Necesitamos al menos MinBarsForSwing velas a cada lado
   if(barIndex < MinBarsForSwing)
      return;
   
   double currentHigh = iHigh(_Symbol, TradingTimeframe, barIndex);
   double currentLow = iLow(_Symbol, TradingTimeframe, barIndex);
   datetime currentTime = iTime(_Symbol, TradingTimeframe, barIndex);
   
   // Detectar Swing High: Mínimo de la vela actual es menor que el mínimo de la vela anterior
   // Según la transcripción: "un mínimo es cuando una vela tiene su bajo menor que el mínimo anterior"
   bool isSwingLow = false;
   bool isSwingHigh = false;
   
   // Para Swing Low: el mínimo actual es menor que el mínimo anterior
   double prevLow = iLow(_Symbol, TradingTimeframe, barIndex + 1);
   if(currentLow < prevLow)
   {
      // Verificar que las velas siguientes no rompieron este mínimo
      bool confirmed = true;
      for(int i = barIndex - 1; i >= MathMax(0, barIndex - MinBarsForSwing); i--)
      {
         if(iLow(_Symbol, TradingTimeframe, i) < currentLow)
         {
            confirmed = false;
            break;
         }
      }
      
      if(confirmed)
         isSwingLow = true;
   }
   
   // Para Swing High: el máximo actual es mayor que el máximo anterior
   double prevHigh = iHigh(_Symbol, TradingTimeframe, barIndex + 1);
   if(currentHigh > prevHigh)
   {
      // Verificar que las velas siguientes no rompieron este máximo
      bool confirmed = true;
      for(int i = barIndex - 1; i >= MathMax(0, barIndex - MinBarsForSwing); i--)
      {
         if(iHigh(_Symbol, TradingTimeframe, i) > currentHigh)
         {
            confirmed = false;
            break;
         }
      }
      
      if(confirmed)
         isSwingHigh = true;
   }
   
   // Agregar swing low si se encontró
   if(isSwingLow)
   {
      SwingPoint newSwing;
      newSwing.price = currentLow;
      newSwing.time = currentTime;
      newSwing.barIndex = barIndex;
      newSwing.isHigh = false;
      newSwing.isValid = true;
      
      int size = ArraySize(swingLows);
      ArrayResize(swingLows, size + 1);
      swingLows[size] = newSwing;
      
      // Dibujar si está habilitado
      if(ShowSwingPoints)
         DrawSwingPoint(newSwing, false);
   }
   
   // Agregar swing high si se encontró
   if(isSwingHigh)
   {
      SwingPoint newSwing;
      newSwing.price = currentHigh;
      newSwing.time = currentTime;
      newSwing.barIndex = barIndex;
      newSwing.isHigh = true;
      newSwing.isValid = true;
      
      int size = ArraySize(swingHighs);
      ArrayResize(swingHighs, size + 1);
      swingHighs[size] = newSwing;
      
      // Dibujar si está habilitado
      if(ShowSwingPoints)
         DrawSwingPoint(newSwing, true);
   }
}

//+------------------------------------------------------------------+
//| Determinar estructura inicial basada en swings encontrados        |
//+------------------------------------------------------------------+
void DetermineInitialStructure()
{
   int highCount = ArraySize(swingHighs);
   int lowCount = ArraySize(swingLows);
   
   if(highCount < 2 || lowCount < 2)
   {
      currentStructure = STRUCTURE_NEUTRAL;
      return;
   }
   
   // Analizar los últimos swings
   // Higher Highs + Higher Lows = Alcista
   // Lower Highs + Lower Lows = Bajista
   
   SwingPoint lastHigh = swingHighs[highCount - 1];
   SwingPoint prevHigh = swingHighs[highCount - 2];
   SwingPoint lastLow = swingLows[lowCount - 1];
   SwingPoint prevLow = swingLows[lowCount - 2];
   
   bool higherHighs = lastHigh.price > prevHigh.price;
   bool higherLows = lastLow.price > prevLow.price;
   bool lowerHighs = lastHigh.price < prevHigh.price;
   bool lowerLows = lastLow.price < prevLow.price;
   
   if(higherHighs && higherLows)
   {
      currentStructure = STRUCTURE_BULLISH;
      // El nivel de ruptura bajista es el último mínimo válido
      bearishBreakLevel = lastLow.price;
      lastValidSwingLow = lastLow;
   }
   else if(lowerHighs && lowerLows)
   {
      currentStructure = STRUCTURE_BEARISH;
      // El nivel de ruptura alcista es el último máximo válido
      bullishBreakLevel = lastHigh.price;
      lastValidSwingHigh = lastHigh;
   }
   else
   {
      currentStructure = STRUCTURE_NEUTRAL;
   }
   
   // Establecer niveles de ruptura
   UpdateBreakLevels();
}

//+------------------------------------------------------------------+
//| Actualizar estructura de mercado                                  |
//+------------------------------------------------------------------+
void UpdateMarketStructure()
{
   // Analizar la vela cerrada más reciente (índice 1)
   AnalyzeBarForSwing(1);
   
   // Verificar rupturas de estructura
   double currentPrice = iClose(_Symbol, TradingTimeframe, 1);
   double currentHigh = iHigh(_Symbol, TradingTimeframe, 1);
   double currentLow = iLow(_Symbol, TradingTimeframe, 1);
   
   ENUM_STRUCTURE_EVENT newEvent = EVENT_NONE;
   
   // En estructura ALCISTA
   if(currentStructure == STRUCTURE_BULLISH)
   {
      // Verificar BOS alcista (nuevo máximo)
      if(bullishBreakLevel > 0 && currentHigh > bullishBreakLevel)
      {
         newEvent = EVENT_BOS_BULLISH;
         OnBreakOfStructure(true);
      }
      // Verificar ChoCH (rompe mínimo en tendencia alcista)
      else if(bearishBreakLevel > 0 && currentLow < bearishBreakLevel)
      {
         newEvent = EVENT_CHOCH_DOWN;
         OnChangeOfCharacter(false);
      }
   }
   // En estructura BAJISTA
   else if(currentStructure == STRUCTURE_BEARISH)
   {
      // Verificar BOS bajista (nuevo mínimo)
      if(bearishBreakLevel > 0 && currentLow < bearishBreakLevel)
      {
         newEvent = EVENT_BOS_BEARISH;
         OnBreakOfStructure(false);
      }
      // Verificar ChoCH (rompe máximo en tendencia bajista)
      else if(bullishBreakLevel > 0 && currentHigh > bullishBreakLevel)
      {
         newEvent = EVENT_CHOCH_UP;
         OnChangeOfCharacter(true);
      }
   }
   // En estructura NEUTRAL
   else
   {
      // Esperando confirmación de nueva tendencia
      // Se confirma bajista cuando hace un nuevo mínimo
      if(bearishBreakLevel > 0 && currentLow < bearishBreakLevel)
      {
         newEvent = EVENT_BOS_BEARISH;
         currentStructure = STRUCTURE_BEARISH;
         Print("⬇️ ESTRUCTURA BAJISTA CONFIRMADA");
         
         if(ShowStructureLines)
            DrawStructureLine(bearishBreakLevel, false);
      }
      // Se confirma alcista cuando hace un nuevo máximo
      else if(bullishBreakLevel > 0 && currentHigh > bullishBreakLevel)
      {
         newEvent = EVENT_BOS_BULLISH;
         currentStructure = STRUCTURE_BULLISH;
         Print("⬆️ ESTRUCTURA ALCISTA CONFIRMADA");
         
         if(ShowStructureLines)
            DrawStructureLine(bullishBreakLevel, true);
      }
   }
   
   if(newEvent != EVENT_NONE)
   {
      lastEvent = newEvent;
      UpdateBreakLevels();
   }
}

//+------------------------------------------------------------------+
//| Evento: Break of Structure                                        |
//+------------------------------------------------------------------+
void OnBreakOfStructure(bool isBullish)
{
   datetime currentTime = iTime(_Symbol, TradingTimeframe, 1);
   double breakPrice = isBullish ? iHigh(_Symbol, TradingTimeframe, 1) : iLow(_Symbol, TradingTimeframe, 1);
   
   Print(isBullish ? "⬆️ BOS ALCISTA" : "⬇️ BOS BAJISTA", 
         " | Precio: ", breakPrice, 
         " | Tiempo: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
   
   // Actualizar el swing válido para SL
   // "El último mínimo menor que mínimo antes de la ruptura"
   if(isBullish)
   {
      // Para BOS alcista, el SL es el último swing low antes de la ruptura
      lastValidSwingLow = GetLastSwingBeforeTime(false, currentTime);
   }
   else
   {
      // Para BOS bajista, el SL es el último swing high antes de la ruptura
      lastValidSwingHigh = GetLastSwingBeforeTime(true, currentTime);
   }
   
   if(ShowStructureLines)
   {
      DrawStructureLine(breakPrice, isBullish);
   }
}

//+------------------------------------------------------------------+
//| Evento: Change of Character                                       |
//+------------------------------------------------------------------+
void OnChangeOfCharacter(bool towardsBullish)
{
   datetime currentTime = iTime(_Symbol, TradingTimeframe, 1);
   double breakPrice = towardsBullish ? iHigh(_Symbol, TradingTimeframe, 1) : iLow(_Symbol, TradingTimeframe, 1);
   
   Print(towardsBullish ? "🔄 CHOCH HACIA ARRIBA" : "🔄 CHOCH HACIA ABAJO", 
         " | Precio: ", breakPrice, 
         " | Tiempo: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
   
   // Cambiar a estructura neutral (según transcripción: "no estamos bajistas todavía, estamos neutrales")
   currentStructure = STRUCTURE_NEUTRAL;
   
   // Actualizar niveles de ruptura para la nueva potencial tendencia
   UpdateBreakLevels();
   
   if(ShowStructureLines)
   {
      DrawChochLine(breakPrice, towardsBullish);
   }
}

//+------------------------------------------------------------------+
//| Actualizar niveles de ruptura                                     |
//+------------------------------------------------------------------+
void UpdateBreakLevels()
{
   int highCount = ArraySize(swingHighs);
   int lowCount = ArraySize(swingLows);
   
   if(highCount > 0)
   {
      // El nivel de ruptura alcista es el último swing high
      bullishBreakLevel = swingHighs[highCount - 1].price;
      lastValidSwingHigh = swingHighs[highCount - 1];
   }
   
   if(lowCount > 0)
   {
      // El nivel de ruptura bajista es el último swing low
      bearishBreakLevel = swingLows[lowCount - 1].price;
      lastValidSwingLow = swingLows[lowCount - 1];
   }
}

//+------------------------------------------------------------------+
//| Obtener último swing antes de un tiempo específico                |
//+------------------------------------------------------------------+
SwingPoint GetLastSwingBeforeTime(bool isHigh, datetime beforeTime)
{
   SwingPoint result;
   ZeroMemory(result);
   
   if(isHigh)
   {
      for(int i = ArraySize(swingHighs) - 1; i >= 0; i--)
      {
         if(swingHighs[i].time < beforeTime)
         {
            result = swingHighs[i];
            break;
         }
      }
   }
   else
   {
      for(int i = ArraySize(swingLows) - 1; i >= 0; i--)
      {
         if(swingLows[i].time < beforeTime)
         {
            result = swingLows[i];
            break;
         }
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Verificar señales de trading                                      |
//+------------------------------------------------------------------+
void CheckForTradeSignals()
{
   // Verificar si ya hay posición abierta
   if(!AllowMultiplePositions && PositionSelect(_Symbol))
      return;
   
   // Solo operar si hay un evento de estructura reciente
   if(lastEvent == EVENT_NONE)
      return;
   
   // Verificar filtros de dirección
   if(TradeLongOnly && (lastEvent == EVENT_BOS_BEARISH || lastEvent == EVENT_CHOCH_DOWN))
      return;
   if(TradeShortOnly && (lastEvent == EVENT_BOS_BULLISH || lastEvent == EVENT_CHOCH_UP))
      return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // SEÑAL LONG: BOS alcista en estructura alcista
   if(lastEvent == EVENT_BOS_BULLISH && currentStructure == STRUCTURE_BULLISH)
   {
      if(EnterOnBreakout)
      {
         ExecuteLongTrade();
      }
   }
   // SEÑAL SHORT: BOS bajista en estructura bajista  
   else if(lastEvent == EVENT_BOS_BEARISH && currentStructure == STRUCTURE_BEARISH)
   {
      if(EnterOnBreakout)
      {
         ExecuteShortTrade();
      }
   }
   
   // Resetear el evento después de procesarlo
   lastEvent = EVENT_NONE;
}

//+------------------------------------------------------------------+
//| Ejecutar trade largo                                              |
//+------------------------------------------------------------------+
void ExecuteLongTrade()
{
   // Calcular SL: debajo del último swing low válido
   double stopLoss;
   
   if(UseFixedSL)
   {
      stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - FixedSLPips * _Point * 10;
   }
   else
   {
      if(!lastValidSwingLow.isValid || lastValidSwingLow.price <= 0)
      {
         Print("❌ No hay swing low válido para SL");
         return;
      }
      
      // SL debajo del último mínimo + buffer
      double buffer = 10 * _Point;
      stopLoss = lastValidSwingLow.price - buffer;
   }
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double riskDistance = entryPrice - stopLoss;
   
   // Verificar distancia mínima y máxima
   double riskPips = riskDistance / _Point / 10;
   if(riskPips < MinSwingDistancePips || riskPips > MaxSwingDistancePips)
   {
      Print("❌ Distancia de SL fuera de rango: ", riskPips, " pips");
      return;
   }
   
   // Calcular TP basado en R:R
   double takeProfit = entryPrice + (riskDistance * RiskRewardRatio);
   
   // Calcular tamaño de lote
   double lotSize = CalculateLotSize(riskDistance);
   
   // Ejecutar la orden
   if(trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "PA_Long_BOS"))
   {
      Print("✅ LONG EJECUTADO | Entry: ", entryPrice, " | SL: ", stopLoss, " | TP: ", takeProfit);
      
      // Guardar info del trade
      activeTrade.ticket = trade.ResultOrder();
      activeTrade.entryPrice = entryPrice;
      activeTrade.stopLoss = stopLoss;
      activeTrade.takeProfit = takeProfit;
      activeTrade.swingLevel = lastValidSwingLow.price;
      activeTrade.isLong = true;
      
      if(ShowTradeLabels)
         DrawTradeLabel(entryPrice, true);
   }
   else
   {
      Print("❌ Error al ejecutar LONG: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Ejecutar trade corto                                              |
//+------------------------------------------------------------------+
void ExecuteShortTrade()
{
   // Calcular SL: arriba del último swing high válido
   double stopLoss;
   
   if(UseFixedSL)
   {
      stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) + FixedSLPips * _Point * 10;
   }
   else
   {
      if(!lastValidSwingHigh.isValid || lastValidSwingHigh.price <= 0)
      {
         Print("❌ No hay swing high válido para SL");
         return;
      }
      
      // SL arriba del último máximo + buffer
      double buffer = 10 * _Point;
      stopLoss = lastValidSwingHigh.price + buffer;
   }
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double riskDistance = stopLoss - entryPrice;
   
   // Verificar distancia mínima y máxima
   double riskPips = riskDistance / _Point / 10;
   if(riskPips < MinSwingDistancePips || riskPips > MaxSwingDistancePips)
   {
      Print("❌ Distancia de SL fuera de rango: ", riskPips, " pips");
      return;
   }
   
   // Calcular TP basado en R:R
   double takeProfit = entryPrice - (riskDistance * RiskRewardRatio);
   
   // Calcular tamaño de lote
   double lotSize = CalculateLotSize(riskDistance);
   
   // Ejecutar la orden
   if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "PA_Short_BOS"))
   {
      Print("✅ SHORT EJECUTADO | Entry: ", entryPrice, " | SL: ", stopLoss, " | TP: ", takeProfit);
      
      // Guardar info del trade
      activeTrade.ticket = trade.ResultOrder();
      activeTrade.entryPrice = entryPrice;
      activeTrade.stopLoss = stopLoss;
      activeTrade.takeProfit = takeProfit;
      activeTrade.swingLevel = lastValidSwingHigh.price;
      activeTrade.isLong = false;
      
      if(ShowTradeLabels)
         DrawTradeLabel(entryPrice, false);
   }
   else
   {
      Print("❌ Error al ejecutar SHORT: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote basado en riesgo                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskDistance)
{
   double accountRisk = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double valuePerPip = tickValue / tickSize;
   double riskPerLot = riskDistance / tickSize * valuePerPip;
   
   double lotSize = accountRisk / riskPerLot;
   
   // Ajustar a límites del broker
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathMax(minLot, MathMin(lotSize, maxLot));
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Gestionar posiciones abiertas                                     |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double takeProfit = PositionGetDouble(POSITION_TP);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         double currentPrice = posType == POSITION_TYPE_BUY ? 
                               SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                               SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         double riskDistance = MathAbs(entryPrice - currentSL);
         double currentProfit = posType == POSITION_TYPE_BUY ? 
                                currentPrice - entryPrice : 
                                entryPrice - currentPrice;
         double currentRR = riskDistance > 0 ? currentProfit / riskDistance : 0;
         
         // Breakeven
         if(UseBreakeven && currentRR >= BreakevenRR)
         {
            double newSL = posType == POSITION_TYPE_BUY ? 
                           entryPrice + 5 * _Point : 
                           entryPrice - 5 * _Point;
            
            if((posType == POSITION_TYPE_BUY && newSL > currentSL) ||
               (posType == POSITION_TYPE_SELL && newSL < currentSL))
            {
               trade.PositionModify(ticket, newSL, takeProfit);
               Print("🔒 Breakeven aplicado | Ticket: ", ticket);
            }
         }
         
         // Trailing Stop por estructura
         if(UseTrailingStop)
         {
            // Actualizar SL al nuevo swing válido si es mejor
            double newStructureSL = 0;
            
            if(posType == POSITION_TYPE_BUY)
            {
               // Para longs, mover SL al último swing low si es más alto
               if(lastValidSwingLow.isValid && lastValidSwingLow.price > currentSL)
               {
                  newStructureSL = lastValidSwingLow.price - 10 * _Point;
               }
            }
            else
            {
               // Para shorts, mover SL al último swing high si es más bajo
               if(lastValidSwingHigh.isValid && lastValidSwingHigh.price < currentSL)
               {
                  newStructureSL = lastValidSwingHigh.price + 10 * _Point;
               }
            }
            
            if(newStructureSL > 0)
            {
               trade.PositionModify(ticket, newStructureSL, takeProfit);
               Print("📊 Trailing por estructura | Ticket: ", ticket, " | Nuevo SL: ", newStructureSL);
            }
         }
         
         // Cerrar si hay Change of Character en contra
         if(posType == POSITION_TYPE_BUY && currentStructure == STRUCTURE_BEARISH)
         {
            trade.PositionClose(ticket);
            Print("🔄 Posición LONG cerrada por cambio a estructura BAJISTA");
         }
         else if(posType == POSITION_TYPE_SELL && currentStructure == STRUCTURE_BULLISH)
         {
            trade.PositionClose(ticket);
            Print("🔄 Posición SHORT cerrada por cambio a estructura ALCISTA");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar si estamos dentro de horario de trading                 |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour;
   
   if(TradingStartHour < TradingEndHour)
   {
      return (currentHour >= TradingStartHour && currentHour < TradingEndHour);
   }
   else
   {
      // Horario que cruza medianoche
      return (currentHour >= TradingStartHour || currentHour < TradingEndHour);
   }
}

//+------------------------------------------------------------------+
//| Obtener nombre de la estructura                                   |
//+------------------------------------------------------------------+
string GetStructureName(ENUM_MARKET_STRUCTURE structure)
{
   switch(structure)
   {
      case STRUCTURE_BULLISH: return "ALCISTA ⬆️";
      case STRUCTURE_BEARISH: return "BAJISTA ⬇️";
      case STRUCTURE_NEUTRAL: return "NEUTRAL ↔️";
      default: return "DESCONOCIDA";
   }
}

//+------------------------------------------------------------------+
//| Imprimir estado de estructura (debug)                            |
//+------------------------------------------------------------------+
void PrintStructureStatus()
{
   static datetime lastDebugTime = 0;
   if(TimeCurrent() - lastDebugTime < 300) // Cada 5 minutos
      return;
   
   lastDebugTime = TimeCurrent();
   
   Print("═══════════ ESTADO DE ESTRUCTURA ═══════════");
   Print("Estructura actual: ", GetStructureName(currentStructure));
   Print("Nivel ruptura alcista: ", bullishBreakLevel);
   Print("Nivel ruptura bajista: ", bearishBreakLevel);
   Print("Último swing high: ", lastValidSwingHigh.price, " @ ", TimeToString(lastValidSwingHigh.time, TIME_DATE|TIME_MINUTES));
   Print("Último swing low: ", lastValidSwingLow.price, " @ ", TimeToString(lastValidSwingLow.time, TIME_DATE|TIME_MINUTES));
   Print("═════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| FUNCIONES DE VISUALIZACIÓN                                        |
//+------------------------------------------------------------------+

void DrawSwingPoint(SwingPoint &swing, bool isHigh)
{
   string name = "PA_Swing_" + (isHigh ? "H_" : "L_") + IntegerToString(swing.time);
   
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   
   ENUM_OBJECT objType = isHigh ? OBJ_ARROW_DOWN : OBJ_ARROW_UP;
   color objColor = isHigh ? BullishColor : BearishColor;
   double offset = isHigh ? 20 * _Point : -20 * _Point;
   
   if(ObjectCreate(0, name, objType, 0, swing.time, swing.price + offset))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, objColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   }
}

void DrawStructureLine(double price, bool isBullish)
{
   string name = "PA_BOS_" + IntegerToString(TimeCurrent());
   
   datetime startTime = iTime(_Symbol, TradingTimeframe, 10);
   datetime endTime = TimeCurrent() + PeriodSeconds(TradingTimeframe) * 5;
   
   if(ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBullish ? BullishColor : BearishColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Etiqueta
   string labelName = "PA_BOS_Label_" + IntegerToString(TimeCurrent());
   if(ObjectCreate(0, labelName, OBJ_TEXT, 0, endTime, price))
   {
      ObjectSetString(0, labelName, OBJPROP_TEXT, isBullish ? "BOS ⬆️" : "BOS ⬇️");
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, isBullish ? BullishColor : BearishColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   }
}

void DrawChochLine(double price, bool towardsBullish)
{
   string name = "PA_CHOCH_" + IntegerToString(TimeCurrent());
   
   datetime startTime = iTime(_Symbol, TradingTimeframe, 10);
   datetime endTime = TimeCurrent() + PeriodSeconds(TradingTimeframe) * 5;
   
   if(ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, NeutralColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
   
   // Etiqueta
   string labelName = "PA_CHOCH_Label_" + IntegerToString(TimeCurrent());
   if(ObjectCreate(0, labelName, OBJ_TEXT, 0, endTime, price))
   {
      ObjectSetString(0, labelName, OBJPROP_TEXT, "CHOCH 🔄");
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, NeutralColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   }
}

void DrawTradeLabel(double price, bool isLong)
{
   string name = "PA_Trade_" + IntegerToString(TimeCurrent());
   
   if(ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, TimeCurrent(), price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, isLong ? BullishColor : BearishColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   }
   
   string labelName = "PA_Trade_Label_" + IntegerToString(TimeCurrent());
   double labelPrice = isLong ? price + 30 * _Point : price - 30 * _Point;
   
   if(ObjectCreate(0, labelName, OBJ_TEXT, 0, TimeCurrent(), labelPrice))
   {
      ObjectSetString(0, labelName, OBJPROP_TEXT, isLong ? "LONG 📈" : "SHORT 📉");
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, isLong ? BullishColor : BearishColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 12);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   }
}

//+------------------------------------------------------------------+
