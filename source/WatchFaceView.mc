import Toybox.Activity;
import Toybox.Application.Storage;
import Toybox.UserProfile;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.ActivityMonitor;
import Toybox.SensorHistory;

class WatchFaceView extends WatchUi.WatchFace {

    // ── Palette ────────────────────────────────────────────────────────────
    private const C_BG      as Number = 0x000000;
    private const C_PRIMARY as Number = 0xFFFFFF;
    private const C_LABEL   as Number = 0x8C8C8C;
    private const C_ICON    as Number = 0xB0B0B0;
    private const C_AOD     as Number = 0xAAAAAA;
    private const C_RED     as Number = 0xAA2222;
    private const C_GREEN   as Number = 0x00AA44;
    private const C_YELLOW  as Number = 0xCCAA00;
    private const C_TRACK   as Number = 0x1C1C1C;

    // ── Screen geometry (resolved in onLayout) ─────────────────────────────
    private var _w as Number = 390;
    private var _h as Number = 390;

    // Center column constant; outer columns solved per-band so they neither
    // clip the round arc nor collide with the center column.
    private var _cxM    as Number = 195;
    private var _cxLtop as Number = 105;
    private var _cxRtop as Number = 285;
    private var _cxLbot as Number = 105;
    private var _cxRbot as Number = 285;

    private var _hHdr  as Number = 0;
    private var _hLbl  as Number = 0;
    private var _hVal  as Number = 0;
    private var _timeDy as Number = 0;      // digit centre relative to font-box centre
    private var _chartH as Number = 14;
    private var _hDow  as Number = 0;
    private var _hDom  as Number = 0;
    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_THAI_HOT;

    private var _yHeader  as Number = 30;
    private var _yTopLbl  as Number = 70;
    private var _yTopVal  as Number = 95;
    private var _yDiv1    as Number = 128;
    private var _yTime    as Number = 195;
    private var _yDateTop as Number = 178;
    private var _yDateBot as Number = 210;
    private var _yChart   as Number = 250;   // top of the stress strip
    private var _yDiv2    as Number = 262;
    private var _yBotVal  as Number = 300;
    private var _yBotLbl  as Number = 328;

    private var _isAwake as Boolean = true;

    private var _stressBars   as Array<Number>? = null;   // 0-100, or -1 for no data
    private var _stressBarsAt as Number         = 0;

    // RHR history — persisted daily in Application.Storage
    private const RHR_KEY  as String            = "rhrHist";
    private var   _rhrHist as Dictionary or Null = null;

    // Last-known-good sensor values, to ride out SensorHistory gaps
    private var _bodyBatt   as Number? = null;
    private var _bodyBattAt as Number  = 0;
    private var _stress     as Number? = null;
    private var _stressAt   as Number  = 0;
    private var _sleep      as Number? = null;
    private var _sleepAt    as Number  = 0;
    private const STALE_SECS as Number = 7200;

    private const PAD      as Number = 2;
    private const HAIR_PAD as Number = 8;   // metric value row → hairline
    private const LBL_GAP  as Number = 2;   // metric label row ↔ value row
    // Number fonts reserve a lot of empty space above/below the digits. The layout
    // is sized by the digits themselves: digit height ≈ INK_PCT % of the font ascent,
    // sitting on the baseline (measured on THAI_HOT/HOT).
    private const INK_PCT as Number = 69;
    private const TPAD    as Number = 8;     // hairline → digits
    private const TGAP    as Number = 8;     // digits → chart

    // 24h stress strip under the time
    private const CHART_BARS as Number = 48;
    private const CHART_MIN  as Number = 14;
    private const CHART_MAX  as Number = 36;
    private const CHART_GAP  as Number = 8;     // chart bottom → hairline
    private const CHART_SECS as Number = 86400;
    private const CHART_REFRESH as Number = 600;
    private const DOW_FONT as Graphics.FontDefinition = Graphics.FONT_TINY;
    private const DOM_FONT as Graphics.FontDefinition = Graphics.FONT_SMALL;
    private const GAP     as Number = 12;
    private const COLGAP  as Number = 16;
    private const DAY_NAMES as Array<String> = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

    public function initialize() {
        WatchFace.initialize();
    }

    public function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cxM = _w / 2;

        _hHdr = Graphics.getFontHeight(Graphics.FONT_XTINY);  // header + date weekday
        _hLbl = Graphics.getFontHeight(Graphics.FONT_XTINY);
        _hVal = Graphics.getFontHeight(Graphics.FONT_TINY);    // metric values + date day

        _hDow = Graphics.getFontHeight(DOW_FONT);
        _hDom = Graphics.getFontHeight(DOM_FONT);

        var inset   = _h / 24;
        var safeTop = inset;
        var safeBot = _h - inset;
        var safeH   = safeBot - safeTop;

        // Everything except the time digits and the chart.
        var fixed = _hHdr + PAD + _hLbl + LBL_GAP + _hVal + HAIR_PAD + 1 + TPAD
                  + TGAP + CHART_GAP + 1 + HAIR_PAD + _hVal + LBL_GAP + _hLbl;
        var avail = safeH - fixed;            // shared by time digits + chart

        // Widest the time may be, leaving room for the date block beside it.
        var wDow    = dc.getTextWidthInPixels("WED", DOW_FONT);
        var wDom    = dc.getTextWidthInPixels("88",  DOM_FONT);
        var dateW   = (wDow > wDom) ? wDow : wDom;
        var widthCap = (chordHalf(_h / 2) * 2 * 94) / 100 - GAP - dateW;
        var inkCap   = avail - CHART_MIN;

        // Built-in fallback: largest number font whose digits fit.
        var candidates = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM
        ] as Array<Graphics.FontDefinition>;

        var baseFont = candidates[candidates.size() - 1];
        for (var i = 0; i < candidates.size(); i += 1) {
            if (inkOf(candidates[i]) <= inkCap
                && dc.getTextWidthInPixels("00:00", candidates[i]) <= widthCap) {
                baseFont = candidates[i];
                break;
            }
        }
        _timeFont = baseFont;
        var inkH = inkOf(baseFont);

        // CIQ 5.1+: rescale the biggest font to exactly fill the height / width
        // budget (glyphs keep their look). Older devices keep the built-in size.
        if (Graphics has :getVectorFont) {
            var f0  = candidates[0];
            var sH  = inkCap.toFloat() / inkOf(f0);
            var sW  = widthCap.toFloat() / dc.getTextWidthInPixels("00:00", f0);
            var s   = (sH < sW) ? sH : sW;
            for (var n = 0; n < 4 && s >= 0.6; n += 1) {
                try {
                    var vf = Graphics.getVectorFont({:font => f0, :scale => s});
                    if (vf != null) {
                        var ink = inkOf(vf);
                        if (ink <= inkCap && dc.getTextWidthInPixels("00:00", vf) <= widthCap) {
                            if (ink > inkH) { _timeFont = vf; inkH = ink; }
                            break;
                        }
                    }
                } catch (e) {
                    break;      // keep the built-in font
                }
                s = s * 0.97;
            }
        }

        _chartH = avail - inkH;
        if (_chartH > CHART_MAX) { _chartH = CHART_MAX; }
        _timeDy = Graphics.getFontAscent(_timeFont) - inkH / 2 - Graphics.getFontHeight(_timeFont) / 2;

        // Pin the digits to the exact vertical centre (widest chord) where the
        // stack allows, then flow the rest outward from there.
        var total        = fixed + inkH + _chartH;
        var toTimeCenter = _hHdr + PAD + _hLbl + LBL_GAP + _hVal + HAIR_PAD + 1 + TPAD + inkH / 2;
        var y = _h / 2 - toTimeCenter;
        if (y < safeTop)           { y = safeTop; }
        if (y + total > safeBot)   { y = safeBot - total; }

        _yHeader = y + _hHdr / 2;            y += _hHdr + PAD;
        _yTopLbl = y + _hLbl / 2;            y += _hLbl + LBL_GAP;
        _yTopVal = y + _hVal / 2;            y += _hVal + HAIR_PAD;
        _yDiv1   = y;                        y += 1 + TPAD;
        _yTime   = y + inkH / 2;             // centre of the digits
        _yDateTop = _yTime - _hDom / 2;
        _yDateBot = _yTime + _hDow / 2;      y += inkH + TGAP;
        _yChart  = y;                        y += _chartH + CHART_GAP;
        _yDiv2   = y;                        y += 1 + HAIR_PAD;
        _yBotVal = y + _hVal / 2;            y += _hVal + LBL_GAP;
        _yBotLbl = y + _hLbl / 2;

        // Solve each metric band's outer-column offset from measured widths.
        // Top band measured at the values row; bottom at the icon row (lowest).
        var sTop = solveSpread(dc, "88888", "88.88", "8888", _yTopVal, 0, Graphics.FONT_TINY);
        var sBot = solveSpread(dc, "88", "888", "100%", _yBotLbl, 12, Graphics.FONT_TINY);
        _cxLtop = _cxM - sTop;  _cxRtop = _cxM + sTop;
        _cxLbot = _cxM - sBot;  _cxRbot = _cxM + sBot;

    }

    // Height of the digits of a number font (they sit on the baseline).
    private function inkOf(font as Graphics.FontType) as Number {
        return Graphics.getFontAscent(font) * INK_PCT / 100;
    }

    // Outer-column offset bounded by: lower = no overlap with center column,
    // upper = no clip past the round arc. Target sits near 0.26*width.
    private function solveSpread(dc as Dc, leftMax as String, centerMax as String,
                                 rightMax as String, yRow as Number, iconHalf as Number,
                                 font as Graphics.FontDefinition) as Number {
        var cW = dc.getTextWidthInPixels(centerMax, font) / 2;
        var lW = dc.getTextWidthInPixels(leftMax,   font) / 2;
        var rW = dc.getTextWidthInPixels(rightMax,  font) / 2;

        var needL = cW + lW + COLGAP;
        var needR = cW + rW + COLGAP;
        var minS  = (needL > needR) ? needL : needR;

        // Outer content half-width (text or icon, whichever is wider).
        var edge = lW;
        if (rW > edge)       { edge = rW; }
        if (iconHalf > edge) { edge = iconHalf; }

        var maxS = (chordHalf(yRow) * 90) / 100 - edge;
        if (maxS < 0) { maxS = 0; }

        var s = (_w * 52) / 200;       // target
        if (s < minS) { s = minS; }    // don't collide
        if (s > maxS) { s = maxS; }    // don't clip (collision-avoid loses if arc is too tight)
        return s;
    }

    private function chordHalf(y as Number) as Number {
        var r  = _w / 2;
        var dy = y - (_h / 2);
        var v  = r * r - dy * dy;
        if (v <= 0) { return 0; }
        return Math.sqrt(v).toNumber();
    }

    public function onShow() as Void { loadRhrHist(); }
    public function onExitSleep() as Void { _isAwake = true; loadRhrHist(); }
    public function onEnterSleep() as Void { _isAwake = false; }

    public function setSleepScore(v as Number) as Void {
        _sleep   = v;
        _sleepAt = Time.now().value();
    }

    public function onUpdate(dc as Dc) as Void {
        var settings      = System.getDeviceSettings();
        var is24h         = settings.is24Hour;
        var distanceUnits = settings.distanceUnits;
        dc.setColor(C_BG, C_BG);
        dc.clear();
        if (_isAwake) {
            drawFullFace(dc, is24h, distanceUnits);
        } else {
            drawAOD(dc, is24h);
        }
    }

    private function drawFullFace(dc as Dc, is24h as Boolean, distanceUnits as System.UnitsSystem) as Void {
        recordTodayRhr();
        var actInfo = ActivityMonitor.getInfo();
        drawHeader(dc, actInfo);
        drawTopMetrics(dc, actInfo, distanceUnits);
        drawHairline(dc, _yDiv1);
        drawTimeBand(dc, System.getClockTime(), C_PRIMARY, 0, 0, is24h);
        drawStressChart(dc);
        drawHairline(dc, _yDiv2);
        drawBottomMetrics(dc, actInfo);
        drawBezelArcs(dc, actInfo);
    }

    private function drawAOD(dc as Dc, is24h as Boolean) as Void {
        var ct = System.getClockTime();
        drawTimeBand(dc, ct, C_AOD, burnX(ct), burnY(ct), is24h);
    }

    private function burnX(ct as System.ClockTime) as Number { return (ct.min % 6) - 3; }
    private function burnY(ct as System.ClockTime) as Number { return (ct.min % 4) - 2; }

    private function drawHeader(dc as Dc, today as ActivityMonitor.Info) as Void {

        var C_RING   = 0x606060; // bright enough to see on real AMOLED
        var C_EMPTY  = 0x1A1A1A; // dim base so the dot shape is always visible
        var dotR     = 8;
        var spacing  = 20;
        var startX   = _cxM - spacing * 3;
        var cy       = _yHeader;

        var history = ActivityMonitor.getHistory();

        for (var i = 0; i < 7; i++) {
            var cx          = startX + i * spacing;
            var steps       = 0;
            var stepGoal    = 8000;
            var restHR      = -1;  // -1 = no data
            var vigorousMin = 0;
            var moderateMin = 0;

            if (i == 6) {
                // Today — ActivityMonitor.Info has all fields
                if (today.steps    instanceof Number) { steps    = today.steps    as Number; }
                if (today.stepGoal instanceof Number) { stepGoal = today.stepGoal as Number; }

                var rhr = readCurrentRhr();
                if (rhr != null) { restHR = rhr as Number; }
                if (today has :activeMinutesDay) {
                    var actMin = today.activeMinutesDay;
                    if (actMin != null) {
                        if (actMin.vigorous instanceof Number) { vigorousMin = actMin.vigorous as Number; }
                        if (actMin.moderate instanceof Number) { moderateMin = actMin.moderate as Number; }
                    }
                }
            } else {
                // Past day record (ActivityMonitor.ActivityInfo, fewer fields)
                var hi = 5 - i;
                if (hi < history.size()) {
                    var rec = history[hi];
                    if (rec != null) {
                        if (rec.steps    instanceof Number) { steps    = rec.steps    as Number; }
                        if (rec.stepGoal instanceof Number) { stepGoal = rec.stepGoal as Number; }
                        if (rec.startOfDay instanceof Time.Moment) {
                            restHR = rhrForDay(rec.startOfDay as Time.Moment);
                        }
                        if (rec has :activeMinutes) {
                            var recMin = rec.activeMinutes;
                            if (recMin != null) {
                                if ((recMin has :vigorous) && recMin.vigorous instanceof Number) {
                                    vigorousMin = recMin.vigorous as Number;
                                }
                                if ((recMin has :moderate) && recMin.moderate instanceof Number) {
                                    moderateMin = recMin.moderate as Number;
                                }
                            }
                        }
                    }
                }
            }

            // Exercise: step goal met, OR vigorous ≥5 min, OR moderate ≥20 min
            var exercised = (steps >= stepGoal) || (vigorousMin >= 5) || (moderateMin >= 20);

            // Top-half color from RHR (-1 → no fill)
            var topColor = -1;
            if (restHR >= 0) {
                if      (restHR < 57) { topColor = C_GREEN;  }
                else if (restHR < 65) { topColor = C_YELLOW; }
                else                  { topColor = C_RED;    }
            }

            // Always draw dim base so the dot is visible even with no data
            dc.setColor(C_EMPTY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, dotR - 1);

            // Outline ring
            dc.setColor(C_RING, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, dotR);

            // Top half — RHR indicator
            if (topColor >= 0) {
                dc.setClip(cx - dotR, cy - dotR, dotR * 2 + 1, dotR);
                dc.setColor(topColor, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, dotR - 1);
                dc.clearClip();
            }

            // Bottom half — exercise indicator
            if (exercised) {
                dc.setClip(cx - dotR, cy, dotR * 2 + 1, dotR + 1);
                dc.setColor(C_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, dotR - 1);
                dc.clearClip();
            }
        }
    }

    // Horizontal rule whose ends dissolve into the background.
    private function drawHairline(dc as Dc, y as Number) as Void {
        var half = chordHalf(y);
        if (half <= 0) { return; }
        var inset = (half * 88) / 100;
        var x0    = _cxM - inset;
        var len   = inset * 2;
        var fadeW = len / 4;
        var peak  = 0x30;
        for (var i = 0; i < len; i += 3) {
            var d = (i < len - i) ? i : len - i;
            var b = (d >= fadeW) ? peak : peak * d / fadeW;
            if (b > 0) {
                dc.setColor((b << 16) | (b << 8) | b, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x0 + i, y, x0 + i + 2, y);
            }
        }
    }

    private function drawTopMetrics(dc as Dc, info as ActivityMonitor.Info, distanceUnits as System.UnitsSystem) as Void {
        dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxLtop, _yTopLbl, Graphics.FONT_XTINY, "STP",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxM, _yTopLbl, Graphics.FONT_XTINY, "DIST",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxRtop, _yTopLbl, Graphics.FONT_XTINY, "BODY",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var stepsStr = (info.steps instanceof Number) ? (info.steps as Number).toString() : "0";
        var distStr  = buildDistStr(info, distanceUnits);
        var bodyStr  = getBodyBatteryStr();

        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxLtop, _yTopVal, Graphics.FONT_TINY, stepsStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxM, _yTopVal, Graphics.FONT_TINY, distStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxRtop, _yTopVal, Graphics.FONT_TINY, bodyStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

    }

    private function drawTimeBand(dc as Dc, clockTime as System.ClockTime,
                                  timeColor as Number, xShift as Number, yShift as Number,
                                  is24h as Boolean) as Void {
        var hour = clockTime.hour;
        var min  = clockTime.min;

        if (!is24h) {
            if (hour == 0)      { hour = 12; }
            else if (hour > 12) { hour -= 12; }
        }
        var timeStr = hour.format(is24h ? "%02d" : "%d") + ":" + min.format("%02d");

        var today  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dowIdx = (today.day_of_week instanceof Number) ? (today.day_of_week as Number) - 1 : 0;
        var dow    = DAY_NAMES[dowIdx];
        var dom      = (today.day instanceof Number) ? (today.day as Number).format("%d") : "--";

        var timeW = dc.getTextWidthInPixels(timeStr, _timeFont);
        var dowW  = dc.getTextWidthInPixels(dow, DOW_FONT);
        var domW  = dc.getTextWidthInPixels(dom, DOM_FONT);
        var dateW = (dowW > domW) ? dowW : domW;

        var groupW = timeW + GAP + dateW;
        var startX = (_w - groupW) / 2 + xShift;

        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, _yTime + yShift - _timeDy, _timeFont, timeStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var dateCx = startX + timeW + GAP + dateW / 2;
        dc.drawText(dateCx, _yDateTop + yShift, DOW_FONT, dow,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(dateCx, _yDateBot + yShift, DOM_FONT, dom,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Average the last 24h of stress samples into CHART_BARS buckets (oldest first).
    // Cached: a full pass reads several hundred samples, so redo it every few minutes.
    private function refreshStressBars() as Void {
        var now = Time.now().value();
        if (_stressBars != null && (now - _stressBarsAt) < CHART_REFRESH) { return; }

        var sums   = new Array<Number>[CHART_BARS];
        var counts = new Array<Number>[CHART_BARS];
        for (var i = 0; i < CHART_BARS; i += 1) { sums[i] = 0; counts[i] = 0; }

        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var iter = SensorHistory.getStressHistory({
                :period => new Time.Duration(CHART_SECS),
                :order  => SensorHistory.ORDER_OLDEST_FIRST
            });
            if (iter != null) {
                var start  = now - CHART_SECS;
                var sample = iter.next();
                while (sample != null) {
                    if (sample.data != null) {
                        var idx = ((sample.when.value() - start) * CHART_BARS) / CHART_SECS;
                        if (idx < 0)           { idx = 0; }
                        if (idx >= CHART_BARS) { idx = CHART_BARS - 1; }
                        sums[idx]   += (sample.data as Number).toNumber();
                        counts[idx] += 1;
                    }
                    sample = iter.next();
                }
            }
        }

        var bars = new Array<Number>[CHART_BARS];
        for (var i = 0; i < CHART_BARS; i += 1) {
            bars[i] = (counts[i] > 0) ? (sums[i] / counts[i]) : -1;
        }
        _stressBars   = bars;
        _stressBarsAt = now;
    }

    // Small grey bar strip under the time; older bars are dimmer, the newest brightest.
    private function drawStressChart(dc as Dc) as Void {
        refreshStressBars();
        var bars = _stressBars;
        if (bars == null) { return; }

        var bw    = 4;
        var gap   = 2;
        var total = CHART_BARS * (bw + gap) - gap;
        var x0    = _cxM - total / 2;
        var base  = _yChart + _chartH;

        for (var i = 0; i < CHART_BARS; i += 1) {
            var v = (bars as Array<Number>)[i];
            var h = 1;
            var b = 0x24;                                   // no data: faint baseline
            if (v >= 0) {
                h = 2 + (v * (_chartH - 2)) / 100;
                b = 0x34 + (0x6C * i) / (CHART_BARS - 1);   // 0x34 → 0xA0
            }
            dc.setColor((b << 16) | (b << 8) | b, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + i * (bw + gap), base - h, bw, h);
        }
    }

    private function drawBottomMetrics(dc as Dc, info as ActivityMonitor.Info) as Void {
        // Left — sleep score, falling back to stress if unavailable
        var sleepStr   = "--";
        var showStress = false;

        if (_sleep != null && (Time.now().value() - _sleepAt) < STALE_SECS) {
            sleepStr = (_sleep as Number).format("%d");
        }

        if (sleepStr.equals("--")) {
            var stress = getStressVal();
            if (stress != null) {
                sleepStr   = (stress as Number).format("%d");
                showStress = true;
            }
        }

        var batt = System.getSystemStats().battery.toNumber();

        drawMetric(dc, _cxLbot, _yBotVal, _yBotLbl, sleepStr, showStress ? "STR" : "SLP");
        drawMetric(dc, _cxM,    _yBotVal, _yBotLbl, getHrStr(), "HR");
        drawMetric(dc, _cxRbot, _yBotVal, _yBotLbl, batt.toString() + "%", "BAT");
    }

    // Value (white) with its dim label.
    private function drawMetric(dc as Dc, cx as Number, yVal as Number, yLbl as Number,
                                value as String, label as String) as Void {
        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yVal, Graphics.FONT_TINY, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yLbl, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Thin progress arcs hugging the bezel: steps on the left, battery on the right.
    private function drawBezelArcs(dc as Dc, info as ActivityMonitor.Info) as Void {
        var cx   = _w / 2;
        var cy   = _h / 2;
        var r    = _w / 2 - 5;
        var half = 35;                  // arc half-span in degrees
        var span = half * 2;

        var stepPct = 0.0;
        if ((info.steps instanceof Number) && (info.stepGoal instanceof Number)
            && (info.stepGoal as Number) > 0) {
            stepPct = (info.steps as Number).toFloat() / (info.stepGoal as Number);
            if (stepPct > 1.0) { stepPct = 1.0; }
        }
        var battPct = System.getSystemStats().battery / 100.0;
        if (battPct > 1.0) { battPct = 1.0; }

        dc.setPenWidth(4);
        dc.setColor(C_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE,         180 + half, 180 - half);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 360 - half, half);

        if (stepPct > 0.02) {
            dc.setColor(stepPct >= 1.0 ? C_GREEN : C_ICON, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 180 + half,
                       180 + half - (span * stepPct).toNumber());
        }
        if (battPct > 0.02) {
            // Normal grey; yellow warning under 20%; red at 5% or below.
            var battPctInt = System.getSystemStats().battery.toNumber();
            var battColor  = C_ICON;
            if (battPctInt <= 5)       { battColor = C_RED; }
            else if (battPctInt < 20)  { battColor = C_YELLOW; }
            dc.setColor(battColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 360 - half,
                       (360 - half + (span * battPct).toNumber()) % 360);
        }
        dc.setPenWidth(1);
    }

    private function readBodyBattery() as Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var iter   = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
            var sample = iter.next();
            if (sample != null && sample.data != null) { return sample.data as Number; }
        }
        return null;
    }

    private function readStress() as Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var iter   = SensorHistory.getStressHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
            var sample = iter.next();
            if (sample != null && sample.data != null) { return sample.data as Number; }
        }
        return null;
    }

    private function getBodyBatteryStr() as String {
        var fresh = readBodyBattery();
        if (fresh != null) {
            _bodyBatt   = fresh;
            _bodyBattAt = Time.now().value();
            return (fresh as Number).format("%d");
        }
        if (_bodyBatt != null && (Time.now().value() - _bodyBattAt) < STALE_SECS) {
            return (_bodyBatt as Number).format("%d");
        }
        return "--";
    }

    private function getStressVal() as Number? {
        var fresh = readStress();
        if (fresh != null) {
            _stress   = fresh;
            _stressAt = Time.now().value();
            return fresh;
        }
        if (_stress != null && (Time.now().value() - _stressAt) < STALE_SECS) {
            return _stress;
        }
        return null;
    }

    private function dayKey(m as Time.Moment) as String {
        var g = Gregorian.info(m, Time.FORMAT_SHORT);
        return (g.year  as Number).format("%04d")
             + (g.month as Number).format("%02d")
             + (g.day   as Number).format("%02d");
    }

    private function loadRhrHist() as Void {
        var v = Storage.getValue(RHR_KEY);
        _rhrHist = (v instanceof Dictionary) ? (v as Dictionary) : ({} as Dictionary);
    }

    private function readCurrentRhr() as Number? {
        var prof = UserProfile.getProfile();
        if ((prof has :averageRestingHeartRate) && prof.averageRestingHeartRate instanceof Number) {
            var rhr = prof.averageRestingHeartRate as Number;
            if (rhr > 0) { return rhr; }
        }
        if ((prof has :restingHeartRate) && prof.restingHeartRate instanceof Number) {
            var rhr = prof.restingHeartRate as Number;
            if (rhr > 0) { return rhr; }
        }
        return null;
    }

    private function recordTodayRhr() as Void {
        if (_rhrHist == null) { loadRhrHist(); }
        var d   = _rhrHist as Dictionary;
        var key = dayKey(Time.now());
        if (d.hasKey(key)) { return; }

        var rhr = readCurrentRhr();
        if (rhr == null) { return; }

        d.put(key, rhr as Number);

        var cutoff = dayKey(new Time.Moment(Time.now().value() - 8 * 86400));
        var keys = d.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var k = keys[i] as String;
            if (k.compareTo(cutoff) < 0) { d.remove(k); }
        }
        Storage.setValue(RHR_KEY, d as Dictionary<Storage.KeyType, Storage.ValueType>);
        _rhrHist = d;
    }

    private function rhrForDay(m as Time.Moment) as Number {
        if (_rhrHist == null) { loadRhrHist(); }
        var v = (_rhrHist as Dictionary).get(dayKey(m));
        return (v instanceof Number) ? (v as Number) : -1;
    }

    private function getHrStr() as String {
        var hist   = ActivityMonitor.getHeartRateHistory(1, true);
        var sample = hist.next();
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            return (sample.heartRate as Number).toString();
        }
        return "--";
    }

    private function buildDistStr(info as ActivityMonitor.Info, distanceUnits as System.UnitsSystem) as String {
        if (!(info.distance instanceof Number)) { return "0.00"; }
        var distCm = info.distance as Number;
        if (distanceUnits == System.UNIT_STATUTE) {
            return (distCm / 160934.4).format("%.2f");
        }
        return (distCm / 100000.0).format("%.2f");
    }
}