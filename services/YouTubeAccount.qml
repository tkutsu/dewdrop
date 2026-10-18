pragma Singleton

import QtQuick
import qs

// The sign-in Feeds reads subscriptions with. Its own, apart from Google.qml,
// because subscriptions often live on a brand account, which has no Gmail,
// Tasks or Calendar of its own: one token cannot serve both.
// `gtasks-auth --youtube` writes it, reusing the main account's OAuth client.
GoogleAccount {
    file: "youtube.json"
    consentArgs: ["--youtube"]
}
