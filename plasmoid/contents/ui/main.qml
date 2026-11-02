pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.components as PlasmaComponents3

PlasmoidItem {
    id: root

    property var usage: null
    property string errorMessage: ""
    property bool loading: false
    property string capturedAt: ""
    property int ageTick: 0
    readonly property int refreshInterval: Math.max(10, plasmoid.configuration.refreshInterval || 20)
    readonly property bool showDetails: plasmoid.configuration.showDetails !== false

    readonly property string statusCommand: "/bin/sh -c 'exec \"$HOME/.local/bin/codex-usage\" status --json'"

    Plasmoid.icon: "utilities-system-monitor-symbolic"
    Plasmoid.status: usage === null ? PlasmaCore.Types.PassiveStatus : PlasmaCore.Types.ActiveStatus

    function refresh() {
        if (loading)
            return;
        loading = true;
        errorMessage = "";
        commandSource.connectSource(statusCommand);
    }

    function setResult(data) {
        loading = false;
        var exitCode = data["exit code"];
        var stdout = data["stdout"] || "";
        var stderr = data["stderr"] || "";
        if (exitCode !== 0) {
            errorMessage = stderr.trim() || "codex-usage exited with code " + exitCode;
            return;
        }
        try {
            var parsed = JSON.parse(stdout.trim());
            if (!parsed.primary && !parsed.secondary)
                throw new Error("No usage windows were returned");
            usage = parsed;
            capturedAt = parsed.captured_at || "";
        } catch (exception) {
            errorMessage = "Could not read Codex usage data";
        }
    }

    function windowText(window) {
        if (!window)
            return "Unavailable";
        return remainingPercent(window) + "% left";
    }

    function remainingPercent(window) {
        if (!window || typeof window.used_percent !== "number")
            return 0;
        return Math.round(Math.max(0, Math.min(100, 100 - window.used_percent)));
    }

    function remainingColor(window) {
        var value = remainingPercent(window);
        if (value <= 10)
            return "#ef6a67";
        if (value <= 25)
            return "#e7b84b";
        return "#71c77a";
    }

    function resetText(window) {
        if (!window || !window.resets_at)
            return "Reset time unavailable";
        var resetValue = window.resets_at;
        var reset = typeof resetValue === "number"
            ? new Date(resetValue * 1000)
            : new Date(resetValue);
        if (isNaN(reset.getTime()))
            return "Reset time unavailable";
        var remaining = Math.max(0, reset.getTime() - Date.now());
        var minutes = Math.floor(remaining / 60000);
        var hours = Math.floor(minutes / 60);
        minutes %= 60;
        var until = hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
        return "resets " + Qt.formatTime(reset, "HH:mm") + " · in " + until;
    }

    function ageText() {
        ageTick;
        if (!capturedAt)
            return "Not updated yet";
        var captured = new Date(capturedAt);
        if (isNaN(captured.getTime()))
            return "Update time unavailable";
        var seconds = Math.max(0, Math.floor((Date.now() - captured.getTime()) / 1000));
        if (seconds < 60)
            return "Updated just now";
        if (seconds < 3600)
            return "Updated " + Math.floor(seconds / 60) + "m ago";
        return "Updated " + Math.floor(seconds / 3600) + "h ago";
    }

    function trackedWindow() {
        var windows = [];
        if (usage && usage.primary)
            windows.push(usage.primary);
        if (usage && usage.secondary)
            windows.push(usage.secondary);
        windows.sort(function(left, right) {
            return (left.window_minutes || Number.MAX_VALUE) - (right.window_minutes || Number.MAX_VALUE);
        });
        return windows.length > 0 ? windows[0] : null;
    }

    function windowTitle(window) {
        if (!window || !window.window_minutes)
            return "Usage window";
        if (window.window_minutes === 300)
            return "5-hour window";
        if (window.window_minutes === 10080)
            return "7-day window";
        return window.window_minutes + " minute window";
    }

    Plasma5Support.DataSource {
        id: commandSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            disconnectSource(source);
            root.setResult(data);
        }
    }

    Timer {
        interval: root.refreshInterval * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.usage !== null
        onTriggered: root.ageTick++
    }

    compactRepresentation: Item {
        implicitWidth: compactLabel.implicitWidth + Kirigami.Units.gridUnit
        implicitHeight: compactLabel.implicitHeight

        PlasmaComponents3.Label {
            id: compactLabel
            anchors.centerIn: parent
            text: root.loading ? "…" : root.usage ? root.windowText(root.trackedWindow()) : "—"
            font.bold: true
            font.pointSize: 10
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: "Codex Usage"
            subText: root.usage ? root.ageText() : (root.errorMessage || "Waiting for Codex data")
        }
    }

    fullRepresentation: Item {
        implicitWidth: 340
        implicitHeight: contentColumn.implicitHeight + Kirigami.Units.gridUnit * 2

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: "Codex Usage"
                    font.bold: true
                    font.pointSize: 14
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Label {
                    text: root.usage ? (root.usage.plan_type || "unknown plan") : ""
                    opacity: 0.7
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                radius: Kirigami.Units.cornerRadius
                color: root.trackedWindow() ? Qt.alpha(root.remainingColor(root.trackedWindow()), 0.16) : Qt.rgba(1, 1, 1, 0.06)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    PlasmaComponents3.Label {
                        text: "Remaining"
                        opacity: 0.75
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        text: root.trackedWindow() ? root.remainingPercent(root.trackedWindow()) + "%" : "—"
                        color: root.trackedWindow() ? root.remainingColor(root.trackedWindow()) : Kirigami.Theme.textColor
                        font.bold: true
                        font.pointSize: 24
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, 0.15)
            }

            PlasmaComponents3.Label {
                visible: root.errorMessage !== ""
                Layout.fillWidth: true
                text: root.errorMessage
                wrapMode: Text.WordWrap
                color: "#ff776d"
            }

            WindowRow {
                visible: root.usage && root.usage.primary
                title: root.windowTitle(root.usage ? root.usage.primary : null)
                window: root.usage ? root.usage.primary : null
            }

            WindowRow {
                visible: root.usage && root.usage.secondary
                title: root.windowTitle(root.usage ? root.usage.secondary : null)
                window: root.usage ? root.usage.secondary : null
            }

            PlasmaComponents3.Label {
                visible: root.usage !== null && root.showDetails
                Layout.fillWidth: true
                text: root.usage ? ((root.usage.tokens ? root.usage.tokens.total_tokens.toLocaleString() : "0") + " session tokens · " + (root.usage.live_processes || 0) + " live Codex") : ""
                opacity: 0.7
            }

            Item { Layout.fillHeight: true }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.ageText() + " · updates every " + root.refreshInterval + "s"
                opacity: 0.65
            }
        }
    }

    Component.onCompleted: root.refresh()

    component WindowRow: ColumnLayout {
        id: row
        required property string title
        required property var window
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                text: row.title
                opacity: 0.75
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                text: root.windowText(row.window)
                font.bold: true
                color: root.remainingColor(row.window)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                width: parent.width * (row.window ? root.remainingPercent(row.window) / 100 : 0)
                height: parent.height
                radius: parent.radius
                color: root.remainingColor(row.window)
            }
        }

        PlasmaComponents3.Label {
            text: root.resetText(row.window)
            opacity: 0.65
            font.pointSize: 9
        }
    }
}
