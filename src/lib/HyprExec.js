.pragma library

// A command for Hyprland to start, as the Lua call its dispatcher takes:
// `hl.dsp.exec_cmd("<line>", <rules>)`. Hyprland hands the line to sh, so each
// word is quoted for sh, and the line is then written as a Lua string. Not
// with JSON.stringify: JSON's \u0001 is a syntax error in Lua, and the
// command would fail without a word.
//
// `rules` is a Lua table literal from the caller's own code ("{ float = true }"),
// `dir` a folder to start in, or "".
function dispatch(argv, rules, dir) {
    const sh = word => "'" + String(word).replace(/'/g, "'\\''") + "'";
    const line = (dir ? `cd ${sh(dir)} && ` : "") + argv.map(sh).join(" ");
    return `hl.dsp.exec_cmd(${lua(line)}, ${rules})`;
}

// A Lua string literal: quote and backslash escaped, and control
// characters as decimal escapes, which every Lua reads. The rest goes as is.
function lua(text) {
    let out = "";
    for (const c of text) {
        const code = c.codePointAt(0);
        if (c === '"' || c === "\\")
            out += "\\" + c;
        else if (code < 0x20 || code === 0x7f)
            out += "\\" + String(code).padStart(3, "0");
        else
            out += c;
    }
    return '"' + out + '"';
}
