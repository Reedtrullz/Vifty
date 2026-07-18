import SwiftUI
import ViftyCore

struct CurveProfileToolbar: View {
    let profiles: [CurveProfile]
    let selectedProfileID: CurveProfile.ID?
    let editState: CurveProfileEditState
    let recoveryMessage: String?
    let dispatcher: FanControlPanelActionDispatcher

    @State private var newProfileName = ""
    @State private var showSaveSheet = false
    @State private var profilePendingDeletion: CurveProfile?
    @State private var pendingOverwriteName: String?
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileIdentityRow
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    profileActions
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        presetsMenu
                        if selectedProfile != nil {
                            updateButton
                        }
                        saveAsButton
                    }
                    if selectedProfile != nil {
                        deleteButton
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showSaveSheet) {
            saveProfileSheet
        }
        .confirmationDialog(
            "Delete profile?",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        profilePendingDeletion = nil
                    }
                }
            ),
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                dispatcher.deleteCurveProfile(profile.id)
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("Delete \(profile.name)? This cannot be undone.")
        }
        .confirmationDialog(
            "Replace saved profile?",
            isPresented: Binding(
                get: { pendingOverwriteName != nil },
                set: { isPresented in
                    if !isPresented { pendingOverwriteName = nil }
                }
            )
        ) {
            if let pendingOverwriteName {
                Button("Replace \(pendingOverwriteName)", role: .destructive) {
                    let result = dispatcher.saveCurveProfile(
                        name: pendingOverwriteName,
                        confirmOverwrite: true
                    )
                    self.pendingOverwriteName = nil
                    if case .persistenceFailed(let message)? = result {
                        newProfileName = pendingOverwriteName
                        saveErrorMessage = message
                        showSaveSheet = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingOverwriteName = nil
            }
        } message: {
            Text("Save As found an existing profile with this name. Replacing it keeps the saved profile identity but updates its curve.")
        }
    }

    private var profileIdentityRow: some View {
        HStack(spacing: 8) {
            Picker("Profile", selection: selectedProfileBinding) {
                Text("Unsaved").tag(Optional<CurveProfile.ID>.none)
                ForEach(profiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            if toolbarPresentation.showsEditedBadge {
                Label("Edited", systemImage: "pencil.circle.fill")
                    .viftyFont(.caption, weight: .semibold)
                    .foregroundStyle(.orange)
                    .fixedSize()
            }

            if let recoveryMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(recoveryMessage)
                    .accessibilityLabel("Profile backup recovered")
                    .accessibilityHint(recoveryMessage)
            }
        }
    }

    @ViewBuilder
    private var profileActions: some View {
        presetsMenu
        if selectedProfile != nil {
            updateButton
        }
        saveAsButton
        if selectedProfile != nil {
            deleteButton
        }
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(DeveloperFanPreset.allCases) { preset in
                Button {
                    dispatcher.developerPresetSelected(preset)
                } label: {
                    Label(preset.displayName, systemImage: preset.systemImage)
                }
            }
        } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
        }
        .controlSize(.small)
    }

    private var updateButton: some View {
        Button {
            dispatcher.updateCurveProfile()
        } label: {
            Label("Update", systemImage: "arrow.triangle.2.circlepath")
        }
        .controlSize(.small)
        .disabled(!toolbarPresentation.canUpdate)
        .help(toolbarPresentation.canUpdate ? "Update the selected profile without changing its identity." : "The selected profile is already saved.")
    }

    private var saveAsButton: some View {
        Button {
            saveErrorMessage = nil
            newProfileName = ""
            showSaveSheet = true
        } label: {
            Label("Save As", systemImage: "plus.square.on.square")
        }
        .controlSize(.small)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if let selectedProfile {
                profilePendingDeletion = selectedProfile
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .controlSize(.small)
    }

    private var selectedProfile: CurveProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    private var selectedProfileBinding: Binding<CurveProfile.ID?> {
        Binding(
            get: { selectedProfileID },
            set: { profileID in dispatcher.curveProfileSelected(profileID) }
        )
    }

    private var toolbarPresentation: CurveProfileToolbarPresentation {
        CurveProfileToolbarPresentation.resolve(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            editState: editState
        )
    }

    private var saveProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Curve Profile As")
                .viftyFont(.headline)
            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
            if let saveErrorMessage {
                Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .viftyFont(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    saveErrorMessage = nil
                    newProfileName = ""
                    showSaveSheet = false
                }
                Button("Save As") {
                    let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let result = dispatcher.saveCurveProfile(
                        name: name,
                        confirmOverwrite: false
                    )
                    switch result {
                    case .created?, .updated?:
                        saveErrorMessage = nil
                        newProfileName = ""
                        showSaveSheet = false
                    case .overwriteConfirmationRequired?:
                        saveErrorMessage = nil
                        newProfileName = ""
                        showSaveSheet = false
                        pendingOverwriteName = name
                    case .persistenceFailed(let message)?:
                        saveErrorMessage = message
                    case nil:
                        break
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
