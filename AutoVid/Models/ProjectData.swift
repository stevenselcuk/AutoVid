import Foundation

struct XcodeBuildOutput: Decodable, Sendable {
    let project: ProjectData?
    let workspace: ProjectData?
}

struct ProjectData: Decodable, Sendable {
    let schemes: [String]?
    let targets: [String]?
}
