import QtQuick
import qs
import qs.services

// The Google popups' way back in when the sign-in needs you — no credentials,
// a dead token, or a scope the token was never granted. Runs the consent
// script and reads the credentials again when it exits (see Google.reconsent),
// so nothing needs restarting afterwards. Only there while it is needed.
PopupButton {
    visible: Google.needsConsent
    live: !Google.consenting
    framed: true
    label: Google.consenting ? "reconnecting…" : "reconnect"
    warn: true
    onTapped: {
        OpenPopup.dismiss();
        Google.reconsent();
    }
}
