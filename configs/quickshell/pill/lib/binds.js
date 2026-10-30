function isKdl(text) {
    return text.indexOf("binds {") !== -1 || text.indexOf("binds{") !== -1;
}

function readMod(text) {
    if (isKdl(text)) return "Mod";
    var m = text.match(/^\s*local\s+mod\s*=\s*"([^"]*)"/m);
    return m ? m[1] : "SUPER";
}

function isMouseCombo(combo) {
    return /mouse:|mouse_up|mouse_down|wheel/i.test(combo);
}

function optsHasMouse(opts) {
    return /\bmouse\s*=\s*true\b/.test(opts);
}

function strEnd(s, i) {
    for (var j = i + 1; j < s.length; j++) {
        if (s[j] === "\\") j++;
        else if (s[j] === '"') return j;
    }
    return -1;
}

function splitArgs(inner) {
    var args = [];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < inner.length; i++) {
        var c = inner[i];
        if (c === '"') {
            i = strEnd(inner, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(' || c === '{' || c === '[') depth++;
        else if (c === ')' || c === '}' || c === ']') depth--;
        else if (c === ',' && depth === 0) {
            args.push(inner.slice(start, i));
            start = i + 1;
        }
    }
    args.push(inner.slice(start));
    return args.map(function (a) { return a.trim(); });
}

function resolveCombo(firstArg, modValue) {
    var modMatch = firstArg.match(/^mod\s*\.\.\s*"([^"]*)"$/);
    if (modMatch) {
        return { combo: modValue + modMatch[1] };
    }
    var litMatch = firstArg.match(/^"([^"]*)"$/);
    if (litMatch) {
        return { combo: litMatch[1] };
    }
    return { combo: firstArg };
}

function deriveLabel(action) {
    var exec = action.match(/exec_cmd\(\s*"([^"]*)"\s*\)/);
    if (exec) {
        var cmd = exec[1];
        var script = cmd.match(/\/scripts\/([^\/]+)\.sh\b/);
        if (script) return script[1];
        return cmd.split(/\s+/)[0];
    }
    var execEnv = action.match(/exec_cmd\(\s*os\.getenv\([^)]*\)\s*\.\.\s*"([^"]*)"/);
    if (execEnv) {
        var path = execEnv[1];
        var s = path.match(/\/scripts\/([^\/]+)\.sh\b/);
        if (s) return s[1];
        return path;
    }

    if (/window\.kill\b/.test(action)) return "kill window";
    if (/window\.close\b|close-window/.test(action)) return "close window";
    if (/window\.fullscreen\b|fullscreen-window/.test(action)) return "fullscreen";
    if (/window\.float\b|toggle-window-floating/.test(action)) return "float";
    if (/window\.move\b|move-column-to-workspace/.test(action)) return "move to workspace";
    if (/focus-workspace/.test(action)) return "focus workspace";
    if (/window\.drag\b/.test(action)) return "drag window";
    if (/window\.resize\b/.test(action)) return "resize window";

    var ws = action.match(/focus\(\s*{\s*workspace\s*=\s*"r([+-]\d+)"/);
    if (ws) return "workspace " + ws[1];

    return action.replace(/^hl\.dsp\./, "").replace(/\(\)$/, "").replace(/-/g, " ");
}

function nameComment(raw, closeIndex) {
    var rest = raw.slice(closeIndex + 1);
    var m = rest.match(/(?:--|\/\/)\s?(.*)$/);
    return m ? m[1].trim() : "";
}

function isExecAction(action) {
    return /exec_cmd\s*\(/.test(action) || /^spawn\b/.test(action);
}

function execCmd(action) {
    var m = action.match(/exec_cmd\(\s*"((?:[^"\\]|\\.)*)"\s*\)/);
    if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    if (/^spawn\b/.test(action)) {
        var parts = [];
        var re = /"([^"\\]*(?:\\.[^"\\]*)*)"/g;
        var sm;
        while ((sm = re.exec(action)) !== null) {
            parts.push(sm[1].replace(/\\"/g, '"').replace(/\\\\/g, "\\"));
        }
        return parts.join(" ");
    }
    return "";
}

function parseKdlLine(raw, lineIndex) {
    var m = raw.match(/^\s*([A-Za-z0-9_+]+)(?:\s+[a-z\-]+=[a-z0-9]+)*\s*\{\s*([^;]+?);\s*\}(?:\s*\/\/\s*(.*))?$/);
    if (!m) return null;

    var combo = m.group ? m.group(1) : m[1];
    var action = (m.group ? m.group(2) : m[2]).trim();
    var name = (m.group ? m.group(3) : m[3]) || "";
    name = name.trim();
    var isExec = isExecAction(action);

    return {
        combo: combo,
        label: name.length ? name : deriveLabel(action),
        name: name,
        action: action,
        cmd: execCmd(action),
        isExec: isExec,
        isMouse: isMouseCombo(combo),
        lineIndex: lineIndex
    };
}

function parseLuaLine(raw, lineIndex, modValue) {
    var open = raw.indexOf("hl.bind(");
    if (open === -1) return null;

    var depth = 0;
    var startInner = open + "hl.bind(".length;
    var endInner = -1;
    for (var i = startInner - 1; i < raw.length; i++) {
        var c = raw[i];
        if (c === '"') {
            i = strEnd(raw, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(') depth++;
        else if (c === ')') {
            depth--;
            if (depth === 0) { endInner = i; break; }
        }
    }
    if (endInner === -1) return null;

    var inner = raw.slice(startInner, endInner);
    var args = splitArgs(inner);
    if (args.length < 2) return null;

    var resolved = resolveCombo(args[0], modValue);
    var action = args[1];
    var opts = args.length >= 3 ? args.slice(2).join(", ") : "";

    var name = nameComment(raw, endInner);
    var mouse = isMouseCombo(resolved.combo) || optsHasMouse(opts);

    return {
        combo: resolved.combo,
        label: name.length ? name : deriveLabel(action),
        name: name,
        action: action,
        cmd: execCmd(action),
        isExec: isExecAction(action),
        isMouse: mouse,
        lineIndex: lineIndex
    };
}

function parse(text) {
    var kdl = isKdl(text);
    var modValue = readMod(text);
    var lines = text.split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var entry = kdl ? parseKdlLine(lines[i], i) : parseLuaLine(lines[i], i, modValue);
        if (entry) out.push(entry);
    }
    return out;
}

function rebind(text, lineIndex, newCombo) {
    var lines = text.split("\n");
    if (lineIndex < 0 || lineIndex >= lines.length) {
        return { text: text, ok: false, error: "invalid lineIndex" };
    }

    var raw = lines[lineIndex];

    if (isKdl(text)) {
        var m = raw.match(/^(\s*)([A-Za-z0-9_+]+)(\s*.*)$/);
        if (!m) return { text: text, ok: false, error: "no bind on line" };
        lines[lineIndex] = m[1] + newCombo + m[3];
        return { text: lines.join("\n"), ok: true, error: "" };
    }

    var modValue = readMod(text);
    var open = raw.indexOf("hl.bind(");
    if (open === -1) {
        return { text: text, ok: false, error: "no hl.bind on line" };
    }

    var startInner = open + "hl.bind(".length;
    var firstEnd = -1;
    var depth = 0;
    for (var i = startInner; i < raw.length; i++) {
        var c = raw[i];
        if (c === '"') {
            i = strEnd(raw, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(' || c === '{' || c === '[') depth++;
        else if (c === ')' || c === '}' || c === ']') depth--;
        else if (c === ',' && depth === 0) {
            firstEnd = i;
            break;
        }
    }
    if (firstEnd === -1) {
        return { text: text, ok: false, error: "malformed hl.bind" };
    }

    var firstRaw = raw.slice(startInner, firstEnd);
    var leading = firstRaw.match(/^\s*/)[0];
    var trailing = firstRaw.match(/\s*$/)[0];

    var modPrefix = modValue + " + ";
    var firstArg;
    if (newCombo.indexOf(modPrefix) === 0) {
        firstArg = 'mod .. " + ' + newCombo.slice(modPrefix.length) + '"';
    } else {
        firstArg = '"' + newCombo + '"';
    }

    var newFirstRaw = leading + firstArg + trailing;
    var newLine = raw.slice(0, startInner) + newFirstRaw + raw.slice(firstEnd);
    lines[lineIndex] = newLine;

    return { text: lines.join("\n"), ok: true, error: "" };
}

function inUse(text, newCombo, exceptLineIndex) {
    var entries = parse(text);
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].lineIndex === exceptLineIndex) continue;
        if (entries[i].combo === newCombo) return true;
    }
    return false;
}

function comboExpr(combo, modValue) {
    var modPrefix = modValue + " + ";
    if (combo.indexOf(modPrefix) === 0)
        return 'mod .. " + ' + combo.slice(modPrefix.length) + '"';
    return '"' + combo + '"';
}

function escapeCmd(cmd) {
    return cmd.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function closeParenIndex(raw, open) {
    var depth = 0;
    for (var i = open + "hl.bind(".length - 1; i < raw.length; i++) {
        var c = raw[i];
        if (c === '"') {
            i = strEnd(raw, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(') depth++;
        else if (c === ')') {
            depth--;
            if (depth === 0) return i;
        }
    }
    return -1;
}

function argStart(raw, innerStart, nth) {
    var depth = 0;
    var seen = -1;
    for (var i = innerStart; i < raw.length; i++) {
        var c = raw[i];
        if (c === '"') {
            i = strEnd(raw, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(' || c === '{' || c === '[') depth++;
        else if (c === ')' || c === '}' || c === ']') {
            if (depth === 0) return -1;
            depth--;
        } else if (c === ',' && depth === 0) {
            seen++;
            if (seen === nth) return i + 1;
        }
    }
    return -1;
}

function argRange(raw, argIndex) {
    var open = raw.indexOf("hl.bind(");
    if (open === -1) return null;
    var innerStart = open + "hl.bind(".length;
    var close = closeParenIndex(raw, open);
    if (close === -1) return null;

    var start = argIndex === 0 ? innerStart : argStart(raw, innerStart, argIndex - 1);
    if (start === -1) return null;

    var end = argStart(raw, start, 0);
    if (end === -1) end = close;
    else end = end - 1;
    return { start: start, end: end };
}

function add(text, combo, cmd, name) {
    if (!combo || !combo.length)
        return { text: text, ok: false, error: "empty combo" };
    if (!cmd || !cmd.length)
        return { text: text, ok: false, error: "empty command" };

    var lines = text.split("\n");

    if (isKdl(text)) {
        var line = "    " + combo + ' { spawn "' + escapeCmd(cmd) + '"; }';
        if (name && name.length)
            line += " // " + name;

        // Insert before closing brace of binds block
        var insertAt = lines.length - 1;
        for (var i = lines.length - 1; i >= 0; i--) {
            if (lines[i].trim() === "}") {
                insertAt = i;
                break;
            }
        }
        lines.splice(insertAt, 0, line);
        return { text: lines.join("\n"), ok: true, error: "" };
    }

    var modValue = readMod(text);
    var first = comboExpr(combo, modValue);
    var line = "hl.bind(" + first + ', hl.dsp.exec_cmd("' + escapeCmd(cmd) + '"))';
    if (name && name.length)
        line += " -- " + name;

    var insertAt = lines.length;
    for (var i = lines.length - 1; i >= 0; i--) {
        if (lines[i].trim().length) { insertAt = i + 1; break; }
        insertAt = i;
    }
    lines.splice(insertAt, 0, line);
    return { text: lines.join("\n"), ok: true, error: "" };
}

function del(text, lineIndex) {
    var lines = text.split("\n");
    if (lineIndex < 0 || lineIndex >= lines.length)
        return { text: text, ok: false, error: "invalid lineIndex" };
    lines.splice(lineIndex, 1);
    return { text: lines.join("\n"), ok: true, error: "" };
}

function editCmd(text, lineIndex, cmd) {
    var lines = text.split("\n");
    if (lineIndex < 0 || lineIndex >= lines.length)
        return { text: text, ok: false, error: "invalid lineIndex" };

    var raw = lines[lineIndex];

    if (isKdl(text)) {
        var newLine = raw.replace(/\{\s*spawn\s+[^;]+;\s*\}/, '{ spawn "' + escapeCmd(cmd) + '"; }');
        if (newLine === raw) {
            newLine = raw.replace(/\{\s*[^;]+;\s*\}/, '{ spawn "' + escapeCmd(cmd) + '"; }');
        }
        lines[lineIndex] = newLine;
        return { text: lines.join("\n"), ok: true, error: "" };
    }

    var range = argRange(raw, 1);
    if (!range)
        return { text: text, ok: false, error: "could not isolate dispatch arg" };

    var slice = raw.slice(range.start, range.end);
    var leading = slice.match(/^\s*/)[0];
    var trailing = slice.match(/\s*$/)[0];
    var dispatch = 'hl.dsp.exec_cmd("' + escapeCmd(cmd) + '")';

    lines[lineIndex] = raw.slice(0, range.start) + leading + dispatch + trailing + raw.slice(range.end);
    return { text: lines.join("\n"), ok: true, error: "" };
}

function balanceOk(s) {
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (c === '"') {
            i = strEnd(s, i);
            if (i < 0) break;
            continue;
        }
        if (c === '(' || c === '{' || c === '[') depth++;
        else if (c === ')' || c === '}' || c === ']') {
            depth--;
            if (depth < 0) return false;
        }
    }
    return depth === 0 && i === s.length;
}

function editAction(text, lineIndex, action) {
    var lines = text.split("\n");
    if (lineIndex < 0 || lineIndex >= lines.length)
        return { text: text, ok: false, error: "invalid lineIndex" };

    var raw = lines[lineIndex];

    if (isKdl(text)) {
        lines[lineIndex] = raw.replace(/\{\s*[^;]+;\s*\}/, "{ " + action.replace(/;$/, "") + "; }");
        return { text: lines.join("\n"), ok: true, error: "" };
    }

    if (!balanceOk(action))
        return { text: text, ok: false, error: "unbalanced () or quote" };

    var range = argRange(raw, 1);
    if (!range)
        return { text: text, ok: false, error: "could not isolate dispatch arg" };

    var slice = raw.slice(range.start, range.end);
    var leading = slice.match(/^\s*/)[0];
    var trailing = slice.match(/\s*$/)[0];

    lines[lineIndex] = raw.slice(0, range.start) + leading + action + trailing + raw.slice(range.end);
    return { text: lines.join("\n"), ok: true, error: "" };
}

function editName(text, lineIndex, name) {
    var lines = text.split("\n");
    if (lineIndex < 0 || lineIndex >= lines.length)
        return { text: text, ok: false, error: "invalid lineIndex" };

    var raw = lines[lineIndex];

    if (isKdl(text)) {
        var head = raw.replace(/\s*\/\/.*$/, "");
        if (name && name.length)
            head += " // " + name;
        lines[lineIndex] = head;
        return { text: lines.join("\n"), ok: true, error: "" };
    }

    var open = raw.indexOf("hl.bind(");
    if (open === -1)
        return { text: text, ok: false, error: "no hl.bind on line" };
    var close = closeParenIndex(raw, open);
    if (close === -1)
        return { text: text, ok: false, error: "unterminated bind" };

    var head = raw.slice(0, close + 1);
    var rest = raw.slice(close + 1).replace(/\s*--.*$/, "");
    var line = head + rest;
    if (name && name.length)
        line += " -- " + name;

    lines[lineIndex] = line;
    return { text: lines.join("\n"), ok: true, error: "" };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { parse, rebind, add, del, editCmd, editAction, editName, execCmd, balanceOk, inUse };
}
