import Toybox.Activity;
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
    private const C_DIVIDER as Number = 0x2E2E2E;
    private const C_AOD     as Number = 0xAAAAAA;
    private const C_RED     as Number = 0xAA2222;
    private const C_BATTLOW as Number = C_RED;

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
    private var _hTime as Number = 0;
    private var _timeFont as Graphics.FontDefinition = Graphics.FONT_NUMBER_THAI_HOT;

    private var _yHeader  as Number = 30;
    private var _yTopLbl  as Number = 70;
    private var _yTopVal  as Number = 95;
    private var _yDiv1    as Number = 128;
    private var _yTime    as Number = 195;
    private var _yDateTop as Number = 178;
    private var _yDateBot as Number = 210;
    private var _yDiv2    as Number = 262;
    private var _yBotVal  as Number = 300;
    private var _yBotLbl  as Number = 328;

    private var _isAwake as Boolean = true;

    // Last-known-good sensor values, to ride out SensorHistory gaps
    private var _bodyBatt   as Number? = null;
    private var _bodyBattAt as Number  = 0;
    private var _stress     as Number? = null;
    private var _stressAt   as Number  = 0;
    private var _sleep      as Number? = null;
    private var _sleepAt    as Number  = 0;
    private const STALE_SECS as Number = 7200;

    private const PAD     as Number = 2;
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

        var inset   = _h / 16;
        var safeTop = inset;
        var safeBot = _h - inset;
        var safeH   = safeBot - safeTop;

        // Largest number font whose full stack fits the vertical safe band.
        var candidates = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM
        ] as Array<Graphics.FontDefinition>;

        _timeFont = candidates[candidates.size() - 1];
        _hTime    = Graphics.getFontHeight(_timeFont);
        for (var i = 0; i < candidates.size(); i += 1) {
            var ht = Graphics.getFontHeight(candidates[i]);
            if (stackHeight(ht) <= safeH) {
                _timeFont = candidates[i];
                _hTime    = ht;
                break;
            }
        }

        // Pin the TIME to the exact vertical center (widest chord), then flow
        // the rest of the stack outward from there.
        var toTimeCenter = _hHdr + PAD + _hLbl + 4 + _hVal + PAD + 1 + PAD + _hTime / 2;
        var y = _h / 2 - toTimeCenter;
        if (y < safeTop) { y = safeTop; }

        _yHeader = y + _hHdr / 2;            y += _hHdr + PAD;
        _yTopLbl = y + _hLbl / 2;            y += _hLbl + 4;
        _yTopVal = y + _hVal / 2;            y += _hVal + PAD;
        _yDiv1   = y;                        y += 1 + PAD;
        _yTime   = y + _hTime / 2;
        _yDateTop = _yTime - _hVal / 2;
        _yDateBot = _yTime + _hHdr / 2;      y += _hTime + PAD;
        _yDiv2   = y;                        y += 1 + PAD;
        _yBotVal = y + _hVal / 2;            y += _hVal + 4;
        _yBotLbl = y + _hLbl / 2;

        // Solve each metric band's outer-column offset from measured widths.
        // Top band measured at the values row; bottom at the icon row (lowest).
        var sTop = solveSpread(dc, "88888", "88.88", "8888", _yTopVal, 0, Graphics.FONT_TINY);
        var sBot = 92;
        _cxLtop = _cxM - sTop;  _cxRtop = _cxM + sTop;
        _cxLbot = _cxM - sBot;  _cxRbot = _cxM + sBot;

    }

    // Stack height for a candidate time-font height.
    private function stackHeight(hTime as Number) as Number {
        return _hHdr + PAD
             + _hLbl + 4 + _hVal + PAD
             + 1 + PAD
             + hTime + PAD
             + 1 + PAD
             + _hVal + 4 + _hLbl;
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

    public function onExitSleep() as Void { _isAwake = true; }
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
        var actInfo = ActivityMonitor.getInfo();
        drawHeader(dc);
        drawTopMetrics(dc, actInfo, distanceUnits);
        drawVerticalDividers(dc);
        drawHairline(dc, _yDiv1);
        drawTimeBand(dc, System.getClockTime(), C_PRIMARY, 0, 0, is24h);
        drawHairline(dc, _yDiv2);
        drawBottomMetrics(dc, actInfo);
    }

    private function drawAOD(dc as Dc, is24h as Boolean) as Void {
        var ct = System.getClockTime();
        drawTimeBand(dc, ct, C_AOD, burnX(ct), burnY(ct), is24h);
    }

    private function burnX(ct as System.ClockTime) as Number { return (ct.min % 6) - 3; }
    private function burnY(ct as System.ClockTime) as Number { return (ct.min % 4) - 2; }

    private function drawHeader(dc as Dc) as Void {
        var C_GREEN  = 0x00AA44;
        var C_YELLOW = 0xCCAA00;

        var C_RING   = 0x606060; // bright enough to see on real AMOLED
        var C_EMPTY  = 0x1A1A1A; // dim base so the dot shape is always visible
        var dotR     = 8;
        var spacing  = 20;
        var startX   = _cxM - spacing * 3;
        var cy       = _yHeader;

        var today   = ActivityMonitor.getInfo();
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

                var prof = UserProfile.getProfile();
                if ((prof has :averageRestingHeartRate) && prof.averageRestingHeartRate instanceof Number) {
                    var rhr = prof.averageRestingHeartRate as Number;
                    if (rhr > 0) { restHR = rhr; }
                } else if ((prof has :restingHeartRate) && prof.restingHeartRate instanceof Number) {
                    var rhr = prof.restingHeartRate as Number;
                    if (rhr > 0) { restHR = rhr; }
                }
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
                        if ((rec has :restingHeartRate) && rec.restingHeartRate instanceof Number) {
                            restHR = rec.restingHeartRate as Number;
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
                else if (restHR < 60) { topColor = C_YELLOW; }
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

    // Slim vertical line whose tips dissolve into the background.
    private function drawFadingVLine(dc as Dc, x as Number, yTop as Number, yBot as Number) as Void {
        var lineH = yBot - yTop;
        if (lineH <= 2) { return; }
        var fadeH = lineH / 3;
        if (fadeH < 4) { fadeH = 4; }
        var peak = 0x3C; // max brightness component (~60/255, subtle gray)
        for (var y = yTop; y <= yBot; y++) {
            var dy   = y - yTop;
            var fromE = lineH - dy;
            var dist = dy < fromE ? dy : fromE;
            var b    = dist >= fadeH ? peak : peak * dist / fadeH;
            if (b > 0) {
                dc.setColor((b << 16) | (b << 8) | b, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, y, 1, 1);
            }
        }
    }

    private function drawVerticalDividers(dc as Dc) as Void {
        // Top band: span from top of label row to bottom of value row
        var tTop = _yTopLbl - _hLbl / 2 - 4;
        var tBot = _yTopVal + _hVal / 2 + 4;
        // Bottom band: span from top of value row to bottom of label row
        var bTop = _yBotVal - _hVal / 2 - 4;
        var bBot = _yBotLbl + _hLbl / 2 + 4;

        // X: midpoint between adjacent column centers
        var txL = (_cxLtop + _cxM) / 2;
        var txR = (_cxM + _cxRtop) / 2;
        var bxL = (_cxLbot + _cxM) / 2;
        var bxR = (_cxM + _cxRbot) / 2;

        drawFadingVLine(dc, txL, tTop, tBot);
        drawFadingVLine(dc, txR, tTop, tBot);
        drawFadingVLine(dc, bxL, bTop, bBot);
        drawFadingVLine(dc, bxR, bTop, bBot);
    }

    private function drawHairline(dc as Dc, y as Number) as Void {
        var half = chordHalf(y);
        if (half <= 0) { return; }
        var inset = (half * 88) / 100;
        dc.setColor(C_DIVIDER, C_BG);
        dc.drawLine(_cxM - inset, y, _cxM + inset, y);
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

        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxLtop, _yTopVal, Graphics.FONT_TINY, stepsStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxM, _yTopVal, Graphics.FONT_TINY, buildDistStr(info, distanceUnits),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(_cxRtop, _yTopVal, Graphics.FONT_TINY, getBodyBatteryStr(),
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
        var dowW  = dc.getTextWidthInPixels(dow, Graphics.FONT_XTINY);
        var domW  = dc.getTextWidthInPixels(dom, Graphics.FONT_TINY);
        var dateW = (dowW > domW) ? dowW : domW;

        var groupW = timeW + GAP + dateW;
        var startX = (_w - groupW) / 2 + xShift;

        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, _yTime + yShift, _timeFont, timeStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var dateCx = startX + timeW + GAP + dateW / 2;
        dc.drawText(dateCx, _yDateTop + yShift, Graphics.FONT_XTINY, dow,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(dateCx, _yDateBot + yShift, Graphics.FONT_TINY, dom,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawBottomMetrics(dc as Dc, info as ActivityMonitor.Info) as Void {
        // Left — sleep score, falling back to stress (HRV-derived) if unavailable
        var sleepStr  = "--";
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

        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxLbot, _yBotVal, Graphics.FONT_TINY, sleepStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (showStress) {
            dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cxLbot, _yBotLbl, Graphics.FONT_XTINY, "HRV",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            drawMoonIcon(dc, _cxLbot, _yBotLbl);
        }

        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxM, _yBotVal, Graphics.FONT_TINY, getHrStr(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxM, _yBotLbl, Graphics.FONT_XTINY, "HR",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var batt = System.getSystemStats().battery.toNumber();
        dc.setColor(C_PRIMARY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cxRbot, _yBotVal, Graphics.FONT_TINY, batt.toString() + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawBatteryIcon(dc, _cxRbot, _yBotLbl, batt);
    }

    // Crescent moon: filled circle with an offset filled circle cut out in bg colour
    private function drawMoonIcon(dc as Dc, cx as Number, cy as Number) as Void {
        var r  = 7;  // moon body radius
        var ro = 6;  // cutout radius
        var ox = 3;  // cutout x offset (shifts the shadow rightward)
        var oy = -2; // cutout y offset (shifts shadow upward)
        dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(C_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx + ox, cy + oy, ro);
    }



    private function drawBatteryIcon(dc as Dc, cx as Number, cy as Number, pct as Number) as Void {
        var bw = 24; var bh = 10;
        var bx = cx - bw / 2; var by = cy - bh / 2;
        dc.setColor(C_ICON, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(bx, by, bw, bh);
        dc.fillRectangle(bx + bw, by + 3, 3, 4);
        var fill = ((bw - 2) * pct / 100).toNumber();
        if (fill > 0) {
            dc.setColor(pct > 20 ? C_ICON : C_BATTLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 1, by + 1, fill, bh - 2);
        }
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