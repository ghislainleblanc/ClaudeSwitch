//
//  MenuContentView.swift
//  Claude Switch
//

import SwiftUI

struct MenuContentView: View {
    let viewModel: SwitcherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if viewModel.needsInitialSetup {
                setupSection
            } else {
                profileSection
            }

            if let status = viewModel.status {
                statusView(for: status)
                if status == .sessionMismatch {
                    assignmentButtons
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.menuSymbolName)
                .font(.title3)
                .foregroundStyle(.tint)
            Text("app.name")
                .font(.headline)
            Spacer()
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("setup.question")
                .font(.subheadline.weight(.semibold))
            Text("setup.explanation")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            assignmentButtons
        }
    }

    private var assignmentButtons: some View {
        ForEach(Profile.allCases) { profile in
            Button {
                Task { await viewModel.assignCurrentSession(to: profile) }
            } label: {
                Label(profile.localizedName, systemImage: profile.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isBusy)
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Profile.allCases) { profile in
                profileRow(for: profile)
            }
        }
    }

    private func profileRow(for profile: Profile) -> some View {
        let isActive = viewModel.activeProfile == profile

        return Button {
            Task { await viewModel.switchTo(profile) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: profile.symbolName)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.localizedName)
                        .font(.body)
                    Text(subtitle(for: profile, isActive: isActive))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .background(isActive ? AnyShapeStyle(.selection.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .disabled(viewModel.isBusy || isActive)
    }

    private func subtitle(for profile: Profile, isActive: Bool) -> String {
        if isActive {
            return String(localized: "profile.active")
        }
        if let date = viewModel.snapshotDates[profile] {
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            return String(format: String(localized: "profile.lastSavedFormat"), formatted)
        }
        return String(localized: "profile.notSavedYet")
    }

    @ViewBuilder
    private func statusView(for status: SwitcherViewModel.Status) -> some View {
        switch status {
        case .saving(let profile):
            statusLabel(String(format: String(localized: "status.savingFormat"), profile.localizedName),
                        systemImage: "arrow.down.doc", style: .secondary)
        case .switching(let profile):
            statusLabel(String(format: String(localized: "status.switchingFormat"), profile.localizedName),
                        systemImage: "arrow.triangle.2.circlepath", style: .secondary)
        case .switched(let profile):
            statusLabel(String(format: String(localized: "status.switchedFormat"), profile.localizedName),
                        systemImage: "checkmark.circle", style: .green)
        case .signInRequired(let profile):
            statusLabel(String(format: String(localized: "status.signInRequiredFormat"), profile.localizedName),
                        systemImage: "person.crop.circle.badge.exclamationmark", style: .orange)
        case .sessionMismatch:
            statusLabel(String(localized: "status.sessionMismatch"),
                        systemImage: "questionmark.circle", style: .orange)
        case .failure(let message):
            statusLabel(String(format: String(localized: "status.failureFormat"), message),
                        systemImage: "exclamationmark.triangle", style: .red)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, style: some ShapeStyle) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(style)
    }

}

#Preview {
    MenuContentView(viewModel: SwitcherViewModel())
}
