import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var validationMessage: String?
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("http://192.168.31.250:端口", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Harness 服务地址")
                } footer: {
                    Text("必须以 http:// 或 https:// 开头，不能在地址中包含用户名、密码或 Token。")
                }

                Section {
                    Button("保存并连接") {
                        save()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if appState.hasConfiguredEndpoint {
                        Button("清除本机网页会话", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                } footer: {
                    Text("清除会删除本机 WebKit Cookie 和网页缓存，不会删除服务器上的会话、文件或其他数据。")
                }

                Section("关于") {
                    LabeledContent("最低系统", value: "iOS 15.0")
                    LabeledContent("网络", value: "HTTP / HTTPS")
                    LabeledContent("版本", value: "首版开发中")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("关闭") {
                    dismiss()
                }
            )
            .onAppear {
                draft = appState.endpointString
            }
            .confirmationDialog(
                "清除本机网页会话？",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    clearWebSession()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("下次打开 Harness 时可能需要重新登录。")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        guard appState.saveEndpoint(draft) else {
            validationMessage = "地址无效。请填写完整的 HTTP 或 HTTPS 地址。"
            return
        }
        validationMessage = nil
        dismiss()
    }

    private func clearWebSession() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async {
                appState.clearEndpoint()
                dismiss()
            }
        }
    }
}
