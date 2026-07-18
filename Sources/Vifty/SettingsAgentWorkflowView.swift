import SwiftUI
import ViftyCore

struct SettingsAgentWorkflowView: View {
    @ObservedObject var model: AppModel
    @StateObject private var copiedFeedbackScheduler: CopyFeedbackScheduler
    @State private var agentRuleCopied = false
    @State private var agentCommandCopied = false

    init(
        model: AppModel,
        copiedFeedbackScheduler: CopyFeedbackScheduler = CopyFeedbackScheduler()
    ) {
        self.model = model
        _copiedFeedbackScheduler = StateObject(wrappedValue: copiedFeedbackScheduler)
    }

    var body: some View {
        SettingsPane(accessibilityPane: .agentWorkflows) {
            SettingsCategorySection(title: "Agent Workflows", systemImage: "terminal") {
                Text("Guarded commands request bounded cooling leases; they never expose direct fan controls.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Commands") {
                Menu {
                    ForEach(AgentWorkflowSupport.WorkloadCommandMode.allCases) { mode in
                        Section(mode.menuTitle) {
                            ForEach(AgentWorkflowSupport.safeWorkloadCommandTemplates) { template in
                                Button(template.title) {
                                    copyAgentWorkflowCommand(template, mode)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Copy Command", systemImage: "terminal")
                }
                .help(AgentWorkflowSupport.copyCommandHelp)

                if agentCommandCopied {
                    Label(AgentWorkflowSupport.copiedCommandMessage, systemImage: "checkmark.circle")
                        .viftyFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Agent Rule") {
                Text("Copy the safety contract into an agent's project instructions before running guarded workloads.")
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copyAgentWorkflowRule()
                } label: {
                    Label("Copy Agent Rule", systemImage: "doc.on.doc")
                }
                .help(AgentWorkflowSupport.copyHelp)

                if agentRuleCopied {
                    Label(AgentWorkflowSupport.copiedMessage, systemImage: "checkmark.circle")
                        .viftyFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            copiedFeedbackScheduler.cancel()
        }
    }

    private func copyAgentWorkflowRule() {
        AgentWorkflowSupport.copyAgentRule()
        agentRuleCopied = true
        agentCommandCopied = false
        scheduleCopiedFeedbackReset()
    }

    private func copyAgentWorkflowCommand(
        _ template: AgentWorkflowSupport.WorkloadCommandTemplate,
        _ mode: AgentWorkflowSupport.WorkloadCommandMode
    ) {
        AgentWorkflowSupport.copyWorkloadCommand(template, mode: mode)
        agentRuleCopied = false
        agentCommandCopied = true
        scheduleCopiedFeedbackReset()
    }

    private func scheduleCopiedFeedbackReset() {
        copiedFeedbackScheduler.schedule {
            agentRuleCopied = false
            agentCommandCopied = false
        }
    }
}
