import SwiftUI
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var path = NavigationPath()
    @Published var editorVideoURL: URL?
    @Published var isEditorPresented = false
    
    private let dependencyContainer: DependencyContainer
    
    init(dependencyContainer: DependencyContainer? = nil) {
        self.dependencyContainer = dependencyContainer ?? DependencyContainer.shared
    }
    
    func start() -> some View {
        AppCoordinatorView(coordinator: self)
    }
    
    
    func makeDashboardView() -> some View {
        let viewModel = DashboardViewModel(
            xcodeProjectService: dependencyContainer.xcodeProjectService,
            automationService: dependencyContainer.automationService,
            deviceDiscoveryService: dependencyContainer.deviceDiscoveryService,
            recordingService: dependencyContainer.recordingService,
            captureService: dependencyContainer.captureService,
            coordinator: self
        )
        
        viewModel.onRecordingFinished = { [weak self] url in
            self?.showEditor(for: url)
        }
        
        return DashboardView(viewModel: viewModel)
    }
    
    func makeEditorView(videoURL: URL) -> some View {
        EditorView(videoURL: videoURL)
    }
    
    
    // URL Command Handling
    let urlCommandSubject = PassthroughSubject<URLCommand, Never>()
    
    enum URLCommand {
        case start
        case stop
    }
    
    func handle(url: URL) {
        // autovid://start
        // autovid://stop
        
        guard let host = url.host() else { return }
        
        switch host {
        case "start":
            urlCommandSubject.send(.start)
        case "stop":
            urlCommandSubject.send(.stop)
        default:
            print("Unknown URL command: \(host)")
        }
    }

    func showEditor(for url: URL) {
        self.editorVideoURL = url
        self.isEditorPresented = true
    }
    
    func dismissEditor() {
        self.isEditorPresented = false
        self.editorVideoURL = nil
    }
}

struct AppCoordinatorView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeDashboardView()
                .navigationDestination(for: String.self) { route in
                    Text("Route: \(route)")
                }
        }
        .sheet(isPresented: $coordinator.isEditorPresented) {
            if let url = coordinator.editorVideoURL {
                coordinator.makeEditorView(videoURL: url)
            }
        }
    }
}

