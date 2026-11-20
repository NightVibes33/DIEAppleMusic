import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PromptSheet {
    id: s
    title: "Two-factor authentication"
    subtitle: "Enter the verification code sent to your Apple devices."
    onOpened: code.forceActiveFocus()
    Field {
        id: code
        Layout.fillWidth: true
        implicitHeight: 56
        maximumLength: 6
        horizontalAlignment: TextInput.AlignHCenter
        font.family: Theme.mono
        font.pixelSize: 26
        font.letterSpacing: 12
        inputMethodHints: Qt.ImhDigitsOnly
        onAccepted: s.answer(text)
    }
    footer: [
        Item { Layout.fillWidth: true },
        AppButton { text: "Cancel"; kind: "quiet"; onClicked: s.cancel() },
        AppButton { text: "Continue"; kind: "primary"; onClicked: s.answer(code.text) }
    ]
}
