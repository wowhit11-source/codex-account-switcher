import AppKit
import CodexAccountSwitcherCore
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            currentAccount
            usage
            Divider()
            profiles
            controls
            Divider()
            continuity
            status
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task { await model.bootstrap() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Codex Account Switcher").font(.headline)
                Text(model.environment?.officialApp.map { "공식 앱 \($0.shortVersion ?? "버전 미확인")" } ?? "공식 앱 확인 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var currentAccount: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentAccountTitle).font(.caption).foregroundStyle(.secondary)
            if model.accountDisplayMode == .officialHostManaged {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.orange)
                    Text("공식 앱 내부 계정")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("앱에서 확인")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                Text("호스트 관리 인증 사용 중 · auth.json 계정을 현재 계정으로 표시하지 않음")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let account = model.currentAccount {
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(Redactor.maskEmail(account.email) ?? "이메일 없음").fontWeight(.semibold)
                    Spacer()
                    Text(account.planType?.capitalized ?? account.type)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            } else if model.accountDisplayMode == .checking {
                Label("계정 정보 확인 중", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Label("인증된 ChatGPT 계정 없음", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentAccountTitle: String {
        switch model.accountDisplayMode {
        case .checking:
            "계정 정보"
        case .officialHostManaged:
            "공식 앱 현재 계정"
        case .storedAuthentication:
            "저장된 인증 계정"
        case .switchVerified:
            "방금 전환한 계정"
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Codex 사용량").font(.caption).foregroundStyle(.secondary)
            if model.accountDisplayMode == .officialHostManaged {
                Text("공식 앱 내부 계정의 사용량은 공식 앱에서 확인하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let primary = model.rateLimits?.primary {
                ProgressView(value: min(max(primary.usedPercent, 0), 100), total: 100)
                HStack {
                    Text("Primary 사용 \(primary.usedPercent, specifier: "%.0f")%")
                    Spacer()
                    if let reset = primary.resetsAt {
                        Text("초기화 \(reset, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("사용량 정보 없음").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("등록된 계정").font(.caption).foregroundStyle(.secondary)
            if !model.oneClickSwitchAvailability.isAvailable,
               model.environment?.officialAppAuthenticationMode != .hostManaged,
               model.oneClickSwitchAvailability.reason != "환경 확인 중",
               let reason = model.oneClickSwitchAvailability.reason {
                Label(reason, systemImage: "exclamationmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.profiles.isEmpty {
                Text("등록된 프로필이 없습니다").font(.caption).foregroundStyle(.secondary)
            } else if model.profiles.count <= 3 {
                profileRows
            } else {
                ScrollView {
                    profileRows
                }
                .frame(height: 190)
            }
        }
    }

    private var profileRows: some View {
        LazyVStack(alignment: .leading, spacing: 7) {
            ForEach(model.profiles) { profile in
                profileRow(profile)
            }
        }
    }

    private func profileRow(_ profile: AccountProfile) -> some View {
        let isVerifiedActive = profile.isActive && model.accountDisplayMode != .officialHostManaged
        return HStack {
            Image(systemName: isVerifiedActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isVerifiedActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                Text([profile.planType?.capitalized, profile.maskedEmail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if profile.isActive && model.accountDisplayMode == .officialHostManaged {
                    Text("스위처의 마지막 전환 기록 · 현재 여부 미확인")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isVerifiedActive {
                if model.environment?.officialAppAuthenticationMode == .hostManaged {
                    Button("공식 로그인") { model.guidedSwitch(to: profile) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                } else if model.oneClickSwitchAvailability.isAvailable {
                    Button("전환") { model.requestSwitch(to: profile) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                } else {
                    Text("원클릭 불가")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                        .help(model.oneClickSwitchAvailability.reason ?? "원클릭 전환을 사용할 수 없습니다")
                }
            }
            Menu {
                Button("브라우저로 계정 변경") { model.requestAccountChange(profile, flow: .browser) }
                Button("Device Code로 계정 변경") { model.requestAccountChange(profile, flow: .deviceCode) }
                Divider()
                Button("프로필 삭제", role: .destructive) { model.deleteProfile(profile) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isBusy)
        }
    }

    private var controls: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 7) {
            GridRow {
                Button("저장 인증 등록") { model.captureCurrentAccount() }
                    .disabled(model.isBusy || model.storedAccount == nil)
                    .help("~/.codex/auth.json에 저장된 계정을 등록합니다. 공식 앱의 호스트 관리 계정과 다를 수 있습니다.")
                Button("계정 추가") { model.addAccount(flow: .browser) }
                    .disabled(model.isBusy)
            }
            GridRow {
                Button("Device Code 추가") { model.addAccount(flow: .deviceCode) }
                    .disabled(model.isBusy)
                Button("계정 정보 새로고침") { Task { await model.refreshAll() } }
                    .disabled(model.isBusy)
            }
            GridRow {
                Button("Codex 앱 열기") { model.openOfficialApp() }
                Button("긴급 복구") { model.emergencyRestore() }
                    .disabled(model.isBusy)
            }
            GridRow {
                Button("Guided Switch") { model.guidedSwitch() }
                    .disabled(model.isBusy)
                Color.clear.frame(height: 1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var continuity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Session Continuity Test").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let verdict = model.continuityRecord?.verdict {
                    Text(verdict.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(verdict == .pass ? .green : verdict == .pending ? .secondary : .orange)
                }
            }
            if let record = model.continuityRecord {
                Text(record.marker).font(.caption2.monospaced()).textSelection(.enabled)
                HStack {
                    Button("마커 찾기") { model.locateContinuityMarker() }
                    Button("PASS") { model.finishContinuityTest(.pass) }
                    Button("PARTIAL") { model.finishContinuityTest(.partial) }
                    Button("FAIL") { model.finishContinuityTest(.fail) }
                }
                .controlSize(.mini)
            } else {
                Button("연속성 테스트 시작") { model.beginContinuityTest() }
                    .controlSize(.small)
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isBusy && model.phase != .idle && model.phase != .completed {
                ProgressView().controlSize(.small)
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(model.statusMessage.contains("실패") || model.statusMessage.contains("오류") ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let comparison = model.lastSnapshotComparison {
                Text("보호 파일: 삭제 \(comparison.deleted.count) · 변경 \(comparison.modified.count) · 유지 \(comparison.unchangedCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("진단 보고서") { model.openBundledDocument("ENVIRONMENT_REPORT.md") }
            Button("도움말") { model.openBundledDocument("TROUBLESHOOTING.md") }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
        }
        .buttonStyle(.plain)
    }
}
