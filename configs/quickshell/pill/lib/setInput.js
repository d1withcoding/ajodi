.import "setDeco.js" as Deco

/** Field reads and writes share setDeco's matchers. */
var getField = Deco.getField;
var setField = Deco.setField;

/**
 * Replaces the value of an env var. Supports KDL `KEY "value"` and Lua `hl.env("KEY", ...)`.
 */
function setEnv(text, key, valueRaw) {
    var reLua = new RegExp("(hl\\.env\\(\\s*\"" + Deco.escapeRe(key) + "\"\\s*,\\s*)\"[^\"]*\"");
    if (reLua.test(text)) {
        return { text: text.replace(reLua, "$1\"" + valueRaw + "\""), ok: true };
    }

    var reKdl = new RegExp("(\\b" + Deco.escapeRe(key) + "\\s+)\"[^\"]*\"");
    if (reKdl.test(text)) {
        return { text: text.replace(reKdl, "$1\"" + valueRaw + "\""), ok: true };
    }

    return { text: text, ok: false };
}

/**
 * Replaces theme and size in cursor config (KDL cursor block or setcursor script).
 */
function setCursorLine(text, theme, size) {
    var changed = false;
    var out = text;

    if (/setcursor\s+\S+\s+\d+/.test(out)) {
        out = out.replace(/setcursor\s+\S+\s+\d+/, "setcursor " + theme + " " + size);
        changed = true;
    }

    if (/xcursor-theme\s+"[^"]*"/.test(out)) {
        out = out.replace(/xcursor-theme\s+"[^"]*"/, 'xcursor-theme "' + theme + '"');
        changed = true;
    }

    if (/xcursor-size\s+\d+/.test(out)) {
        out = out.replace(/xcursor-size\s+\d+/, "xcursor-size " + size);
        changed = true;
    }

    return { text: out, ok: changed };
}
