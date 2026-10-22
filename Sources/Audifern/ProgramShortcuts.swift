import Foundation

/// Only matching, named slots can be switched together. A shortcut preference
/// never changes a hearing aid, and is scoped to this exact device selection.
struct ProgramShortcutCatalog {
    struct Program: Identifiable, Equatable {
        let id: Int
        let name: String
    }
    let aids: [AidConnection]
    var scope: String { aids.map { $0.id.uuidString }.sorted().joined(separator: ":") }
    var programs: [Program] {
        guard let first = aids.first else { return [] }
        return Array(Set(first.programIDs)).sorted().compactMap { id in
            guard let name = first.programNames[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  aids.allSatisfy({ $0.programIDs.contains(id) && $0.programNames[id] == name }) else { return nil }
            return .init(id: id, name: name)
        }
    }
    var activeID: Int? {
        guard let first = aids.first, let active = first.activeProgram,
              aids.allSatisfy({ $0.activeProgram == active }) else { return nil }
        return active
    }
    func visible(saved: [Int]?) -> [Program] {
        guard let saved else { return programs }
        let included = programs.filter { saved.contains($0.id) }
        // Never write a temporary discovery/connection inventory into defaults.
        // If fitting removed every saved slot, retain one valid local choice.
        if !included.isEmpty { return included }
        return [programs.first { $0.id == activeID } ?? programs.first].compactMap { $0 }
    }
    func selection(changing id: Int, included: Bool, saved: [Int]?) -> [Int]? {
        guard programs.contains(where: { $0.id == id }) else { return nil }
        var ids = Set(visible(saved: saved).map(\.id))
        if included { ids.insert(id) } else { ids.remove(id) }
        return ids.isEmpty ? nil : ids.sorted()
    }
}
