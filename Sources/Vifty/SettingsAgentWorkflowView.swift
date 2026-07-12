import SwiftUI
import ViftyCore

struct SettingsAgentWorkflowView: View {
    @ObservedObject var model: AppModel
    @State private var agentRuleCopied = false
    @State private var agentCommandCopied = false
    @State private var copiedFeedbackTask: Task<Void, Never>?

    var body: some View {
        SettingsCategorySection(title: "Agent Workflows", systemImage: "terminal") {
            Text("Copy guarded workload commands and the Vifty agent rule. These commands request bounded cooling leases; they do not expose direct fan controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

            Button {
                copyAgentWorkflowRule()
            } label: {
                Label("Copy Agent Rule", systemImage: "doc.on.doc")
            }
            .help(AgentWorkflowSupport.copyHelp)

            if agentRuleCopied {
                Text(AgentWorkflowSupport.copiedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if agentCommandCopied {
                Text(AgentWorkflowSupport.copiedCommandMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            copiedFeedbackTask?.cancel()
            copiedFeedbackTask = nil
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
        copiedFeedbackTask?.cancel()
        copiedFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            agentRuleCopied = false
            agentCommandCopied = false
            copiedFeedbackTask = nil
        }
    }
}
