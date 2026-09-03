import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        Group {
            if appState.hasConfiguredEndpoint, let url = appState.endpointURL {
                HarnessScreen(url: url, showingSettings: $showingSettings)
                    .id(appState.endpointString)
            } else {
                WelcomeView(showingSettings: $showingSettings)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct WelcomeView: View {
    @Binding var showingSettings: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 54))
                    .foregroundColor(.accentColor)

                Text("DeepSeek Harness")
                    .font(.title2.weight(.semibold))

                Text("连接你自己的 Harness 服务，继续使用会话、模型、Plugins、Skills 和文件能力。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button {
                    showingSettings = true
                } label: {
                    Label("配置服务地址", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 44)

                Text("支持 HTTP 与 HTTPS\n公网访问请优先使用 HTTPS 或 VPN/组网")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .navigationTitle("开始使用")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

struct HarnessScreen: View {
    let url: URL
    @Binding var showingSettings: Bool
    @StateObject private var webStore = WebViewStore()

    var body: some View {
        NavigationView {
            ZStack {
                HarnessWebView(url: url, store: webStore)
                    .ignoresSafeArea(edges: .bottom)

                if webStore.isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if let error = webStore.lastError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 34))
                        Text("页面加载失败")
                            .font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重新加载") {
                            webStore.clearError()
                            webStore.reload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            }
            .navigationTitle("Harness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        webStore.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!webStore.canGoBack)

                    Button {
                        webStore.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!webStore.canGoForward)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        webStore.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
