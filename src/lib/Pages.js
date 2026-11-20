.pragma library

// A Google list read to its end. A reply holds a few hundred items at most
// and a nextPageToken for the rest, and a list longer than one page is the
// one whose tail matters.
//
// `ask(token, ok, fail)` asks for one page ("" for the first) and answers
// through Http's two callbacks. Each reply goes to `take(body)`, which
// returns false to stop there (an answer to a request since replaced). Then
// `done()` after the last page, or `failed(why, status)` once. A token
// handed back twice would go round for ever, so it ends the walk as a
// failure.
function walk(ask, take, done, failed) {
    const asked = {};
    const page = function (token) {
        ask(token, function (body) {
            if (take(body) === false)
                return;
            const next = body?.nextPageToken;
            if (!next) {
                done();
            } else if (asked[next]) {
                failed("The server repeated a page token", 0);
            } else {
                asked[next] = true;
                page(next);
            }
        }, failed);
    };
    page("");
}

// `url` with `token`'s page asked for: the first page is the URL as it is.
function url(url, token) {
    return token === "" ? url : `${url}&pageToken=${encodeURIComponent(token)}`;
}
