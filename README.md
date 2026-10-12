# MT5 Custom Setup — XAU Suite

A gold (XAU/USD) indicator suite for **MetaTrader 5**, ported from the TakeProfit (Indie) versions,
with TradingView-style **smooth, anti-aliased graphics** and a set of modern colour themes.

MT5 draws indicator plots with aliased 1-pixel GDI lines. Every indicator here instead renders onto a
32-bit ARGB canvas (`OBJ_BITMAP_LABEL`) through a small rendering engine (`Include/XauSuite`):

- **Strokes** are distance-field capsules with sub-pixel coverage, round caps and joins. Polylines are
  accumulated in a coverage mask first, so translucent lines never double-blend at the joints. Dashes
  and soft glows are supported.
- **Fills** between curves are rasterised per pixel column with fractional edges and optional alpha
  gradients (TradingView-like fading clouds). Clouds split exactly where the lines cross.
- **Shapes**: rounded rectangles, circles and triangles use signed distance functions. Labels are pills
  with pointers, and dashboards are cards with shadows, chips, gauges and progress bars.
- **Text** uses the terminal's anti-aliased font renderer (Segoe UI).
- **Layers**: zones, clouds and boxes are drawn *behind* the candles, while lines, labels and tags are
  drawn *in front*.
- **Redraws** happen on scroll, zoom and resize, and on ticks at most every 120–300 ms. The values still
  appear in the Data Window and stay readable through `iCustom`.

## Indicators

| File | What it shows |
|---|---|
| `XAU_TrendRibbon` | 21/55 EMA cloud whose opacity follows ADX strength, 200 EMA baseline with glow, ATR trailing stop (Supertrend) with gradient fill, BUY/SELL flip labels, regime-coloured candles |
| `XAU_SessionsKeyLevels` | Asia / London / New York session boxes with range (DST-aware in each city's time), PDH / PDL / PDC, daily open, PWH / PWL, weekly open, round $50 levels, stacked price tags |
| `XAU_SmartMoneyConcepts` | BOS / CHoCH, HH / HL / LH / LL, order blocks, fair value gaps (shrink as filled), equal highs/lows, liquidity sweeps, premium / equilibrium / discount. Committed on closed bars only (no repaint) |
| `XAU_VWAPBands` | Day / week / month anchored VWAP on the NY 17:00 trading day, 1/2/3σ bands with gradient stretch / extreme zones, previous period VWAP, tags |
| `XAU_VolumeProfile` | Fixed-lookback **or visible-range** profile, buy/sell split, POC, value area, previous day POC / VAH / VAL |
| `XAU_MomentumMatrix` | RSI with a red→grey→teal value gradient and overbought / oversold glow, signal line, MACD histogram on the RSI scale, regular + hidden divergences with connecting lines (separate window) |
| `XAU_ADRVolatility` | ADR high / low targets (dynamic or from open) with exhaustion zones, squeeze / expansion regime background, ADR usage card with progress bar |
| `XAU_IntermarketRadar` | Rolling correlation of gold vs DXY and vs silver, gold/silver ratio z-score, read-out card (separate window). Detects broker symbols automatically (prefix/suffix aware) and synthesises DXY from the six ICE basket pairs if your broker has no dollar index |
| `XAU_CommandCenter` | Dashboard: 4-timeframe trend / RSI / ADX matrix, weighted bias verdict with gauge, session, day change, ADR usage, position in day range, PDH / PDL distance, ATR regime, plain-language read |
| `Scripts/XAU_OneClickSetup` | Builds the whole workspace in one click (see below) |
| `Scripts/XAU_ChartTheme` | Restyles the chart (background, candles, grid, axis) to match a theme |

## Themes

Every indicator has a **Colour theme** input:

- **Midnight**: mint / rose / gold on deep navy (default)
- **Aurora**: aqua / magenta / violet
- **Classic**: TradingView's own colours
- **Daylight**: tuned for white charts

Indicators default to **Suite theme**, which follows the last theme chosen in `XAU_OneClickSetup` or
`XAU_ChartTheme`. Those scripts also restyle the chart background and candles to match. Then save it as a
template (*Charts → Templates → Save Template*).

## Install

1. In MT5: **File → Open Data Folder**.
2. Copy the repository's `MQL5` folder over the terminal's `MQL5` folder. This merges `Include/XauSuite`,
   `Indicators/XauSuite` and `Scripts/XauSuite`.
3. Open **MetaEditor** (F4), right-click `Indicators/XauSuite` → **Compile**, then do the same for
   `Scripts/XauSuite`.
4. In the terminal's Navigator, refresh, then drag indicators onto an XAUUSD chart.

## One-click setup

After compiling, drag **Scripts → XauSuite → XAU_OneClickSetup** onto any chart, pick a theme and press OK.
The script finds your broker's gold symbol (including suffixes such as `XAUUSD.m`), then opens and styles:

| Chart | Purpose | Indicators |
|---|---|---|
| XAUUSD **D1** | Bias | Trend Ribbon, Smart Money Concepts |
| XAUUSD **H4** | Structure | Smart Money Concepts, Volume Profile, Sessions & Key Levels |
| XAUUSD **H1** | Plan | Sessions & Key Levels, VWAP Bands, Command Center, Intermarket Radar (sub-window) |
| XAUUSD **M15** | Execution | Trend Ribbon, Sessions & Key Levels, VWAP Bands, ADR & Volatility, Command Center, Momentum Matrix (sub-window) |
| DXY / XAGUSD **H1** | Context | Trend Ribbon (when your broker offers them) |

Other options:

- **What to set up**: instead of opening new charts, add only the Execution, Plan or Structure set to the
  current chart.
- **Close all other charts first**: start from a clean workspace.
- **Gold symbol**: set this if auto-detection picks the wrong symbol.

When it finishes, use *Window → Tile Windows* (Alt+R), then *File → Profiles → Save As* to keep the
workspace.

All indicators default to **Suite theme**, so the theme chosen in the setup (or `XAU_ChartTheme`) script
applies to every indicator. Pick a fixed theme in an indicator's inputs to override it.

## Time settings

Bar times in MT5 are broker server time. Indicators that use the trading day or sessions have a **Time**
input group:

- **Trading day starts at**: New York 17:00 (the metals/FX day, default), UTC 00:00, or broker midnight.
- **Server GMT offset**: `99` auto-detects the offset from the live server clock. Set a number such as `2`
  to force it.
- **Server daylight-saving rule**: most gold brokers run GMT+2 in winter and GMT+3 in summer on the US
  DST calendar (the default). Change it if your broker follows EU DST or has no DST.

## Suggested layouts

- **Execution chart (M5–M15)**: Trend Ribbon + Sessions & Key Levels + VWAP Bands + Command Center,
  with Momentum Matrix in a sub-window.
- **Structure chart (M15–H1)**: Smart Money Concepts + Volume Profile + ADR & Volatility.
- **Context**: Intermarket Radar in a sub-window on H1.

## Repository layout

```
MQL5/
  Include/XauSuite/    rendering engine, themes, trading-day clock
  Indicators/XauSuite/ the nine indicators
  Scripts/XauSuite/    chart theme script
```
