import CompanionCore
import SwiftUI

/// A local planning editor. Persistence is supplied by the app-lifetime owner;
/// the view only reads the dashboard's existing device state.
struct FittingWorkspaceView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var audiograms: AudiogramEditorStore
    @Binding var draft: FittingWorkspaceDraft
    let saveDraft: () -> Void
    let loadDraft: () -> Void
    var persistenceStatus: String? = nil
    var canLoadDraft = true
    var history: FittingWorkspaceStore? = nil
    var guided = false
    var referenceOnly = false
    var saveAndClose: (() -> Bool)? = nil
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences
    @State private var showingAcoustics = false
    @State private var showingChecklist = false
    @State private var showingCatalog = false
    @State private var confirmingReload = false
    @State private var editorMessage: String?
    @State private var saveAttemptFailed = false

    private var readiness: FittingWorkspaceReadiness { draft.readiness(audiograms: audiograms.library.exams) }
    private var attachedExam: Audiogram? {
        draft.audiogramID.flatMap { id in audiograms.library.exams.first { $0.id == id } }
    }
    private var validationMessage: String? {
        do { _ = try draft.validated(); return nil }
        catch { return error.localizedDescription }
    }
    private var connectedAids: [AidConnection] { store.orderedConnections.filter(\.isConnected) }

    var body: some View {
        VStack(spacing: 0) {
        if guided { guidedHeader }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if referenceOnly { featureCatalog }
                else if guided { guidedContent }
                else {
                PageHeading(title: L("Fitting workspace"), subtitle: L("A thoughtful plan for your next fitting, kept on this Mac.")) {
                    ConnectionBadge(store: store)
                }
                backupFirst
                planOverview
                if let history { FittingPlanHistoryView(workspace: history) }
                HStack(alignment: .top, spacing: 20) {
                    patientCard.frame(minWidth: 0, maxWidth: .infinity)
                    VStack(spacing: 20) {
                        audiogramCard
                        preferencesCard
                    }.frame(minWidth: 0, maxWidth: .infinity)
                }
                programIdeas
                currentPrograms
                featureCatalog
                }
            }.padding(30).frame(maxWidth: 1160, alignment: .leading)
        }
        if guided { guidedFooter }
        }
        .accessibilityIdentifier("fitting-workspace")
        .onChange(of: draft.model) { _, model in
            if let rationale = draft.rationale, !model.rationales.contains(rationale) { draft.rationale = nil }
        }
        .confirmationDialog(L("Reload your saved plan?"), isPresented: $confirmingReload, titleVisibility: .visible) {
            Button(L("Reload saved plan")) { loadDraft() }
            Button(L("Cancel"), role: .cancel) {}
        } message: { Text(L("This replaces the editor with the last saved copy on this Mac.")) }
    }

    private var guidedHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L("Prepare a fitting plan")).font(.system(size: 30, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                ForEach(FittingPlanStep.allCases) { step in
                    Button { navigation.fittingStep = step } label: {
                        VStack(spacing: 8) {
                            Text(String(step.rawValue + 1)).font(AppType.callout.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(step == navigation.fittingStep ? Color.white : Color.primary)
                                .background(step == navigation.fittingStep ? Brand.accent : Color.secondary.opacity(0.12), in: Circle())
                            Text(step.title).font(AppType.caption.weight(step == navigation.fittingStep ? .semibold : .regular))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityAddTraits(step == navigation.fittingStep ? [.isSelected] : [])
                        .accessibilityIdentifier("fitting-step-\(step.rawValue)")
                }
            }
        }.padding(.horizontal, 30).padding(.vertical, 20)
    }

    @ViewBuilder private var guidedContent: some View {
        switch navigation.fittingStep {
        case .aboutYou:
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Plan name")).font(AppType.headline)
                    TextField(L("Everyday clarity"), text: $draft.name).textFieldStyle(.roundedBorder)
                }
            }
            patientCard
        case .hearingAids:
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L("Which hearing aids do you use?")).font(.system(size: 24, weight: .semibold))
                    Text(L("Copy details you know from your fitting record. Unknown details can stay unrecorded."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                    Picker(L("Planning profile"), selection: $draft.model) {
                        ForEach(FittingWorkspaceModel.allCases) { Text(L($0.title)).tag($0) }
                    }
                    Picker(L("Ears"), selection: $draft.ears) {
                        ForEach(FittingWorkspaceEars.allCases) { Text(L($0.title)).tag($0) }
                    }.pickerStyle(.segmented).font(AppType.body)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(draft.ears.ears, id: \.self) { ear in acousticsEditor(ear).frame(maxWidth: .infinity) }
                    }
                }
            }
        case .audiogram: audiogramCard
        case .preferences:
            preferencesCard
            programIdeas
        case .review:
            planOverview
            currentPrograms
            if let history { FittingPlanHistoryView(workspace: history) }
            Button(L("Compatibility and fitting reference…")) { navigation.present(.fittingReference) }
        }
    }

    private var guidedFooter: some View {
        VStack(spacing: 0) {
            Divider()
            if saveAttemptFailed {
                Text(persistenceStatus.map { M($0) } ?? L("The plan could not be saved. The last saved copy has been preserved."))
                    .font(AppType.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.top, 12)
            }
            HStack(spacing: 16) {
                Label(L("Local plan only. Hearing aids are not programmed."), systemImage: "lock")
                    .font(AppType.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let previous = navigation.fittingStep.previous {
                    Button(L("Back")) { navigation.fittingStep = previous }
                }
                Button(L("Save and close")) {
                    if let saveAndClose {
                        let saved = saveAndClose(); saveAttemptFailed = !saved
                        if saved { navigation.closeSheet() }
                    } else { saveDraft() }
                }
                    .disabled(validationMessage != nil || store.isDemo)
                if let next = navigation.fittingStep.next {
                    Button(L("Continue")) { navigation.fittingStep = next }.buttonStyle(.borderedProminent).font(AppType.body)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(22)
        }
    }

    private var backupFirst: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 24, weight: .medium)).foregroundStyle(Brand.accent)
                .frame(width: 52, height: 52).background(Brand.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Begin with a backup")).font(AppType.headline)
                Text(L("Keep a fresh copy of the state Audifern can read. Full clinical fitting restore is not available yet."))
                    .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { navigation.show(.backups) } label: {
                Label(L("Open backups"), systemImage: "arrow.up.right")
            }.buttonStyle(.bordered).font(AppType.body).accessibilityIdentifier("fitting-open-backups")
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Brand.accent.opacity(0.15)))
    }

    private var planOverview: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        capsule(L("Local plan"), symbol: "doc.text", tint: Brand.accent)
                        TextField(L("Plan name"), text: $draft.name)
                            .font(.title2.weight(.semibold)).textFieldStyle(.plain)
                            .accessibilityIdentifier("fitting-plan-name")
                        Text(L("Your existing hearing-aid fitting stays in place while you prepare."))
                            .font(AppType.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 10) {
                        Button { saveDraft() } label: { Label(L("Save plan"), systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent).font(AppType.body).disabled(validationMessage != nil || store.isDemo)
                            .accessibilityIdentifier("fitting-save-plan")
                        Button(L("Reload saved…")) { confirmingReload = true }
                            .buttonStyle(.borderless).font(AppType.caption).disabled(!canLoadDraft || store.isDemo)
                            .accessibilityIdentifier("fitting-load-plan")
                    }
                }
                Divider()
                ExpandableSection(isExpanded: $showingChecklist) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(readiness.steps) { step in
                            Label(L(step.id.title), systemImage: step.completed ? "checkmark.circle.fill" : "circle.dashed")
                                .font(AppType.callout).foregroundStyle(step.completed ? Brand.accent : Color.secondary)
                                .accessibilityLabel(L("%@ · %@", L(step.id.title), step.completed ? L("Recorded") : L("Needs details")))
                        }
                    }.padding(.top, 14)
                    Text(L("This checklist tracks preparation. It does not approve a prescription or unlock hearing-aid programming."))
                        .font(AppType.caption).foregroundStyle(.secondary).padding(.top, 10)
                } label: {
                    HStack(spacing: 14) {
                        Text(L("%d of %d preparation steps recorded", readiness.completedCount, readiness.steps.count)).font(AppType.callout.weight(.medium))
                        ProgressView(value: Double(readiness.completedCount), total: Double(readiness.steps.count))
                            .progressViewStyle(.linear).frame(width: 110).tint(Brand.accent).accessibilityHidden(true)
                    }
                }
                if let validationMessage { message(L(validationMessage), symbol: "exclamationmark.circle", tint: .orange) }
                if let persistenceStatus, !persistenceStatus.isEmpty { message(M(persistenceStatus), symbol: "doc.badge.clock", tint: .secondary) }
                if let editorMessage { message(editorMessage, symbol: "info.circle", tint: .secondary) }
            }
        }
    }

    private var patientCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(guided ? L("About you") : L("Patient & hearing aids"), number: "1", symbol: "person.crop.rectangle")
                VStack(alignment: .leading, spacing: 14) {
                    field(L("Name or initials"), placeholder: L("Who is this plan for?"), text: $draft.patientLabel, id: "fitting-patient-name")
                    field(L("Birth date · optional"), placeholder: L("YYYY-MM-DD"), text: $draft.birthDate, id: "fitting-birth-date")
                    Picker(L("Hearing-aid experience"), selection: $draft.experience) {
                        ForEach(FittingWorkspaceExperience.allCases) { Text(L($0.title)).tag($0) }
                    }
                    if !guided {
                    Divider()
                    Picker(L("Planning profile"), selection: $draft.model) {
                        ForEach(FittingWorkspaceModel.allCases) { Text(L($0.title)).tag($0) }
                    }.accessibilityIdentifier("fitting-model")
                    Picker(L("Ears"), selection: $draft.ears) {
                        ForEach(FittingWorkspaceEars.allCases) { Text(L($0.title)).tag($0) }
                    }.pickerStyle(.segmented).font(AppType.body)
                    Text(L("Choose the model on your fitting record. A planning profile does not confirm connected-device compatibility."))
                        .font(AppType.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("What would you like to hear more easily?")).font(AppType.callout.weight(.medium))
                        TextField(L("Conversations, music, busy places…"), text: $draft.listeningGoals, axis: .vertical)
                            .lineLimit(3...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("fitting-listening-goals")
                    }
                }.font(AppType.callout)
                if !guided { ExpandableSection(L("Receiver & acoustics"), isExpanded: $showingAcoustics) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L("Copy these details from your current fitting record. Leave anything you do not know unrecorded."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                        ForEach(draft.ears.ears, id: \.self) { ear in acousticsEditor(ear) }
                    }.padding(.top, 14)
                }.font(AppType.callout.weight(.medium)) }
            }
        }
    }

    private func acousticsEditor(_ ear: AudiogramEar) -> some View {
        let acoustics = ear == .left ? $draft.leftAcoustics : $draft.rightAcoustics
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if guided { HearingAidArtwork(right: ear == .right, size: 0.45) }
                Label(L(ear.label), systemImage: "ear").font(AppType.headline)
                    .foregroundStyle(ear == .left ? Color.blue : Color.red)
            }
            field(L("Receiver / speaker"), placeholder: L("As listed on the fitting record"), text: acoustics.receiver,
                  id: "fitting-\(ear.rawValue)-receiver")
            Picker(L("Dome or earmold"), selection: acoustics.coupling) {
                ForEach(FittingWorkspaceCoupling.allCases) { Text(L($0.title)).tag($0) }
            }
            field(L("Vent details · optional"), placeholder: L("Size or description, if known"), text: acoustics.ventDescription,
                  id: "fitting-\(ear.rawValue)-vent")
            Toggle(L("Checked against my fitting record"), isOn: acoustics.checkedAgainstRecord)
                .font(AppType.caption).toggleStyle(.checkbox)
        }.padding(15).background(Brand.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
    }

    private var audiogramCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading(L("Bring your audiogram"), number: "2", symbol: "chart.xyaxis.line")
                Text(L("Link an existing exam, or enter the values from your audiogram in the editor."))
                    .font(AppType.callout).foregroundStyle(.secondary)
                if audiograms.library.exams.isEmpty {
                    Label(L("No saved audiograms yet"), systemImage: "doc.badge.plus")
                        .font(AppType.callout).foregroundStyle(.secondary).padding(.vertical, 5)
                } else {
                    Picker(L("Saved exam"), selection: $draft.audiogramID) {
                        Text(L("Choose an exam")).tag(Optional<UUID>.none)
                        ForEach(audiograms.library.exams) { exam in Text(exam.name).tag(Optional(exam.id)) }
                    }.accessibilityIdentifier("fitting-audiogram-picker")
                }
                if let exam = attachedExam {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exam.name).font(AppType.callout.weight(.semibold))
                        HStack {
                            if let date = exam.examDate { Text(date).monospacedDigit() }
                            Spacer()
                            Text(L("%d recorded points", exam.thresholds.count))
                        }.font(AppType.caption).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            examEarSummary(exam, ear: .left)
                            examEarSummary(exam, ear: .right)
                        }
                    }.padding(14).background(Brand.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                } else if draft.audiogramID != nil {
                    message(L("The linked exam is no longer in this Mac’s audiogram library. Choose another exam."), symbol: "doc.badge.ellipsis", tint: .orange)
                }
                Button { openAudiogram() } label: {
                    Label(attachedExam == nil ? L("Open audiogram editor") : L("Review linked exam"), systemImage: "arrow.up.right")
                }.buttonStyle(.bordered).font(AppType.body).accessibilityIdentifier("fitting-open-audiogram")
                Text(L("Thresholds remain exam records. Linking an exam does not calculate amplification."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func examEarSummary(_ exam: Audiogram, ear: AudiogramEar) -> some View {
        let points = exam.thresholds.filter { $0.key.ear == ear && $0.key.conduction == .air && !$0.noResponse }.count
        return Label(L("%@ · %d air points", L(ear.label), points), systemImage: "circle.fill")
            .font(AppType.caption).foregroundStyle(ear == .left ? Color.blue : Color.red)
    }

    private var preferencesCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading(L("Fitting preferences"), number: "3", symbol: "slider.horizontal.3")
                if draft.capabilities.rationales.isEmpty {
                    Text(L("Select the Intent 3 planning profile to see the rationale choices mapped for that model. Other models need their own validated profile."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                } else {
                    Picker(L("Rationale to discuss"), selection: $draft.rationale) {
                        Text(L("Review together")).tag(Optional<FittingWorkspaceRationale>.none)
                        ForEach(draft.capabilities.rationales) { Text(L($0.title)).tag(Optional($0)) }
                    }.accessibilityIdentifier("fitting-rationale")
                    Text(L("These are planning choices. Clinical gain calculation is not available in Audifern."))
                        .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Picker(L("Adaptation stage to discuss"), selection: $draft.adaptation) {
                    ForEach(FittingWorkspaceAdaptation.allCases) { Text(L($0.title)).tag($0) }
                }.accessibilityIdentifier("fitting-adaptation")
                Text(L("Record a preference to review at your fitting. This does not change the adaptation in your hearing aids."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(AppType.callout)
        }
    }

    private var programIdeas: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeading(L("Plan your listening situations"), number: "4", symbol: "square.grid.2x2")
                        Text(L("Describe the programs you would like to discuss, with the situations that matter to you."))
                            .font(AppType.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        draft.programs.append(.init(name: L("New program idea"), purpose: .custom))
                    } label: { Label(L("Add idea"), systemImage: "plus") }
                        .buttonStyle(.bordered).font(AppType.body).disabled(draft.programs.count >= FittingWorkspaceDraft.maximumProgramIdeas)
                        .accessibilityIdentifier("fitting-add-program")
                }
                if draft.programs.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.text.bubble.right").font(.title2).foregroundStyle(Brand.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Start with a real moment")).font(AppType.callout.weight(.medium))
                            Text(L("A conversation over dinner, a favorite album, or a busy commute."))
                                .font(AppType.callout).foregroundStyle(.secondary)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach($draft.programs) { program in programEditor(program) }
                Text(L("Program ideas are saved in this plan. They do not create, clone or replace fitted programs in your hearing aids."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func programEditor(_ program: Binding<FittingProgramPlan>) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: program.wrappedValue.purpose.symbol).foregroundStyle(Brand.accent)
                    .frame(width: 32, height: 32).background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                TextField(L("Program idea name"), text: program.name).font(AppType.callout.weight(.semibold)).textFieldStyle(.plain)
                Spacer(minLength: 8)
                Button {
                    draft.programs.removeAll { $0.id == program.wrappedValue.id }
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .accessibilityLabel(L("Remove program idea"))
            }
            Picker(L("Listening situation"), selection: program.purpose) {
                ForEach(FittingProgramPurpose.allCases) { Text(L($0.title)).tag($0) }
            }.font(AppType.callout)
            TextField(L("What is difficult, and what would better listening feel like?"), text: program.notes, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder).font(AppType.callout)
        }.padding(16).background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var currentPrograms: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L("Your current fitted programs"), systemImage: "ear.badge.waveform").font(AppType.headline)
                    Spacer()
                    Button(L("Open Programs")) { navigation.show(.programs) }.buttonStyle(.borderless)
                }
                if connectedAids.isEmpty {
                    Text(L("Connect your hearing aids to see their reported program names alongside your plan."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                    Button(L("Open Devices")) { navigation.show(.devices) }.buttonStyle(.bordered).font(AppType.body)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(connectedAids) { aid in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(L(aid.sideLabel)).font(AppType.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Spacer()
                                    Circle().fill(Brand.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                                }
                                Text(aid.activeProgramName ?? aid.activeProgram.map { L("Program %d", $0) } ?? L("Not reported"))
                                    .font(AppType.subheading.weight(.semibold))
                                if let model = aid.model { Text(model).font(AppType.caption).foregroundStyle(.secondary) }
                                if !aid.programIDs.isEmpty {
                                    Text(L("%d fitted programs reported", aid.programIDs.count)).font(AppType.caption).foregroundStyle(.secondary)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Brand.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                Text(L("Volume, equalizers and supported everyday controls remain available in Sound and Programs."))
                    .font(AppType.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var featureCatalog: some View {
        Surface {
            ExpandableSection(isExpanded: $showingCatalog) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                    ForEach(catalog) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(item.title, systemImage: item.symbol).font(AppType.callout.weight(.semibold))
                            Text(item.detail).font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Text(item.status).font(AppType.small.weight(.medium)).foregroundStyle(item.destination == nil ? Color.secondary : Brand.accent)
                                Spacer(minLength: 2)
                                if let destination = item.destination {
                                    Button { navigation.page = destination } label: { Image(systemName: "arrow.up.right") }
                                        .buttonStyle(.borderless).accessibilityLabel(L("Open %@", destination.title))
                                }
                            }
                        }.padding(15).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Brand.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
                    }
                }.padding(.top, 18)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("Explore the fitting toolkit"), systemImage: "square.grid.3x3").font(AppType.headline)
                    Text(L("See what you can use now, what you can plan, and which tools need a verified clinical fitting path."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var catalog: [CatalogItem] {
        [
            .init(id: "volume", title: L("Volume & mute"), detail: L("Adjust your current listening level using the controls already available in Audifern."), symbol: "speaker.wave.2", status: connectedAids.contains(where: \.canChangeVolume) ? L("Available for connected aids") : L("Connect to check"), destination: .hearingAids),
            .init(id: "eq", title: L("Microphone & streaming EQ"), detail: L("Personalize the sound of an existing fitted program in Sound."), symbol: "slider.horizontal.3", status: L("Device and program dependent"), destination: .sound),
            .init(id: "booster", title: L("SpeechBooster"), detail: L("Use the consumer speech boost when the active program supports it."), symbol: "person.wave.2", status: L("Device and program dependent"), destination: .sound),
            .init(id: "tinnitus", title: L("Tinnitus SoundSupport"), detail: L("Existing therapy controls require an eligible professionally fitted program."), symbol: "waveform", status: L("Fitted program required"), destination: .sound),
            .init(id: "audiogram", title: L("Audiogram records"), detail: L("Enter, plot and export the results of an existing exam."), symbol: "chart.xyaxis.line", status: L("Available locally"), destination: .audiogram),
            .init(id: "backup", title: L("Backup & recovery"), detail: L("Save readable device state. Complete clinical restore still needs verification."), symbol: "externaldrive.badge.checkmark", status: L("Readable-state backup"), destination: .backups),
            .init(id: "programs", title: L("Fitted-program creation"), detail: L("Prepare program ideas here. Creating a fitted slot requires a verified prescription and programming path."), symbol: "square.stack.3d.up", status: L("Plan locally")),
            .init(id: "gains", title: L("Gain, compression & MPO"), detail: L("Clinical amplification and maximum output need a validated fitting engine and acoustic context."), symbol: "slider.vertical.3", status: L("Clinical fitting required")),
            .init(id: "feedback", title: L("Feedback calibration"), detail: L("A measured feedback test must match the receiver, earpiece and the wearer’s ear."), symbol: "waveform.path", status: L("Clinical fitting required")),
            .init(id: "real-ear", title: L("Real-ear verification"), detail: L("Measure and verify actual amplification with compatible measurement equipment."), symbol: "ear", status: L("Measurement equipment required")),
            .init(id: "in-situ", title: L("In-situ audiometry"), detail: L("Hearing-aid test tones need a verified measurement workflow."), symbol: "waveform.badge.magnifyingglass", status: L("Clinical fitting required")),
            .init(id: "automation", title: L("Directionality & noise processing"), detail: L("Clinical noise and microphone settings belong to the fitted program, beyond consumer EQ."), symbol: "dot.radiowaves.left.and.right", status: L("Clinical fitting required")),
            .init(id: "accessories", title: L("Accessories, buttons & indicators"), detail: L("Fitted accessory behavior and hardware-button settings need model-specific verification."), symbol: "button.programmable", status: L("Clinical fitting required")),
            .init(id: "logging", title: L("Usage data & logging"), detail: L("A complete usage history has not been read by this workspace."), symbol: "clock.arrow.circlepath", status: L("Not available yet")),
            .init(id: "firmware", title: L("Firmware updates"), detail: L("Firmware installation and recovery are not available in Audifern."), symbol: "arrow.triangle.2.circlepath", status: L("Not available yet")),
            .init(id: "remote", title: L("Remote fitting"), detail: L("Remote clinical sessions require a supported provider service and fitting workflow."), symbol: "person.crop.rectangle.badge.waveform", status: L("Not available yet"))
        ]
    }

    private struct CatalogItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let status: String
        var destination: AppPage? = nil
    }

    private func sectionHeading(_ title: String, number: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(AppType.caption.weight(.bold)).foregroundStyle(Brand.accent)
                .frame(width: 26, height: 26).background(Brand.accent.opacity(0.1), in: Circle()).accessibilityHidden(true)
            Text(title).font(AppType.headline)
            Spacer(minLength: 0)
            Image(systemName: symbol).font(AppType.callout).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppType.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title).accessibilityIdentifier(id)
        }
    }

    private func capsule(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol).font(AppType.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6).background(tint.opacity(0.08), in: Capsule())
    }

    private func message(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(AppType.caption).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }

    private func openAudiogram() {
        if let id = draft.audiogramID, id != audiograms.draft.id {
            if audiograms.isDirty {
                editorMessage = L("The audiogram editor has unsaved changes. Finish those before switching to the linked exam.")
            } else { audiograms.select(id) }
        }
        navigation.show(.audiogram)
    }
}
