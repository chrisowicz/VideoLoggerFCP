import Foundation

/// Small, synthetic project resources shared by test targets only.
public enum FixtureResources {
    public static func project(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "llc", subdirectory: "Projects") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
