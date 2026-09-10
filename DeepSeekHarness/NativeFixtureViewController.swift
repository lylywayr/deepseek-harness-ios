import UIKit

#if DEBUG
/// Debug-only screenshot host. Every scene embeds the real Pocket Workspace
/// controllers and a deterministic Runtime projection; no legacy fixture UI is
/// used as delivery evidence.
final class NativeFixtureViewController: UIViewController {
    private let screen: String
    private let appState = AppState()
    private let store = NativeUIStore()
    private var home: NativeHomeViewController!
    private var applied = false

    init(screen: String) {
        self.screen = screen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DHTheme.background
        let scene = normalizedScene(screen)
        let runtime = HarnessRuntime.fixture(scene: scene)
        let transport = NativeUITransport(baseURL: URL(string: "http://fixture.invalid")!)
        home = NativeHomeViewController(appState: appState, nativeUIStore: store, transport: transport, runtime: runtime, onSettings: { _ in })
        addChild(home)
        home.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(home.view)
        NSLayoutConstraint.activate([
            home.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            home.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            home.view.topAnchor.constraint(equalTo: view.topAnchor),
            home.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        home.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !applied else { return }
        applied = true
        DispatchQueue.main.async { [weak self] in self?.applyScene() }
    }

    private func normalizedScene(_ value: String) -> String {
        switch value {
        case "workspace", "drawer", "flat", "conversation", "normal", "process", "trajectory", "artifacts", "activity", "settings", "keyboard": return value
        default: return "workspace"
        }
    }

    private func applyScene() {
        switch normalizedScene(screen) {
        case "drawer": home.fixtureOpenDrawer()
        case "flat": home.fixtureOpenFlatDrawer()
        case "conversation": home.fixtureOpenConversation()
        case "normal": home.fixtureOpenNormalConversation()
        case "process": home.fixtureSelectMode(1)
        case "trajectory": home.fixtureSelectMode(2)
        case "artifacts": home.fixtureSelectMode(3)
        case "activity": home.fixtureShowActivity()
        case "settings": home.fixtureShowSettings()
        case "keyboard": home.fixtureFocusComposer()
        default: home.fixtureCloseDrawer()
        }
    }
}
#endif
