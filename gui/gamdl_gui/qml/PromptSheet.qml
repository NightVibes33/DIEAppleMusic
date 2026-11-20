import QtQuick

// Base for engine prompts: answers exactly once, cancels if dismissed.
Sheet {
    id: ps
    property var prompt
    property bool answered: false
    function answer(value) { if (answered) return; answered = true; Store.call("answer", [prompt.id, value, false]); close() }
    function cancel() { if (answered) return; answered = true; Store.call("answer", [prompt.id, null, true]); close() }
    onClosed: if (!answered) { answered = true; Store.call("answer", [prompt.id, null, true]) }
}
