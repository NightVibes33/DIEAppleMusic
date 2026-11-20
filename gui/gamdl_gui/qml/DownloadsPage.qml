import QtQuick
import QtQuick.Layouts

PageScroll {
    spacing: 0
    actions: Component {
        Row {
            spacing: 8
            AppButton { visible: Store.activeCount > 0; text: "Stop All"; icon: "stop-f"; onClicked: Store.call("cancel_all") }
            AppButton { text: "Clear Finished"; onClicked: Store.clearFinished() }
        }
    }

    EmptyState {
        visible: Store.jobs.count === 0
        Layout.fillWidth: true
        icon: "download"
        title: "Nothing downloading"
        text: "Paste a link on Home or search the catalog to start a download."
        action: "Go to Home"
        onActionClicked: Store.go("home")
    }

    Repeater {
        model: Store.jobs
        delegate: ColumnLayout {
            id: job
            required property int jobId
            required property string label
            required property string sub
            required property string art
            required property bool done
            required property string summary
            required property bool failed
            readonly property var items: Store.jobModel(jobId)
            Layout.fillWidth: true
            Layout.bottomMargin: 26
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Art { Layout.preferredWidth: 64; Layout.preferredHeight: 64; source: job.art; glyph: "album" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: job.label; color: Theme.text; font.family: Theme.display; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text {
                        Layout.fillWidth: true
                        text: (job.sub ? job.sub + " · " : "") + (job.done ? job.summary
                              : job.items && job.items.count && Store.itemsDone >= 0 ? progressText() : (Store.status || "Looking up the link…"))
                        function progressText() {
                            var d = 0
                            for (var i = 0; i < job.items.count; i++) if (job.items.get(i).status) d++
                            return d + " of " + job.items.count + " done"
                        }
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideRight
                    }
                }
                AppButton { visible: !job.done; text: "Stop"; icon: "stop-f"; onClicked: Store.call("cancel_job", [job.jobId]) }
                AppButton { visible: job.done && job.failed; text: "Retry"; icon: "sync"; onClicked: Store.retryJob(job.jobId) }
            }
            ListHeader { Layout.fillWidth: true; visible: job.items && job.items.count > 0 }
            Repeater {
                model: job.items
                delegate: QueueRow {
                    required property var model
                    required property int index
                    Layout.fillWidth: true
                    it: model
                    jobId: job.jobId
                    striped: index % 2 === 0
                }
            }
        }
    }
}
