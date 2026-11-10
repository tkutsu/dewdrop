.pragma library

// Encode a local path without treating its filename as a query or fragment.
function fromPath(path) {
    return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
}

// FolderListModel reparses its decoded path as a URL. A Linux double-leading
// slash keeps that second parse from truncating #/? or decoding percent escapes.
function forFolderModel(path) {
    return path ? fromPath("/" + path) : "";
}
