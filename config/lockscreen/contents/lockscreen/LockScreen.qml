/*
    Apollo lock screen.

    kscreenlocker asks PAM as soon as the greeter starts. The built-in
    fallback theme calls authenticator.respond() from onPromptForSecretChanged,
    and that signal runs inside PamAuthenticator::promptInternal before
    m_pendingPrompt is stored, so the typed password is thrown away. Unlock
    then finds the worker still inside the first conversation and fails.

    Respond only after that slot has returned (Qt.callLater), and only with
    the password the user submitted.
*/
import QtQuick 2.15
import QtQuick.Layouts 1.15

import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.plasma.components 3.0 as PlasmaComponents

Item {
    id: root

    property string notice: ""
    property bool submitted: false
    property string submittedPassword: ""
    property bool promptPending: false
    property bool sawPrompt: false
    // tryUnlock() before the worker is ready does not start PAM and does not
    // report failure. Once busy has been true, a conversation exists; calling
    // startAuthenticating() again makes the worker return Failure.
    property bool authStarted: false

    function submit() {
        submittedPassword = password.text
        submitted = true
        notice = ""
        if (promptPending) {
            Qt.callLater(flush)
        } else {
            authenticator.startAuthenticating()
        }
    }

    function flush() {
        if (!submitted || !promptPending) {
            return
        }
        var pw = submittedPassword
        submitted = false
        promptPending = false
        authenticator.respond(pw)
    }

    function notePrompt() {
        sawPrompt = true
        promptPending = true
        if (submitted) {
            Qt.callLater(flush)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#1b1e24"
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 4, Kirigami.Units.gridUnit * 18)

        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: kscreenlocker_userName.length === 0
                  ? "The session is locked"
                  : "The session has been locked by " + kscreenlocker_userName
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: "#ffb4ab"
            visible: root.notice.length > 0
            text: root.notice
            wrapMode: Text.WordWrap
        }

        PlasmaExtras.PasswordField {
            id: password
            Layout.fillWidth: true
            enabled: !authenticator.busy && !root.submitted
            placeholderText: "Password"
            focus: true
            onAccepted: root.submit()
        }

        PlasmaComponents.Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Unlock"
            enabled: !authenticator.busy && !root.submitted
            onClicked: root.submit()
        }
    }

    // The greeter starts PAM before this item exists. If the secret prompt
    // was already delivered, the property is set and the signal was missed.
    Timer {
        interval: 200
        repeat: true
        running: !root.sawPrompt && !authenticator.unlocked
        onTriggered: {
            if (authenticator.promptForSecret && authenticator.promptForSecret.length > 0) {
                root.notePrompt()
                return
            }
            if (!root.authStarted) {
                authenticator.startAuthenticating()
            }
        }
    }

    Connections {
        target: authenticator

        function onBusyChanged() {
            if (authenticator.busy) {
                root.authStarted = true
            }
        }

        function onPromptForSecretChanged() {
            root.notePrompt()
        }

        function onFailed(kind) {
            if (kind !== 0) {
                return
            }
            root.promptPending = false
            root.submitted = false
            root.authStarted = false
            root.notice = "Unlocking failed"
            password.text = ""
            password.forceActiveFocus()
            authenticator.startAuthenticating()
        }

        function onSucceeded() {
            Qt.quit()
        }

        function onErrorMessageChanged() {
            if (authenticator.errorMessage.length > 0) {
                root.notice = authenticator.errorMessage
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
