import Testing
@testable import Audifern

@Test func renderedMessagesTranslateExactKeysAndProgramNumbers() {
    let portuguese = Localization(language: .portugueseBrazil), spanish = Localization(language: .spanish)
    #expect(LocalizedMessage.render("Connected", using: portuguese) == portuguese.string("Connected"))
    #expect(LocalizedMessage.render("Program 7", using: portuguese) == "Programa 7")
    #expect(LocalizedMessage.render("Program 7", using: spanish) == "Programa 7")
    #expect(LocalizedMessage.render("Program 7, custom", using: spanish) == "Program 7, custom")
}

@Test func renderedMessagesTranslateKnownCountMessagesWithoutReplacingTheirValues() {
    let portuguese = Localization(language: .portugueseBrazil), spanish = Localization(language: .spanish)
    let message = "All 3 sound changes confirmed by the hearing aids."
    #expect(LocalizedMessage.render(message, using: portuguese) == "Confirmadas 3 alterações de som pelos aparelhos auditivos.")
    #expect(LocalizedMessage.render(message, using: spanish) == "Los audífonos confirmaron 3 cambios de sonido.")
    #expect(LocalizedMessage.render("All 1 sound change confirmed by the hearing aids.", using: spanish) == "Los audífonos confirmaron 1 cambio de sonido.")
}

@Test func renderedMessagesTranslateKnownErrorWrappersAndNestedExactErrors() {
    let portuguese = Localization(language: .portugueseBrazil), spanish = Localization(language: .spanish)
    let message = "Linked change not confirmed: Volume limits changed."
    #expect(LocalizedMessage.render(message, using: portuguese) == "Alteração vinculada não confirmada: Os limites de volume mudaram.")
    #expect(LocalizedMessage.render(message, using: spanish) == "Cambio vinculado sin confirmar: Cambiaron los límites de volumen.")
    #expect(LocalizedMessage.render("Device details: Vendor failure 0xEF/71", using: portuguese) == "Detalhes do dispositivo: Vendor failure 0xEF/71")
}

@Test func renderedMessagesKeepCapturedNamesAndPercentSequencesVerbatim() {
    let spanish = Localization(language: .spanish)
    let name = "Connected · João's aid %@ 100%"
    #expect(LocalizedMessage.render("Connecting to " + name, using: spanish) == "Conectando con " + name)
    let examName = "Connected"
    let message = "Saved \(examName) on this Mac. Audiogram values are stored for reference; they do not prescribe amplification."
    #expect(LocalizedMessage.render(message, using: spanish).contains(examName))
    #expect(!LocalizedMessage.render(message, using: spanish).contains(spanish.string(examName)))
}

@Test func renderedMessageMatchingIsAnchoredBoundedAndDoesNotGuessUnknownText() {
    let text = Localization(language: .portugueseBrazil)
    for value in ["Debug GATT 0xCC56 abc", "My custom program", "Prefix Connecting to aid", "Program 7\n", "Tinnitus custom change confirmed by hearing aid."] {
        #expect(LocalizedMessage.render(value, using: text) == value)
    }
    let oversized = "Connecting to " + String(repeating: "X", count: 4_097)
    #expect(LocalizedMessage.render(oversized, using: text) == oversized)
    #expect(M("Uncatalogued protocol diagnostic 0xAFE1") == "Uncatalogued protocol diagnostic 0xAFE1")
}

@Test func renderedMessagePatternsDoNotCacheTheSelectedLanguage() {
    let text = Localization(language: .english)
    let canonical = "Device details: Volume limits changed."
    #expect(LocalizedMessage.render(canonical, using: text) == canonical)
    text.language = .portugueseBrazil
    #expect(LocalizedMessage.render(canonical, using: text) == "Detalhes do dispositivo: Os limites de volume mudaram.")
    text.language = .spanish
    #expect(LocalizedMessage.render(canonical, using: text) == "Detalles del dispositivo: Cambiaron los límites de volumen.")
}

@Test func renderedMessageControlLabelsUseKnownVocabularyAndPreserveSignedLevels() {
    let spanish = Localization(language: .spanish)
    #expect(LocalizedMessage.render("Volume -2 confirmed by hearing aid", using: spanish) == "Volumen -2 confirmado por el audífono")
    #expect(LocalizedMessage.render("SpeechBooster on confirmed by hearing aid.", using: spanish) == spanish.string("SpeechBooster %@ confirmed by hearing aid.", arguments: [spanish.string("On").lowercased()]))
    #expect(LocalizedMessage.render("Custom Label confirmed by hearing aid", using: spanish) == "Custom Label confirmed by hearing aid")
}
