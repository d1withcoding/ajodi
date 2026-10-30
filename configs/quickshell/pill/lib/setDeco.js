/**
 * Read/write helpers for window decorations and layout in both KDL (niri) and Lua.
 */

function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Returns a field's value with surrounding quotes stripped, or "" when absent.
 * Supports Lua `name = value` and KDL `name value;`.
 */
function getField(text, name) {
    // 1. Try Lua style: name = value
    var reLua = new RegExp("\\b" + escapeRe(name) + "\\s*=\\s*(\"[^\"]*\"|[^,}\\n]*)");
    var m = reLua.exec(text);
    if (m) {
        var v = m[1].trim();
        if (v.length >= 2 && v.charAt(0) === "\"" && v.charAt(v.length - 1) === "\"")
            return v.slice(1, -1);
        return v;
    }

    // 2. Try KDL style: name value; or name value
    var kdlName = name;
    if (name === "gaps_in" || name === "gaps_out") kdlName = "gaps";
    else if (name === "rounding") kdlName = "geometry-corner-radius";
    else if (name === "border_size") kdlName = "width";

    var reKdl = new RegExp("(?:^|\\n|\\s)" + escapeRe(kdlName) + "\\s+(\"[^\"]*\"|[^;{\\n]+)");
    var mKdl = reKdl.exec(text);
    if (mKdl) {
        var vk = mKdl[1].trim();
        if (vk.length >= 2 && vk.charAt(0) === "\"" && vk.charAt(vk.length - 1) === "\"")
            return vk.slice(1, -1);
        return vk;
    }
    return "";
}

/**
 * Replaces a field's value. Supports Lua and KDL.
 */
function setField(text, name, valueLiteral) {
    // 1. Try Lua style
    var reLua = new RegExp("(\\b" + escapeRe(name) + "\\s*=\\s*)(\"[^\"]*\"|[^,}\\n]*)");
    if (reLua.test(text)) {
        return { text: text.replace(reLua, "$1" + valueLiteral), ok: true };
    }

    // 2. Try KDL style
    var kdlName = name;
    if (name === "gaps_in" || name === "gaps_out") kdlName = "gaps";
    else if (name === "rounding") kdlName = "geometry-corner-radius";
    else if (name === "border_size") kdlName = "width";

    var reKdl = new RegExp("((?:^|\\n|\\s)" + escapeRe(kdlName) + "\\s+)(\"[^\"]*\"|[^;{\\n]+)");
    if (reKdl.test(text)) {
        return { text: text.replace(reKdl, "$1" + valueLiteral), ok: true };
    }
    return { text: text, ok: false };
}

/**
 * Finds the body of a block { ... }. Matches both `name = {` and `name {`.
 */
function getBlock(text, blockName) {
    var head = new RegExp("\\b" + escapeRe(blockName) + "(?:\\s*=\\s*|\\s*)\\{");
    var m = head.exec(text);
    if (!m)
        return null;
    var open = m.index + m[0].length - 1;
    var depth = 0;
    for (var i = open; i < text.length; i++) {
        var c = text.charAt(i);
        if (c === "{") {
            depth++;
        } else if (c === "}") {
            depth--;
            if (depth === 0)
                return { start: open + 1, end: i, body: text.slice(open + 1, i) };
        }
    }
    return null;
}

function getBlockField(text, blockName, name) {
    var blk = getBlock(text, blockName);
    if (!blk)
        return "";

    // Special case for niri shadow / border "enabled" / "on"
    if (name === "enabled" || name === "on") {
        if (/\bon\b/.test(blk.body)) return "true";
        if (/\boff\b/.test(blk.body)) return "false";
    }

    return getField(blk.body, name);
}

function setBlockField(text, blockName, name, valueLiteral) {
    var blk = getBlock(text, blockName);
    if (!blk)
        return { text: text, ok: false };

    // Special case for niri shadow / border on/off
    if (name === "enabled" || name === "on") {
        var newBody = blk.body;
        if (valueLiteral === "true" || valueLiteral === true) {
            newBody = newBody.replace(/\boff\b/, "on");
        } else {
            newBody = newBody.replace(/\bon\b/, "off");
        }
        return { text: text.slice(0, blk.start) + newBody + text.slice(blk.end), ok: true };
    }

    var res = setField(blk.body, name, valueLiteral);
    if (!res.ok)
        return { text: text, ok: false };
    return { text: text.slice(0, blk.start) + res.text + text.slice(blk.end), ok: true };
}

/**
 * Returns { start, end } of the first named rule call.
 */
function findNamedRule(text, ruleName) {
    var head = /(?:hl\.layer_rule|window-rule)\s*(?:\(\s*\{|\{)/g;
    var nameRe = new RegExp("(?:name|match app-id)\\s*=\\s*\"" + escapeRe(ruleName) + "\"");
    var m;
    while ((m = head.exec(text)) !== null) {
        var open = text.indexOf("{", m.index);
        var depth = 0;
        for (var i = open; i < text.length; i++) {
            var c = text.charAt(i);
            if (c === "{") {
                depth++;
            } else if (c === "}") {
                depth--;
                if (depth === 0) {
                    var close = text.indexOf(")", i);
                    if (close === -1 || close > i + 3)
                        close = i;
                    var end = close + 1;
                    if (nameRe.test(text.slice(m.index, end)))
                        return { start: m.index, end: end };
                    break;
                }
            }
        }
    }
    return null;
}

function hasNamedRule(text, ruleName) {
    return findNamedRule(text, ruleName) !== null;
}

function removeNamedRule(text, ruleName) {
    var r = findNamedRule(text, ruleName);
    if (!r)
        return { text: text, ok: false };
    var start = r.start;
    if (text.charAt(start - 1) === "\n" && text.charAt(start - 2) === "\n")
        start--;
    var end = r.end;
    if (text.charAt(end) === "\n")
        end++;
    return { text: text.slice(0, start) + text.slice(end), ok: true };
}

function addNamedRule(text, block) {
    if (text.indexOf(block) !== -1)
        return { text: text, ok: false };
    var sep = text.length === 0 || text.charAt(text.length - 1) === "\n" ? "\n" : "\n\n";
    return { text: text + sep + block, ok: true };
}
