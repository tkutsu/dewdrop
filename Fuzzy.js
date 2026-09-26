.pragma library

// fzf-v1-style fuzzy scorer, standing in for rofi's `matching: "normal"` plus
// `tokenize: true`. Returns a number (higher = better) or null when the query
// is not a subsequence of the text.
//
// Callers score one term against several fields and keep the best, so the
// numbers here only ever have to be comparable with each other.

// rofi ran with `normalize-match: true`, which matches accented text from an
// unaccented query. NFD splits a precomposed letter into its base plus a
// combining mark, and U+0300-U+036F is the block those marks live in, so
// dropping them leaves the base letter: "Téléchargé" becomes "Telecharge" and
// "Καφές" becomes "Καφες".
//
// Deliberately not \p{Diacritic}: the explicit range says which marks are
// meant, and does not lean on a regex feature Qt's JS engine only recently
// grew.
function fold(s) {
    return String(s).normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

// True when position i starts a "word" (after a separator or a camelCase hump)
function isBoundary(text, i) {
    const p = text[i - 1];
    const c = text[i];
    if (" -_./".indexOf(p) !== -1) return true;
    return p === p.toLowerCase() && c !== c.toLowerCase();
}

// Folding is the expensive half of a score: normalize() builds a new string
// and the regex walks it, and this used to pay for it on the text and on the
// query alike, once per call. Against a few hundred app names that is nothing.
// Against ten thousand track titles, on every keystroke, it is the whole cost
// — measured over this machine's library at 7ms a term, against 1ms once the
// text has been folded in advance.
//
// So the two halves come apart. prep() is what a caller holding a long list
// does once, when the list is built; scorePrepped() is what it calls per
// keystroke. score() does all of it in one call, for a caller with nothing to
// keep a list in.
function prep(text) {
    // The folded-but-cased string as well as the lowercased one: isBoundary
    // reads the first to find camelCase humps, so it has to be indexed the
    // same way as the string the match walks.
    const raw = fold(text);
    return [raw, raw.toLowerCase()];
}

function prepQuery(query) {
    return fold(query).toLowerCase();
}

function score(query, text) {
    if (!text) return null;
    const p = prep(text);
    return scorePrepped(prepQuery(query), p[0], p[1]);
}

// `q` folded and lowercased, `raw` folded, `t` folded and lowercased — i.e.
// prepQuery(query) and the two halves of prep(text), in that order.
function scorePrepped(q, raw, t) {
    if (!q) return 0;

    // Both scans below hop with indexOf rather than stepping character by
    // character. Same walk, same answer — but a step of the loop is a native
    // string search for the next occurrence instead of an interpreted
    // comparison per character, and against a library this is nearly all of
    // the work: ten thousand titles rejected on their first missing letter.
    // Ranking "red hot" against this library was 160ms stepping and 30ms
    // hopping, measured through Library.search on the same data.

    // Pass 1 (forward): find the earliest position where the whole query has matched
    let qi = 0, end = -1, at = 0;
    for (qi = 0; qi < q.length; qi++) {
        at = t.indexOf(q[qi], at);
        if (at < 0) return null;
        at++;
    }
    end = at - 1;

    // Pass 2 (backward): walk back from end to find the tightest start,
    // so "fx" in "firefox" matches "fox" rather than "f...x" across the word
    let start = end;
    for (qi = q.length - 1, at = end; qi >= 0; qi--) {
        start = t.lastIndexOf(q[qi], at);
        at = start - 1;
    }

    // Score matched characters inside the [start, end] window
    let s = 0, prev = -2, heads = 0;
    qi = 0;
    for (let i = start; i <= end && qi < q.length; i++) {
        if (t[i] !== q[qi]) continue;
        const head = i === 0 || isBoundary(raw, i);
        let b = 16;                          // base per matched char
        if (i === 0) b += 12;                // start of string
        else if (head) b += 8;               // start of a word
        if (prev === i - 1) b += 6;          // consecutive run
        if (head) heads++;
        s += b;
        prev = i;
        qi++;
    }

    // Every character of the query landing on the first letter of a word: an
    // initialism, and by far the most likely thing a short scattered match
    // actually is. Without this "rhcp" scored 78 against Red Hot Chili Peppers
    // and 60 against Anarchy Camp — a band and a song that merely has those
    // four letters in that order — because both are equally scattered and the
    // per-character bonuses could not tell "spread across a phrase" from
    // "spread across its initials". Ten thousand track titles is where that
    // stops being academic.
    //
    // Scaled by length rather than flat, so a four-letter initialism outranks
    // a two-letter one that got lucky, and skipped for a single character,
    // which is an initialism of nothing.
    if (heads === q.length && q.length > 1) s += 10 * q.length;

    s -= (end - start + 1 - q.length) * 2;   // penalise gaps inside the match
    // Capped: a preference, not a penalty that grows without limit. A match
    // at character 200 of a long title would otherwise score below zero, and
    // anything that cuts against the best score cannot reason about that.
    s -= Math.min(start * 0.5, 10);
    if (t === q) s += 40;                    // exact match
    else if (t.startsWith(q)) s += 20;       // prefix match
    return s;
}
