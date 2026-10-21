import Foundation

struct HelpTopic: Identifiable, Sendable {
    let id: String
    let title: String
    let path: [String]
    let symbol: String
    let summary: String
    let guidance: String
    let keywords: String
    let destination: Destination
    enum Destination: Equatable, Sendable {
        case sound, equalizers, library, presets, programs, devices, audiograms, fitting, savedFitting, backups, diagnostics, about
        case settings(String, Int?)
    }
    var localizedPath: [String] { path.map { L($0) } + [L(title)] }
}

enum HelpCatalog {
    static let topics: [HelpTopic] = [
        .init(id: "getting-started", title: "Getting started", path: ["Help"], symbol: "sparkles",
            summary: "Connect your hearing aids and make your first adjustment.",
            guidance: "In Sound, choose Find hearing aids, scan and select your devices. Device details are below each hearing aid. A Bluetooth control connection reads supported values and adjusts consumer controls. Audio streaming is managed separately by macOS.",
            keywords: "setup start pairing connect configurar começar conectar emparejar inicio", destination: .devices),
        .init(id: "volume", title: "Volume and mute", path: ["Sound"], symbol: "speaker.wave.2",
            summary: "Adjust listening level without changing your clinical fitting.",
            guidance: "Use Together to control both ears, or Separate for independent adjustments. Together preserves the difference between left and right volume levels. Mute keeps your level ready for unmuting. Wait for a change to finish before sending another.",
            keywords: "volume level mute unmute sound som silenciar nível volumen sonido", destination: .sound),
        .init(id: "grouping", title: "Together and Separate", path: ["Sound"], symbol: "link",
            summary: "Choose whether future sound changes affect both ears.",
            guidance: "The top selector sets Together or Separate for every sound section, including EQ. A section selector can override that choice; the master then shows Mixed modes. Switching modes never copies settings or sends a hearing-aid command.",
            keywords: "sync synchronize group ungroup linked ears agrupar desagrupar juntos separados sincronizar vincular", destination: .sound),
        .init(id: "speech-booster", title: "SpeechBooster", path: ["Sound"], symbol: "mic",
            summary: "Use speech support in a program that reports support for it.",
            guidance: "SpeechBooster is available only when the current program reports a supported consumer control. If unavailable, connect the aids and wait for the device-feature reading. Together applies the requested state to both compatible ears.",
            keywords: "speech clarity voice conversa fala voz refuerzo", destination: .sound),
        .init(id: "programs", title: "Listening program", path: ["Sound"], symbol: "waveform",
            summary: "Choose a program already fitted to your hearing aids.",
            guidance: "Program names come from the devices, so Geral or General stays exactly as reported. A grouped change requires matching program identifiers and names. Audifern does not create or write a new clinical program.",
            keywords: "program profile Geral General perfil programa", destination: .programs),
        .init(id: "microphone-eq", title: "Microphone EQ", path: ["Sound", "Equalizers"], symbol: "slider.horizontal.3",
            summary: "Fine-tune lows, mids and highs for sound around you.",
            guidance: "In Sound, choose the Microphone EQ tab. Tone controls show three vertical faders; 8 bands uses the device-reported layout. Separate shows both ears side by side, while Together shows one set. Changes remain drafts until Apply. A ≠ marker means the ears currently differ.",
            keywords: "equalizer equaliser bass mid treble lows highs graves médios agudos equalizador ecualizador", destination: .equalizers),
        .init(id: "stream-eq", title: "Streaming EQ", path: ["Sound", "Equalizers"], symbol: "music.note",
            summary: "Adjust the supported equalizer for streamed sound.",
            guidance: "In Sound, choose the Streaming EQ tab to adjust lows, mids and highs or eight device channels. Separate shows both ears without switching tabs. Apply confirms the requested changes. Streaming-source volume is a different control under More sound controls.",
            keywords: "stream streaming music música audio equalizer", destination: .equalizers),
        .init(id: "tinnitus", title: "Tinnitus relief", path: ["Sound", "Equalizers"], symbol: "waveform.path",
            summary: "Inspect the additional tinnitus consumer control when supported.",
            guidance: "The additional-control section is separate from everyday equalizers. It appears only for supported, reported controls and does not add a clinical tinnitus program. Use a clinician-fitted tinnitus plan for treatment decisions.",
            keywords: "tinnitus zumbido acufeno extra advanced", destination: .equalizers),
        .init(id: "presets", title: "Presets", path: ["Library"], symbol: "star",
            summary: "Save a local consumer sound preset and reuse it.",
            guidance: "Save sound captures supported consumer adjustments on this Mac. Review a preset before applying it to compatible connected aids. A local preset is not a new program stored in the hearing aids and does not replace a clinical fitting.",
            keywords: "save restore presets favorites favoritos predefinições ajustes", destination: .presets),
        .init(id: "device-information", title: "Device information", path: ["Sound"], symbol: "ear.badge.waveform",
            summary: "Inspect model, software, firmware and supported features for each ear.",
            guidance: "Each aid has its own information. Unknown values remain unknown until read. Private identifiers are hidden by default; enable their display in Privacy only when needed. Diagnostic exports remain redacted.",
            keywords: "model firmware software version serial number modelo versão número série informacion", destination: .sound),
        .init(id: "battery-time", title: "Battery time remaining", path: ["Sound"], symbol: "battery.75percent",
            summary: "Understand the local countdown and the age of its device reading.",
            guidance: "Audifern reads available runtime telemetry after connecting when a compatible local credential is provisioned. It caches the timestamped reading, counts down locally and refreshes about hourly while connected. Runtime comes from reported charge and current draw, never a percentage conversion. Charging stops the countdown. Cached estimates expire after two hours; hover over the estimate to see its reading time.",
            keywords: "battery remaining runtime time left charge charging bateria tempo restante carga batería duración", destination: .sound),
        .init(id: "battery-alerts", title: "Battery alerts", path: ["Settings"], symbol: "bell.badge",
            summary: "Choose local low-battery notifications for each hearing aid.",
            guidance: "Open Battery alerts to enable thresholds such as 50%, 30%, 20% and below 10%. macOS notification permission is required. Alerts use device-reported charge; a countdown reaching zero is not a new battery reading.",
            keywords: "battery alert notification low 50 30 20 10 bateria bateria baixa notificações alerta batería baja", destination: .settings("battery", nil)),
        .init(id: "reconnection", title: "Automatically reconnect app controls", path: ["Settings", "Connections"], symbol: "antenna.radiowaves.left.and.right",
            summary: "Reconnect only your chosen hearing aids while this Mac is unlocked.",
            guidance: "Automatic connection starts off. Connect your aids in Sound, then remember them in Connections. Nearby retry and wake/unlock attempts are optional. Pause persists until you resume or connect manually. This controls Audifern’s BLE link, not the operating system’s audio profile.",
            keywords: "auto connect reconnect bluetooth wake unlock nearby automático reconectar desbloquear despertar", destination: .settings("connections", 0)),
        .init(id: "nearby-signal", title: "Nearby signal", path: ["Settings", "Connections"], symbol: "dot.radiowaves.left.and.right",
            summary: "Tune the signal threshold used before automatic reconnection.",
            guidance: "Measure the signal at your desk, then adjust the minimum dBm value. A less-negative threshold requires a stronger signal. Walls, your body and interference affect it; it cannot reliably identify an exact distance, room or floor. Fresh readings are required before connecting.",
            keywords: "distance proximity signal rssi range alcance distância proximidade sinal señal", destination: .settings("connections", 1)),
        .init(id: "mac-audio", title: "Mac audio output", path: ["Settings", "Connections"], symbol: "speaker.wave.2",
            summary: "Choose an output already available to macOS.",
            guidance: "Choose the preferred hearing-aid output and a fallback output. Mac audio selects between those available outputs. Pausing app controls does not necessarily release a Bluetooth audio profile owned by macOS. Moving an audio stream between Android and Mac may require the other host to release its connection; no successful phone handoff is assumed.",
            keywords: "audio sound output speaker android phone handoff switch disconnect som saída alto falante teléfono salida", destination: .settings("connections", 2)),
        .init(id: "menu-bar", title: "Menu bar", path: ["Settings", "Quick access"], symbol: "menubar.rectangle",
            summary: "Keep batteries and sound controls one click away.",
            guidance: "Show or hide the menu-bar item in Quick access. Choose the compact or expanded panel, battery text and the sections you use. The menu-bar app stays available when the main window closes. Hiding the icon does not quit Audifern.",
            keywords: "menu bar taskbar tray status icon codexbar barra menus ícone bandeja", destination: .settings("quickAccess", nil)),
        .init(id: "widgets", title: "Widgets and Control Center", path: ["Settings", "Quick access"], symbol: "rectangle.3.group",
            summary: "Add battery widgets and separate quick controls using macOS.",
            guidance: "Add Audifern from the desktop widget gallery. On macOS 26 or later, add its controls through Edit Controls in Control Center and place supported controls in the menu bar. Widget buttons need Audifern running with current device values. macOS manages sizes and placement. Sliders are available in Audifern’s panel; system controls use supported buttons and toggles.",
            keywords: "widget control center centre quick shortcut central controle controles atalho centro", destination: .settings("quickAccess", nil)),
        .init(id: "appearance", title: "Appearance", path: ["Settings", "General"], symbol: "circle.lefthalf.filled",
            summary: "Follow the system appearance or choose Light or Dark.",
            guidance: "Appearance changes only Audifern’s interface. System follows macOS automatically. Hearing-aid sound settings remain unchanged.",
            keywords: "theme dark light system tema escuro claro apariencia oscuro", destination: .settings("general", nil)),
        .init(id: "language", title: "Language", path: ["Settings", "General"], symbol: "globe",
            summary: "Use English, Português (Brasil), Español or the system language.",
            guidance: "Change the interface language in General. Help search accepts common feature names in all three supported languages. Device program names remain exactly as reported.",
            keywords: "language translate english português español idioma tradução traducción", destination: .settings("general", nil)),
        .init(id: "privacy", title: "Privacy", path: ["Settings"], symbol: "lock.shield",
            summary: "Review identifier visibility and local data handling.",
            guidance: "Audifern has no account or telemetry service. Audiograms, local presets and caches stay on this Mac. Widgets receive only the state needed for their controls, without serial numbers or raw Bluetooth identifiers. Exports and external links require an explicit action.",
            keywords: "privacy identifiers data serial private account privacidade dados privacidad", destination: .settings("privacy", nil)),
        .init(id: "audiogram", title: "Audiogram", path: ["Hearing profile"], symbol: "chart.xyaxis.line",
            summary: "Keep your hearing-test results in a local record.",
            guidance: "Enter results from your hearing test and save them locally. The audiogram helps document and prepare a fitting discussion. Saving it does not calculate or program a clinical hearing-aid prescription.",
            keywords: "audiogram hearing test exam audiometry audiometria exame audiograma", destination: .audiograms),
        .init(id: "fitting-plan", title: "Prepare a fitting plan", path: ["Hearing profile"], symbol: "list.bullet.clipboard",
            summary: "Organize your audiogram, listening goals and fitting preferences.",
            guidance: "The guided plan records hearing aids, acoustics and listening preferences for review. These are local planning records. Clinical programming, firmware installation and a full Genie fitting replacement are not available.",
            keywords: "genie plan fitting receiver acoustics adaptation plano adaptação receptor adaptación", destination: .fitting),
        .init(id: "saved-fitting", title: "Saved fitting", path: ["Hearing profile"], symbol: "doc.text.magnifyingglass",
            summary: "Review supported readable state without changing the hearing aids.",
            guidance: "Saved fitting summaries expose supported records captured in a private backup. Unknown fields stay unknown. A readable checkpoint is not a complete firmware image, clinical calibration backup or verified restore mechanism.",
            keywords: "fitting saved configuration read only configuração salva adaptación guardada", destination: .savedFitting),
        .init(id: "backups", title: "Backups", path: ["Hearing profile"], symbol: "externaldrive",
            summary: "Save and compare private checkpoints of supported readable state.",
            guidance: "Backups never overwrite an older checkpoint. They can contain private device and fitting information, so store exports carefully. Clinical restore and firmware restore are not implemented.",
            keywords: "backup compare snapshot export restore cópia segurança comparar copia respaldo", destination: .backups),
        .init(id: "diagnostics", title: "Diagnostics", path: ["Settings"], symbol: "waveform.path.ecg",
            summary: "Inspect connection state and redacted logs when troubleshooting.",
            guidance: "Diagnostics separates discovery, connection and supported feature reads. Connected app controls do not prove audio is routed to the aids. Review redacted logs locally before exporting; Audifern does not send them automatically.",
            keywords: "debug log troubleshooting error bluetooth diagnóstico registros erro diagnóstico", destination: .diagnostics),
        .init(id: "about", title: "About Audifern", path: ["Help"], symbol: "info.circle",
            summary: "Find the version, open-source license and support options.",
            guidance: "About contains the maintainer link, source code, GNU GPLv3 license and optional contributions. Donation QR codes are generated locally. Payment providers control the personal information shown on their own payment pages.",
            keywords: "about version donate support license github sabino sobre versão doar doação ayuda donar", destination: .about)
    ]
    static func topic(_ id: String) -> HelpTopic? { topics.first { $0.id == id } }
    static func search(_ query: String, limit: Int = 100, localize: (String) -> String = { L($0) }) -> [HelpTopic] {
        guard limit > 0 else { return [] }
        let query = normalized(query), words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Array(topics.prefix(limit)) }
        return topics.compactMap { topic -> (HelpTopic, Int)? in
            let title = normalized(localize(topic.title)), path = normalized((topic.path + [topic.title]).map(localize).joined(separator: " "))
            let keywords = normalized(topic.keywords), summary = normalized(localize(topic.summary))
            let all = [title, path, keywords, summary].joined(separator: " ")
            guard words.allSatisfy({ all.contains($0) }) else { return nil }
            return (topic, (title == query ? 100 : 0) + (title.hasPrefix(query) ? 40 : 0) + (title.contains(query) ? 20 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
