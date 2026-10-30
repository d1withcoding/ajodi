/**
 * Rounds the Hz to a whole number for grouping and the apply mode string while `raw` keeps the original entry, or returns null when it is not WxH@HZHz.
 */
function parseMode(raw) {
    var m = raw.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
    if (!m)
        return null;
    return {
        w: parseInt(m[1], 10),
        h: parseInt(m[2], 10),
        hz: Math.round(parseFloat(m[3])),
        raw: raw
    };
}

/**
 * Parses outputs from niri JSON.
 */
function parse(jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    var list = [];
    if (Array.isArray(data)) {
        list = data;
    } else if (typeof data === "object" && data !== null) {
        for (var k in data) {
            var item = data[k];
            item.name = k;
            list.push(item);
        }
    }
    return list.map(function (mon) {
        var modes = [];
        if (mon.modes && Array.isArray(mon.modes)) {
            modes = mon.modes.map(function(m) {
                var hz = Math.round(m.refresh_rate > 500 ? m.refresh_rate / 1000 : m.refresh_rate);
                return {
                    w: m.width,
                    h: m.height,
                    hz: hz,
                    raw: m.width + "x" + m.height + "@" + hz + "Hz"
                };
            });
        } else if (mon.availableModes) {
            modes = mon.availableModes.map(parseMode).filter(function(m) { return m !== null; });
        }
        var curW = mon.current_mode ? mon.current_mode.width : (mon.width || 1920);
        var curH = mon.current_mode ? mon.current_mode.height : (mon.height || 1080);
        var curRate = mon.current_mode ? (mon.current_mode.refresh_rate > 500 ? mon.current_mode.refresh_rate / 1000 : mon.current_mode.refresh_rate) : (mon.refreshRate || 60);
        var curScale = mon.logical ? mon.logical.scale : (mon.scale || 1.0);
        var curX = mon.logical ? mon.logical.x : (mon.x || 0);
        var curY = mon.logical ? mon.logical.y : (mon.y || 0);
        return {
            name: mon.name,
            width: curW,
            height: curH,
            refresh: Math.round(curRate),
            scale: curScale,
            x: curX,
            y: curY,
            modes: modes
        };
    });
}

/**
 * Rewrites output block in KDL format for niri.
 */
function setMonitor(kdlText, output, mode, position, scale) {
    var block = 'output "' + output + '" {\n';
    if (mode && mode !== "auto")
        block += '    mode "' + mode + '"\n';
    if (scale)
        block += '    scale ' + scale + '\n';
    if (position && position !== "auto") {
        var p = position.split("x");
        block += '    position x=' + (p[0] || 0) + ' y=' + (p[1] || 0) + '\n';
    }
    block += '}\n';

    var re = new RegExp('output\\s+"' + output + '"\\s*{[^}]*}', 'g');
    if (re.test(kdlText))
        return kdlText.replace(re, block.trim());
    return kdlText.trim() + '\n\n' + block;
}
