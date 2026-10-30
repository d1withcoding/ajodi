/**
 * Read/write helpers for niri animations in config.kdl.
 */

/** Reads whether animations are enabled (i.e. 'off;' is absent). */
function getEnabled(text) {
    var m = /animations\s*\{([^}]*)\}/.exec(text);
    if (!m) return "true";
    return /\boff\b/.test(m[1]) ? "false" : "true";
}

/** Flips animations enabled: adds or removes 'off;' in animations block. */
function setEnabled(text, literal) {
    var re = /(animations\s*\{)([^}]*)(\})/;
    var m = re.exec(text);
    if (!m) return { text: text, ok: false };
    var body = m[2];
    if (literal === "false" || literal === false) {
        if (!/\boff;?/.test(body)) {
            body = "\n    off;\n" + body;
        }
    } else {
        body = body.replace(/\s*\boff;?/g, "");
    }
    return { text: text.replace(re, "$1" + body + "$3"), ok: true };
}

/** Reads the slowdown factor (or default 1.0). */
function getLeafSpeed(text, leaf) {
    var m = /animations\s*\{[^}]*?\bslowdown\s+([0-9.]+)/.exec(text);
    return m ? m[1] : "1.0";
}

/** Sets the slowdown factor inside animations { ... }. */
function setAllSpeeds(text, literal) {
    var re = /(animations\s*\{)([^}]*)(\})/;
    var m = re.exec(text);
    if (!m) return { text: text, ok: false };
    var body = m[2];
    if (/\bslowdown\s+[0-9.]+;?/.test(body)) {
        body = body.replace(/\bslowdown\s+[0-9.]+;?/, "slowdown " + literal + ";");
    } else {
        body = "\n    slowdown " + literal + ";\n" + body;
    }
    return { text: text.replace(re, "$1" + body + "$3"), ok: true };
}

/**
 * Returns a cubic-bezier curve's control points as [x1, y1, x2, y2].
 */
function getCurvePoints(text, name) {
    var re = /curve\s+"cubic-bezier"\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)/;
    var m = re.exec(text);
    if (!m)
        return [0.16, 1.0, 0.3, 1.0];
    return [parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3]), parseFloat(m[4])];
}

/**
 * Sets the curve points in niri animation config.
 */
function setCurvePoints(text, name, x1, y1, x2, y2) {
    var repl = 'curve "cubic-bezier" ' + x1 + " " + y1 + " " + x2 + " " + y2;
    var re = /curve\s+(?:"cubic-bezier"\s+[0-9.-]+\s+[0-9.-]+\s+[0-9.-]+\s+[0-9.-]+|"[^"]*")/g;
    if (!re.test(text))
        return { text: text, ok: false };
    return { text: text.replace(re, repl), ok: true };
}
