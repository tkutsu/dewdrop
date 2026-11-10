.pragma library

// Soften all-uppercase metadata while preserving intentional mixed case.
function display(text) {
    return text === text.toUpperCase() ? text.toLowerCase() : text;
}
