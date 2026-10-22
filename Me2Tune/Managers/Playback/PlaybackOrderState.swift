import Foundation
import Observation

/// The audible history and the planned order are separate: reserving a decoder does not play it.
@MainActor
@Observable
final class PlaybackOrderState {
    struct Selection: Equatable {
        let id: UUID
        let revision: UUID
        var historyEntryID: UUID? = nil
        var consumedIDs: [UUID] = []
        var startsNewRound = false
        var roundIDs: [UUID]? = nil
    }

    private(set) var isShuffling = false
    private(set) var ids: [UUID] = []
    private(set) var currentID: UUID?
    private(set) var requested: Selection?
    // Repeated tracks in different rounds must retain distinct history identities.
    private struct HistoryEntry {
        let id = UUID()
        let trackID: UUID
    }
    private var historyEntries: [HistoryEntry] = []
    var history: [UUID] { historyEntries.map(\.trackID) }
    private var historyIndex: Int?
    private var remaining: [UUID] = []
    private var nextRound: [UUID] = []
    private var revision = UUID()
    @ObservationIgnored private let shuffle: ([UUID]) -> [UUID]

    init(shuffle: @escaping ([UUID]) -> [UUID] = { $0.shuffled() }) {
        self.shuffle = shuffle
    }

    func reset(ids: [UUID], currentID: UUID?, shuffling: Bool) {
        self.ids = ids
        self.currentID = currentID
        isShuffling = shuffling
        revision = UUID()
        requested = nil
        historyEntries = []
        historyIndex = nil
        remaining = shuffle(ids.filter { $0 != currentID })
        nextRound = shuffle(ids)
    }

    func setShuffling(_ enabled: Bool) {
        guard enabled != isShuffling else { return }
        isShuffling = enabled
        revision = UUID()
        remaining = shuffle(ids.filter { $0 != currentID })
        nextRound = shuffle(ids)
        if let pending = requested {
            requested = selectionInCurrentOrder(pending)
            // The in-flight request is the navigation anchor, ahead of the new pending order.
            if enabled, pending.historyEntryID == nil, let index = remaining.firstIndex(of: pending.id) {
                remaining.insert(remaining.remove(at: index), at: 0)
            }
        }
    }

    func reconcile(ids newIDs: [UUID]) {
        let valid = Set(newIDs)
        let previousIDs = Set(ids)
        let added = newIDs.filter { !previousIDs.contains($0) }
        ids = newIDs
        remaining.removeAll { !valid.contains($0) }
        let prefixCount = historyEntries.prefix((historyIndex ?? -1) + 1).filter { valid.contains($0.trackID) }.count
        historyEntries.removeAll { !valid.contains($0.trackID) }
        historyIndex = prefixCount > 0 ? prefixCount - 1 : nil
        if let currentID, !valid.contains(currentID) { self.currentID = nil }
        if let requested, !valid.contains(requested.id) { self.requested = nil }
        for id in added {
            let insertion = shuffle(remaining + [id]).firstIndex(of: id) ?? remaining.count
            remaining.insert(id, at: insertion)
        }
        if !added.isEmpty || Set(nextRound) != valid { nextRound = shuffle(newIDs) }
    }

    func first(failed: Set<UUID>) -> Selection? {
        let candidates = isShuffling ? remaining : ids
        return candidates.first { !failed.contains($0) }.map { Selection(id: $0, revision: revision) }
    }

    func select(_ id: UUID) -> Selection { Selection(id: id, revision: revision) }

    private func selectionInCurrentOrder(_ selection: Selection) -> Selection {
        guard selection.revision != revision else { return selection }
        return Selection(id: selection.id, revision: revision, historyEntryID: selection.historyEntryID)
    }

    private func historyPosition(of selection: Selection?) -> Int? {
        guard let entryID = selection?.historyEntryID else { return nil }
        return historyEntries.firstIndex { $0.id == entryID }
    }

    private func navigationHistoryPosition(automatic: Bool = false) -> Int? {
        // A request without a history identity has already left the history path.
        // Falling back to the audible cursor would replay that path on the next click.
        automatic || requested == nil ? historyIndex : historyPosition(of: requested)
    }

    private func sequentialSelection(_ id: UUID, backwards: Bool, automatic: Bool = false) -> Selection {
        let cursor = navigationHistoryPosition(automatic: automatic)
        let indices: [Int]
        if backwards {
            indices = Array(historyEntries.indices.prefix(cursor ?? historyEntries.count).reversed())
        } else {
            indices = cursor.map { Array(historyEntries.indices.dropFirst($0 + 1)) } ?? []
        }
        // Resolve in the navigation direction, so repeated tracks keep the right instance.
        let entry = indices.first { historyEntries[$0].trackID == id }.map { historyEntries[$0].id }
        return Selection(id: id, revision: revision, historyEntryID: entry)
    }

    func request(_ selection: Selection) { requested = selectionInCurrentOrder(selection) }
    func cancelRequest() { requested = nil }

    func next(repeatMode: RepeatMode, automatic: Bool, failed: Set<UUID>) -> Selection? {
        let anchor = automatic ? currentID : (requested?.id ?? currentID)
        guard let anchor else { return first(failed: failed) }
        if automatic, repeatMode == .one {
            return failed.contains(anchor) ? nil : select(anchor)
        }
        if isShuffling {
            let cursor = navigationHistoryPosition(automatic: automatic)
            if let cursor, cursor + 1 < historyEntries.count,
               let index = ((cursor + 1)..<historyEntries.count).first(where: { !failed.contains(historyEntries[$0].trackID) }) {
                return Selection(id: historyEntries[index].trackID, revision: revision, historyEntryID: historyEntries[index].id)
            }
            let planned = !automatic && requested?.startsNewRound == true ? (requested?.roundIDs ?? nextRound) : remaining
            var candidates = planned
            if !automatic, let requested, requested.historyEntryID == nil {
                if let offset = candidates.firstIndex(of: requested.id) {
                    candidates = Array(candidates.dropFirst(offset + 1))
                }
            }
            if let id = candidates.first(where: { !failed.contains($0) }) {
                return Selection(id: id, revision: revision,
                                 consumedIDs: Array(planned.prefix { $0 != id }) + [id],
                                 startsNewRound: !automatic && requested?.startsNewRound == true,
                                 roundIDs: !automatic ? requested?.roundIDs : nil)
            }
            guard repeatMode == .all else { return nil }
            var round = nextRound.filter { !failed.contains($0) }
            if round.count > 1, round.first == anchor { round.append(round.removeFirst()) }
            return round.first.map { Selection(id: $0, revision: revision, consumedIDs: [$0], startsNewRound: true, roundIDs: round) }
        }
        guard let index = ids.firstIndex(of: anchor) else { return first(failed: failed) }
        let candidates = Array(ids.dropFirst(index + 1)) + (repeatMode == .all ? Array(ids.prefix(index + 1)) : [])
        return candidates.first { !failed.contains($0) }.map { sequentialSelection($0, backwards: false, automatic: automatic) }
    }

    func previous(repeatMode: RepeatMode, failed: Set<UUID>) -> Selection? {
        if isShuffling {
            // A pending forward request has not entered history yet.
            let cursor = historyPosition(of: requested) ?? (requested == nil ? historyIndex : historyEntries.count)
            guard let cursor, cursor > 0,
                  let index = (0..<min(cursor, historyEntries.count)).reversed().first(where: { !failed.contains(historyEntries[$0].trackID) }) else { return nil }
            return Selection(id: historyEntries[index].trackID, revision: revision, historyEntryID: historyEntries[index].id)
        }
        guard let anchor = requested?.id ?? currentID, let index = ids.firstIndex(of: anchor) else { return nil }
        let candidates = Array(ids.prefix(index).reversed()) + (repeatMode == .all ? Array(ids.suffix(from: index).reversed()) : [])
        return candidates.first { !failed.contains($0) }.map { sequentialSelection($0, backwards: true) }
    }

    func confirm(_ selection: Selection) {
        guard ids.contains(selection.id) else { return }
        if let index = historyPosition(of: selection) {
            historyIndex = index
        } else if historyIndex == nil || currentID != selection.id {
            historyEntries = Array(historyEntries.prefix((historyIndex ?? -1) + 1))
            historyEntries.append(HistoryEntry(trackID: selection.id))
            historyIndex = historyEntries.count - 1
        }
        if selection.revision == revision, selection.historyEntryID == nil {
            if selection.startsNewRound {
                let valid = Set(ids)
                remaining = (selection.roundIDs ?? nextRound).filter { valid.contains($0) }
                let present = Set(remaining)
                remaining.append(contentsOf: ids.filter { !present.contains($0) })
                nextRound = shuffle(ids)
            }
            // Consume only the planned prefix; additions made after reservation remain eligible.
            let consumed = Set(selection.consumedIDs + [selection.id])
            remaining.removeAll { consumed.contains($0) }
        } else {
            // A successor submitted before a mode change remains valid, but must not skip the new order.
            remaining.removeAll { $0 == selection.id }
        }
        currentID = selection.id
        requested = nil
    }
}
