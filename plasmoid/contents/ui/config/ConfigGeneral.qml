import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    property alias cfg_refreshInterval: refreshInterval.value
    property alias cfg_showDetails: showDetails.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: refreshInterval
            Kirigami.FormData.label: i18n("Refresh interval:")
            from: 10
            to: 300
            stepSize: 5
            editable: true
        }

        QQC2.CheckBox {
            id: showDetails
            Kirigami.FormData.label: i18n("Popup:")
            text: i18n("Show token and process details")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("The widget shows remaining usage. Codex writes the source data locally; no credentials or network requests are used.")
            wrapMode: Text.WordWrap
            opacity: 0.7
        }
    }
}
