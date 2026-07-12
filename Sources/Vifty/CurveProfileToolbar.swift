import SwiftUI
import ViftyCore

struct CurveProfileToolbar: View {
    let profiles: [CurveProfile]
    @Binding var selectedProfileID: CurveProfile.ID?
    let selectProfile: (CurveProfile.ID?) -> Void
    let loadPreset: (DeveloperFanPreset) -> Void
    let saveProfile: (String) -> Void
    let deleteProfile: (CurveProfile) -> Void

    @State private var newProfileName = ""
    @State private var showSaveSheet = false
    @State private var profilePendingDeletion: CurveProfile?

    var body: some View {
        HStack(spacing: 8) {
            Picker("Profile", selection: $selectedProfileID) {
                Text("Unsaved").tag(Optional<CurveProfile.ID>.none)
                ForEach(profiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .onChange(of: selectedProfileID) { _, profileID in
                selectProfile(profileID)
            }

            Menu {
                ForEach(DeveloperFanPreset.allCases) { preset in
                    Button {
                        loadPreset(preset)
                    } label: {
                        Label(preset.displayName, systemImage: preset.systemImage)
                    }
                }
            } label: {
                Label("Presets", systemImage: "slider.horizontal.3")
            }
            .controlSize(.small)

            Button {
                showSaveSheet = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            if let selectedProfile = selectedProfile {
                Button(role: .destructive) {
                    profilePendingDeletion = selectedProfile
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
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
                deleteProfile(profile)
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("Delete \(profile.name)? This cannot be undone.")
        }
    }

    private var selectedProfile: CurveProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    private var saveProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Curve Profile")
                .font(.headline)
            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    newProfileName = ""
                    showSaveSheet = false
                }
                Button("Save") {
                    let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    saveProfile(name)
                    newProfileName = ""
                    showSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
