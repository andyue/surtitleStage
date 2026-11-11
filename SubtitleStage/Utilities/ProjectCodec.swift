import Foundation

public enum ProjectCodec {
    public static func encode(_ project: Project) throws -> Data {
        try project.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }
    public static func decode(_ data: Data) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: data)
        try project.validate()
        return project
    }
    public static func save(_ project: Project, to url: URL) throws {
        try encode(project).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> Project { try decode(Data(contentsOf: url)) }
}
