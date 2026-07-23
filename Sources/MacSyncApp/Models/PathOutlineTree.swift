import Foundation

struct PathOutlineItem: Hashable {
    let path: String
    let kind: SnapshotFile.Kind
}

struct PathOutlineNode: Identifiable, Hashable {
    let path: String
    let title: String
    let kind: SnapshotFile.Kind
    let isExplicitSelection: Bool
    let children: [PathOutlineNode]?

    var id: String {
        path
    }
}

/// Builds the disclosure hierarchy used by the path-selection views without
/// changing the flat paths persisted in config/sync-paths.txt.
enum PathOutlineTree {
    static func nodes(for items: [PathOutlineItem]) -> [PathOutlineNode] {
        var nodesByPath = [String: MutableNode]()
        var rootPaths = [String]()

        for item in items where !item.path.isEmpty {
            var parent: MutableNode?
            let paths = ancestorPaths(for: item.path)
            for (index, path) in paths.enumerated() {
                let node: MutableNode
                if let existing = nodesByPath[path] {
                    node = existing
                } else {
                    node = MutableNode(path: path, kind: .folder)
                    nodesByPath[path] = node
                    if let parent {
                        parent.children[path] = node
                    } else {
                        rootPaths.append(path)
                    }
                }

                if index == paths.count - 1 {
                    node.kind = item.kind
                    node.isExplicitSelection = true
                }
                parent = node
            }
        }

        return ordered(rootPaths.compactMap { nodesByPath[$0] }).map {
            makeNode($0, isRoot: true)
        }
    }

    static func paths(in nodes: [PathOutlineNode]) -> [String] {
        nodes.flatMap { node in
            [node.id] + paths(in: node.children ?? [])
        }
    }

    private static func ancestorPaths(for path: String) -> [String] {
        let isHomePath = path.hasPrefix("~/")
        let isAbsolutePath = path.hasPrefix("/")
        let pathWithoutRoot: Substring = if isHomePath {
            path.dropFirst(2)
        } else if isAbsolutePath {
            path.dropFirst()
        } else {
            Substring(path)
        }
        let components = pathWithoutRoot.split(separator: "/").map(String.init)

        var currentPath = isHomePath ? "~" : ""
        return components.map { component in
            if currentPath == "~" {
                currentPath = "~/\(component)"
            } else if currentPath.isEmpty, isAbsolutePath {
                currentPath = "/\(component)"
            } else if currentPath.isEmpty {
                currentPath = component
            } else {
                currentPath += "/\(component)"
            }
            return currentPath
        }
    }

    private static func ordered(_ nodes: [MutableNode]) -> [MutableNode] {
        nodes.sorted {
            if $0.kind != $1.kind {
                return $0.kind == .folder
            }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private static func makeNode(_ node: MutableNode, isRoot: Bool = false) -> PathOutlineNode {
        let children = ordered(Array(node.children.values)).map { makeNode($0) }
        return PathOutlineNode(
            path: node.path,
            title: isRoot ? node.path : pathComponent(in: node.path),
            kind: children.isEmpty ? node.kind : .folder,
            isExplicitSelection: node.isExplicitSelection,
            children: children.isEmpty ? nil : children
        )
    }

    private static func pathComponent(in path: String) -> String {
        String(path.split(separator: "/").last ?? Substring(path))
    }

    private final class MutableNode {
        let path: String
        var kind: SnapshotFile.Kind
        var isExplicitSelection = false
        var children = [String: MutableNode]()

        init(path: String, kind: SnapshotFile.Kind) {
            self.path = path
            self.kind = kind
        }
    }
}
