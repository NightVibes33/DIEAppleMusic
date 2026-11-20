import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PromptSheet {
    id: s
    title: "Sign in through your wrapper"
    subtitle: "The wrapper service needs your Apple ID to start a session. " + Theme.appName + " passes these straight to it."
    onOpened: user.forceActiveFocus()
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        Text { text: "Apple ID"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        Field { id: user; Layout.fillWidth: true }
        Text { text: "Password"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; Layout.topMargin: 8 }
        Field { id: pass; Layout.fillWidth: true; echoMode: TextInput.Password; onAccepted: s.answer({ user: user.text, password: pass.text }) }
    }
    footer: [
        Item { Layout.fillWidth: true },
        AppButton { text: "Cancel"; kind: "quiet"; onClicked: s.cancel() },
        AppButton { text: "Sign In"; kind: "primary"; onClicked: s.answer({ user: user.text, password: pass.text }) }
    ]
}
