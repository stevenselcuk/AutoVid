import Foundation
import Combine
import SwiftUI

@MainActor
protocol XcodeProjectServiceProtocol: AnyObject {
    var availableProjects: [String] { get }
    var availableSchemes: [String] { get }
    var isLoadingProjects: Bool { get }
    var isLoadingSchemes: Bool { get }
    var status: String { get }
    
    var availableProjectsPublisher: AnyPublisher<[String], Never> { get }
    var availableSchemesPublisher: AnyPublisher<[String], Never> { get }
    var isLoadingProjectsPublisher: AnyPublisher<Bool, Never> { get }
    var isLoadingSchemesPublisher: AnyPublisher<Bool, Never> { get }
    var statusPublisher: AnyPublisher<String, Never> { get }
    
    func findXcodeProjects()
    func fetchSchemes(for path: String, currentScheme: String)
}

private struct LocalXcodeBuildOutput: Decodable {
    let project: LocalProjectData?
    let workspace: LocalProjectData?
}

private struct LocalProjectData: Decodable {
    let schemes: [String]?
}

@MainActor
final class XcodeProjectService: ObservableObject, XcodeProjectServiceProtocol {
    @Published var availableProjects: [String] = []
    @Published var availableSchemes: [String] = []
    @Published var isLoadingProjects = false
    @Published var isLoadingSchemes = false
    @Published var status = "IDLE"
    
    var availableProjectsPublisher: AnyPublisher<[String], Never> { $availableProjects.eraseToAnyPublisher() }
    var availableSchemesPublisher: AnyPublisher<[String], Never> { $availableSchemes.eraseToAnyPublisher() }
    var isLoadingProjectsPublisher: AnyPublisher<Bool, Never> { $isLoadingProjects.eraseToAnyPublisher() }
    var isLoadingSchemesPublisher: AnyPublisher<Bool, Never> { $isLoadingSchemes.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<String, Never> { $status.eraseToAnyPublisher() }
    
    @AppStorage("cachedProjects") private var cachedProjectsData: Data = Data()
    @AppStorage("hasScannedProjects") private var hasScannedProjects = false
    
    private var projectScanTask: Task<Void, Never>?
    private var schemeFetchTask: Task<Void, Never>?
    
    private var cachedProjects: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: cachedProjectsData)) ?? []
        }
        set {
            cachedProjectsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    init() {
        availableProjects = cachedProjects
        
        if !hasScannedProjects {
            findXcodeProjects()
        }
    }
    
    deinit {
        projectScanTask?.cancel()
        schemeFetchTask?.cancel()
    }
    
    func findXcodeProjects() {
        projectScanTask?.cancel()
        projectScanTask = Task(priority: .background) { @MainActor in
            self.isLoadingProjects = true
            self.status = "Scanning Projects..."
            defer {
                self.isLoadingProjects = false
                if self.status == "Scanning Projects..." {
                    self.status = "IDLE"
                }
            }

            let foundProjects = await Task.detached(priority: .background) {
                let fileManager = FileManager.default
                let homeURL = fileManager.homeDirectoryForCurrentUser
                let documentsURL = homeURL.appendingPathComponent("Documents")
                let developmentURL = homeURL.appendingPathComponent("Development")

                var projects: [String] = []
                let searchPaths = [documentsURL, developmentURL].filter { fileManager.fileExists(atPath: $0.path) }

                for path in searchPaths {
                    if Task.isCancelled { break }

                    guard let enumerator = fileManager.enumerator(
                        at: path,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }

                    let urls = enumerator.allObjects.compactMap { $0 as? URL }

                    for fileURL in urls {
                        if Task.isCancelled { break }

                        if fileURL.pathExtension == "xcodeproj" || fileURL.pathExtension == "xcworkspace" {
                            projects.append(fileURL.path)
                        }
                    }
                }

                return Array(Set(projects)).sorted()
            }.value

            self.availableProjects = foundProjects
            self.cachedProjects = foundProjects
            self.hasScannedProjects = true
        }
    }
    
    func fetchSchemes(for path: String, currentScheme: String) {
        guard !path.isEmpty else {
            availableSchemes = []
            return
        }

        schemeFetchTask?.cancel()
        schemeFetchTask = Task(priority: .userInitiated) { @MainActor in
            self.isLoadingSchemes = true
            self.status = "Fetching Schemes..."
            defer {
                self.isLoadingSchemes = false
                if self.status == "Fetching Schemes..." {
                    self.status = "IDLE"
                }
            }

            let result = await Task.detached(priority: .userInitiated) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                let projectFlag = path.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
                task.arguments = ["-list", "-json", projectFlag, path]

                let pipe = Pipe()
                task.standardOutput = pipe

                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    if let output = try? JSONDecoder().decode(LocalXcodeBuildOutput.self, from: data) {
                        let schemes = output.project?.schemes ?? output.workspace?.schemes ?? []
                        return (schemes: schemes.sorted(), error: nil as String?)
                    } else {
                        let text = String(data: data, encoding: .utf8) ?? ""
                        print("JSON decode failed. Raw output: \(text)")
                        return (schemes: [String](), error: "SCHEME ERROR")
                    }
                } catch {
                    print("Failed to fetch schemes: \(error)")
                    return (schemes: [String](), error: "SCHEME ERROR")
                }
            }.value

            self.availableSchemes = result.schemes
            
            if let error = result.error {
                self.status = error
            } else {
                self.status = "Ready 1"
            }
        }
    }
}

