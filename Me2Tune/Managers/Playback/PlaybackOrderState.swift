import Foundation
import Observation

/// The audible history and the planned order are separate: reserving a decoder does not play it.
@MainActor
@Observable
final class PlaybackOrderState {
    struct Selection: Equatable {
        let id: UUID
        let revision: UUID
        var historyIndex: Int? = nil
        var startsNewRound = false
        var roundIDs: [UUID]? = nil
    }

    private(set) var isShuffling = false
    private(set) var ids: [UUID] = []
    private(set) var currentID: UUID?
    private(set) var requested: Selection?
    private(set) var history: [UUID] = []
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
        history = []
        historyIndex = nil
        remaining = shuffle(ids.filter { $0 != currentID })
        nextRound = shuffle(ids)
    }

    func setShuffling(_ enabled: Bool) {
        guard enabled != isShuffling else { return }
        let audibleHistory = history
        let audibleIndex = historyIndex
        reset(ids: ids, currentID: currentID, shuffling: enabled)
        history = audibleHistory
        historyIndex = audibleIndex
    }

    func reconcile(ids newIDs: [UUID]) {
        let valid = Set(newIDs)
        let previousIDs = Set(ids)
        let added = newIDs.filter { !previousIDs.contains($0) }
        ids = newIDs
        remaining.removeAll { !valid.contains($0) }
        if var request = requested, let index = request.historyIndex {
            request.historyIndex = history.prefix(index + 1).filter { valid.contains($0) }.count - 1
            requested = request
        }
        let prefixCount = history.prefix((historyIndex ?? -1) + 1).filter { valid.contains($0) }.count
        history.removeAll { !valid.contains($0) }
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

    func request(_ selection: Selection) { requested = selection }
    func cancelRequest() { requested = nil }

    func next(repeatMode: RepeatMode, automatic: Bool, failed: Set<UUID>) -> Selection? {
        let anchor = automatic ? currentID : (requested?.id ?? currentID)
        guard let anchor else { return first(failed: failed) }
        if automatic, repeatMode == .one {
            return failed.contains(anchor) ? nil : select(anchor)
        }
        if isShuffling {
            let cursor = automatic ? historyIndex : (requested?.historyIndex ?? historyIndex)
            if let cursor, cursor + 1 < history.count,
               let index = ((cursor + 1)..<history.count).first(where: { !failed.contains(history[$0]) }) {
                return Selection(id: history[index], revision: revision, historyIndex: index)
            }
            var candidates = remaining
            if !automatic, let requested, requested.historyIndex == nil {
                candidates = requested.startsNewRound ? (requested.roundIDs ?? nextRound) : remaining
                if let offset = candidates.firstIndex(of: requested.id) {
                    candidates = Array(candidates.dropFirst(offset + 1))
                }
            }
            if let id = candidates.first(where: { !failed.contains($0) }) {
                return Selection(id: id, revision: revision,
                                 startsNewRound: !automatic && requested?.startsNewRound == true,
                                 roundIDs: !automatic ? requested?.roundIDs : nil)
            }
            guard repeatMode == .all else { return nil }
            var round = nextRound.filter { !failed.contains($0) }
            if round.count > 1, round.first == anchor { round.append(round.removeFirst()) }
            return round.first.map { Selection(id: $0, revision: revision, startsNewRound: true, roundIDs: round) }
        }
        guard let index = ids.firstIndex(of: anchor) else { return first(failed: failed) }
        let candidates = Array(ids.dropFirst(index + 1)) + (repeatMode == .all ? Array(ids.prefix(index + 1)) : [])
        return candidates.first { !failed.contains($0) }.map { select($0) }
    }

    func previous(repeatMode: RepeatMode, failed: Set<UUID>) -> Selection? {
        if isShuffling {
            // A pending forward request has not entered history yet.
            let cursor = requested?.historyIndex ?? (requested == nil ? historyIndex : history.count)
            guard let cursor, cursor > 0,
                  let index = (0..<min(cursor, history.count)).reversed().first(where: { !failed.contains(history[$0]) }) else { return nil }
            return Selection(id: history[index], revision: revision, historyIndex: index)
        }
        guard let anchor = requested?.id ?? currentID, let index = ids.firstIndex(of: anchor) else { return nil }
        let candidates = Array(ids.prefix(index).reversed()) + (repeatMode == .all ? Array(ids.suffix(from: index).reversed()) : [])
        return candidates.first { !failed.contains($0) }.map { select($0) }
    }

    func confirm(_ selection: Selection) {
        guard ids.contains(selection.id) else { return }
        if selection.revision == revision, let index = selection.historyIndex,
           history.indices.contains(index), history[index] == selection.id {
            historyIndex = index
        } else if historyIndex == nil || currentID != selection.id {
            history = Array(history.prefix((historyIndex ?? -1) + 1))
            history.append(selection.id)
            historyIndex = history.count - 1
        }
        if selection.revision == revision, selection.historyIndex == nil {
            if selection.startsNewRound {
                let valid = Set(ids)
                remaining = (selection.roundIDs ?? nextRound).filter { valid.contains($0) }
                let present = Set(remaining)
                remaining.append(contentsOf: ids.filter { !present.contains($0) })
                nextRound = shuffle(ids)
            }
            if let index = remaining.firstIndex(of: selection.id) {
                remaining.removeFirst(index + 1)
            }
        } else {
            // A successor submitted before a mode change remains valid, but must not skip the new order.
            remaining.removeAll { $0 == selection.id }
        }
        currentID = selection.id
        requested = nil
    }
}
