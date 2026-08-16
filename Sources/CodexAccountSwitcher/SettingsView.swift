import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message = ""

    var body: some View {
        Form {
            Toggle("로그인할 때 Codex Account Switcher 실행", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        message = enabled ? "로그인 시 실행을 켰습니다" : "로그인 시 실행을 껐습니다"
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        message = error.localizedDescription
                    }
                }
            Text("계정 전환은 메뉴에서 사용자가 직접 누를 때만 실행됩니다. 한도 도달 시 자동 전환은 지원하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
