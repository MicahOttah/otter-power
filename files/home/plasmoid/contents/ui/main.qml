import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Gap between columns and rows. Change this one line to tighten or loosen the layout.
    readonly property int gap: Kirigami.Units.smallSpacing * 2

    readonly property string profilePath: "/sys/firmware/acpi/platform_profile"
    readonly property string eppGlob: "/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference"
    readonly property string plPath: "/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw"
    readonly property string twPath: "/sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us"
    readonly property var presets: [
        { name: "Desk",       profile: "cool",        epp: "balance_power",       w: 55, s: 28 },
        { name: "Gaming",     profile: "balanced",    epp: "balance_performance", w: 80, s: 28 },
        { name: "Gaming max", profile: "performance", epp: "balance_performance", w: 80, s: 28 },
        { name: "AI run",     profile: "balanced",    epp: "balance_power",       w: 65, s: 56 }
    ]
    property int tick: 0
    readonly property string readCmd: "sh $HOME/.local/bin/powerctl-read.sh" + ((expanded || tick % 6 === 0) ? " gpu" : "")
    property string currentProfile: "unknown"
    property string currentEpp: ""
    property int plWatts: 0
    property int plWindow: 0
    property string cpuTemp: "n/a"
    property string gpuTemp: "n/a"
    property string dimmTemp: "n/a"
    property string nvmeTemp: "n/a"
    property string fanText: "n/a"
    property string throttleText: "n/a"
    property string pkgText: "n/a"
    property string battText: "n/a"
    property string freqText: "n/a"
    property string gpuPower: "n/a"
    property string gpuUtil: "n/a"
    property string gpuVram: "n/a"
    property real prevEnergy: -1
    property real prevTime: 0

    function cap(s) {
        s = s.replace(/_/g, " ")
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s
    }

    function iconFor(p) {
        switch (p) {
        case "cool":        return "weather-snow-symbolic"
        case "quiet":       return "audio-volume-muted-symbolic"
        case "balanced":    return "power-profile-balanced-symbolic"
        case "performance": return "power-profile-performance-symbolic"
        default:            return "preferences-system-power-management"
        }
    }

    function gpuCeiling(p) {
        switch (p) {
        case "cool":
        case "quiet":       return "55 W"
        case "balanced":    return "110 W"
        case "performance": return "122 W"
        default:            return "n/a"
        }
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            var lines = data["stdout"].split("\n")
            if (lines.length > 0 && lines[0].trim().length > 0)
                root.currentProfile = lines[0].trim()
            var t = lines.length > 1 ? parseInt(lines[1]) : NaN
            root.cpuTemp = isNaN(t) ? "n/a" : Math.round(t / 1000) + " °C"
            var fans = lines.length > 2 ? lines[2].trim() : ""
            root.fanText = fans.length > 0 ? fans.split(/\s+/).map((v, i) => "F" + (i + 1) + ": " + v).join("  ") + " RPM" : "n/a"
            var gl = lines.length > 3 ? lines[3].trim() : ""
            var g = parseInt(gl)
            if (gl === "asleep")
                root.gpuTemp = "asleep"
            else if (!isNaN(g))
                root.gpuTemp = g + " °C"
            else if (root.expanded)
                root.gpuTemp = "n/a"
            if (lines.length > 4 && lines[4].trim().length > 0)
                root.currentEpp = lines[4].trim()
            var dm = lines.length > 5 ? parseInt(lines[5]) : NaN
            root.dimmTemp = isNaN(dm) ? "n/a" : Math.round(dm / 1000) + " °C"

            var th = lines.length > 6 ? lines[6].trim() : ""
            root.throttleText = th.length > 0 ? th : "n/a"

            var e = lines.length > 7 ? parseInt(lines[7]) : NaN
            var now = Date.now()
            if (isNaN(e)) {
                root.pkgText = "n/a"
                root.prevEnergy = -1
            } else {
                var dt = now - root.prevTime
                if (root.prevEnergy >= 0 && e >= root.prevEnergy && dt >= 500)
                    root.pkgText = (((e - root.prevEnergy) / 1e6) / (dt / 1000)).toFixed(1) + " W"
                if (root.prevEnergy < 0 || dt >= 500) {
                    root.prevEnergy = e
                    root.prevTime = now
                }
            }

            var bp = lines.length > 8 ? lines[8].trim().split("|") : []
            if (bp.length >= 3 && bp[0].length > 0) {
                var bw = (Math.abs(parseInt(bp[1])) * parseInt(bp[2])) / 1e12
                root.battText = isNaN(bw) ? bp[0] : bp[0] + ", " + bw.toFixed(1) + " W"
            } else {
                root.battText = "n/a"
            }

            var fq = lines.length > 9 ? parseInt(lines[9]) : NaN
            root.freqText = isNaN(fq) ? "n/a" : Math.round(fq / 1000) + " MHz"
            var nv = lines.length > 10 ? parseInt(lines[10]) : NaN
            root.nvmeTemp = isNaN(nv) ? "n/a" : Math.round(nv / 1000) + " °C"

            var gd = lines.length > 11 ? lines[11].trim() : ""
            if (gd === "asleep") {
                root.gpuPower = "asleep"
                root.gpuUtil = "asleep"
                root.gpuVram = "asleep"
            } else if (gd.length > 0) {
                var gp = gd.split(",").map(s => s.trim())
                if (gp.length >= 4) {
                    root.gpuPower = gp[0] + " W"
                    root.gpuUtil = gp[1] + " %"
                    root.gpuVram = gp[2] + " / " + gp[3] + " MiB"
                }
            } else if (root.expanded) {
                root.gpuPower = "n/a"
                root.gpuUtil = "n/a"
                root.gpuVram = "n/a"
            }

            var pl = lines.length > 12 ? parseInt(lines[12]) : NaN
            root.plWatts = isNaN(pl) ? 0 : Math.round(pl / 1e6)
            var tw = lines.length > 13 ? parseInt(lines[13]) : NaN
            root.plWindow = isNaN(tw) ? 0 : Math.round(tw / 1e6)
        }
        function run(cmd) { connectSource(cmd) }
    }

    function refresh() {
        exec.run(readCmd)
    }

    function setProfile(name) {
        exec.run("echo " + name + " > " + profilePath + "; mkdir -p $HOME/.config/powerctl; echo " + name + " > $HOME/.config/powerctl/profile; " + readCmd)
    }

    function setEpp(name) {
        exec.run("for f in " + eppGlob + "; do echo " + name + " > $f; done; mkdir -p $HOME/.config/powerctl; echo " + name + " > $HOME/.config/powerctl/epp; " + readCmd)
    }

    function setPl(w) {
        exec.run("echo " + (w * 1000000) + " > " + plPath + "; mkdir -p $HOME/.config/powerctl; echo " + w + " > $HOME/.config/powerctl/pl1; " + readCmd)
    }

    function setWindow(s) {
        exec.run("echo " + (s * 1000000) + " > " + twPath + "; mkdir -p $HOME/.config/powerctl; echo " + s + " > $HOME/.config/powerctl/pl1_window; " + readCmd)
    }

    function applyPreset(p, e, w, s) {
        var cmd = "echo " + p + " > " + profilePath + "; "
        cmd += "for f in " + eppGlob + "; do echo " + e + " > $f; done; "
        cmd += "echo " + (w * 1000000) + " > " + plPath + "; "
        cmd += "echo " + (s * 1000000) + " > " + twPath + "; "
        cmd += "mkdir -p $HOME/.config/powerctl; "
        cmd += "echo " + p + " > $HOME/.config/powerctl/profile; "
        cmd += "echo " + e + " > $HOME/.config/powerctl/epp; "
        cmd += "echo " + w + " > $HOME/.config/powerctl/pl1; "
        cmd += "echo " + s + " > $HOME/.config/powerctl/pl1_window; "
        cmd += readCmd
        exec.run(cmd)
    }

    Timer {
        interval: root.expanded ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.tick++; root.refresh() }
    }

    onExpandedChanged: if (expanded) refresh()

    toolTipMainText: "Power profile: " + cap(currentProfile)
    toolTipSubText: "CPU " + cpuTemp + "  |  GPU " + gpuTemp + "  |  DIMM " + dimmTemp + "  |  Fan " + fanText

    compactRepresentation: Kirigami.Icon {
        source: root.iconFor(root.currentProfile)
        fallback: "preferences-system-power-management"
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: root.gap
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight

        // Row 1: monitoring
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: root.gap

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                PlasmaComponents.Label {
                    text: "Power and load"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                PlasmaComponents.Label { text: "Package power: " + root.pkgText }
                PlasmaComponents.Label { text: "CPU max clock: " + root.freqText }
                PlasmaComponents.Label { text: "Throttle events: " + root.throttleText }
                PlasmaComponents.Label { text: "Battery: " + root.battText }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                PlasmaComponents.Label {
                    text: "GPU"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                PlasmaComponents.Label { text: "Ceiling: " + root.gpuCeiling(root.currentProfile) }
                PlasmaComponents.Label { text: "Temp: " + root.gpuTemp }
                PlasmaComponents.Label { text: "Power: " + root.gpuPower }
                PlasmaComponents.Label { text: "Load: " + root.gpuUtil }
                PlasmaComponents.Label { text: "VRAM: " + root.gpuVram }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                PlasmaComponents.Label {
                    text: "Sensors"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                PlasmaComponents.Label { text: "CPU temp: " + root.cpuTemp }
                PlasmaComponents.Label { text: "DIMM temp: " + root.dimmTemp }
                PlasmaComponents.Label { text: "NVMe temp: " + root.nvmeTemp }
                PlasmaComponents.Label { text: "Fan speed: " + root.fanText }
            }

            Item { Layout.fillWidth: true }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Row 2: controls
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: root.gap

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                PlasmaComponents.Label {
                    text: "Presets"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: root.presets
                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        Layout.minimumWidth: implicitWidth
                        text: modelData.name + "  (" + modelData.w + " W, " + root.gpuCeiling(modelData.profile) + " GPU)"
                        highlighted: root.currentProfile === modelData.profile
                            && root.currentEpp === modelData.epp
                            && root.plWatts === modelData.w
                            && root.plWindow === modelData.s
                        onClicked: root.applyPreset(modelData.profile, modelData.epp, modelData.w, modelData.s)
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                RowLayout {
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        source: root.iconFor(root.currentProfile)
                        fallback: "preferences-system-power-management"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }
                    PlasmaComponents.Label {
                        text: "Current: " + root.cap(root.currentProfile)
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                Repeater {
                    model: ["cool", "quiet", "balanced", "performance"]
                    PlasmaComponents.RadioButton {
                        autoExclusive: false
                        text: root.cap(modelData)
                        checked: root.currentProfile === modelData
                        onClicked: {
                            root.setProfile(modelData)
                            checked = Qt.binding(() => root.currentProfile === modelData)
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true; visible: root.currentEpp.length > 0 }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                visible: root.currentEpp.length > 0
                PlasmaComponents.Label {
                    text: "Energy Performance Preference"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: ["performance", "balance_performance", "balance_power", "power"]
                    PlasmaComponents.RadioButton {
                        autoExclusive: false
                        text: root.cap(modelData)
                        checked: root.currentEpp === modelData
                        onClicked: {
                            root.setEpp(modelData)
                            checked = Qt.binding(() => root.currentEpp === modelData)
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true; visible: root.plWatts > 0 }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                visible: root.plWatts > 0
                PlasmaComponents.Label {
                    text: "Sustained power limit"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [55, 65, 75, 80]
                    PlasmaComponents.RadioButton {
                        autoExclusive: false
                        text: modelData + " W"
                        checked: root.plWatts === modelData
                        onClicked: {
                            root.setPl(modelData)
                            checked = Qt.binding(() => root.plWatts === modelData)
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true; visible: root.plWindow > 0 }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                visible: root.plWindow > 0
                PlasmaComponents.Label {
                    text: "Burst window"
                    font.bold: true
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: [10, 28, 56]
                    PlasmaComponents.RadioButton {
                        autoExclusive: false
                        text: modelData + " s"
                        checked: root.plWindow === modelData
                        onClicked: {
                            root.setWindow(modelData)
                            checked = Qt.binding(() => root.plWindow === modelData)
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
