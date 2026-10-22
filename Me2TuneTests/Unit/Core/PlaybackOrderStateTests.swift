import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("随机播放顺序")
struct PlaybackOrderStateTests {
    private func setup(_ count: Int = 4) -> (PlaybackOrderState, [UUID]) {
        let ids = (0..<count).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { Array($0.reversed()) })
        order.reset(ids: ids, currentID: ids.first, shuffling: true)
        if let first = ids.first { order.confirm(order.select(first)) }
        return (order, ids)
    }

    @Test("每轮不重不漏，查询下一首不消耗顺序")
    func entireRound() throws {
        let (order, ids) = setup()
        var played = [ids[0]]
        while let next = order.next(repeatMode: .off, automatic: true, failed: []) {
            #expect(next == order.next(repeatMode: .off, automatic: true, failed: []))
            played.append(next.id)
            order.confirm(next)
        }
        #expect(played == [ids[0], ids[3], ids[2], ids[1]])
        #expect(Set(played) == Set(ids))
        #expect(order.history == played)
    }

    @Test("回退沿历史前进，失败曲目不进入历史")
    func history() throws {
        let (order, ids) = setup()
        let next = try #require(order.next(repeatMode: .off, automatic: false, failed: [ids[3]]))
        order.request(next)
        #expect(order.history == [ids[0]])
        order.confirm(next)
        let previous = try #require(order.previous(repeatMode: .off, failed: []))
        order.confirm(previous)
        #expect(order.currentID == ids[0])
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[2])
        #expect(order.previous(repeatMode: .all, failed: []) == nil)
    }

    @Test("连续请求前进但只记录实际开始的曲目")
    func rapidNext() throws {
        let (order, ids) = setup()
        order.request(try #require(order.next(repeatMode: .off, automatic: false, failed: [])))
        let second = try #require(order.next(repeatMode: .off, automatic: false, failed: []))
        #expect(second.id == ids[2])
        order.request(second)
        order.confirm(second)
        #expect(order.history == [ids[0], ids[2]])
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[1])
    }

    @Test("单曲循环只影响自动续播，前进到末尾不会手动循环")
    func repeatOne() throws {
        let (order, ids) = setup(2)
        #expect(order.next(repeatMode: .one, automatic: true, failed: [])?.id == ids[0])
        let next = try #require(order.next(repeatMode: .one, automatic: false, failed: []))
        #expect(next.id == ids[1])
        order.confirm(next)
        #expect(order.next(repeatMode: .one, automatic: false, failed: []) == nil)
        #expect(order.next(repeatMode: .one, automatic: true, failed: [ids[1]]) == nil)
    }

    @Test("跨轮不连续重复，过滤损坏曲目后仍不重不漏")
    func repeatedRounds() throws {
        let (order, ids) = setup()
        let failed: Set<UUID> = [ids[2]]
        for _ in 0..<2 {
            order.confirm(try #require(order.next(repeatMode: .off, automatic: true, failed: failed)))
        }
        for _ in 0..<4 {
            let last = order.currentID
            var played: [UUID] = []
            for _ in 0..<3 {
                let next = try #require(order.next(repeatMode: .all, automatic: true, failed: failed))
                #expect(next.id != order.currentID)
                order.confirm(next)
                played.append(next.id)
            }
            #expect(played.first != last)
            #expect(Set(played) == Set(ids).subtracting(failed))
        }
    }

    @Test("模式切换保留的后继仅从新一轮移除自身")
    func retainedSuccessor() throws {
        let (order, ids) = setup()
        let reserved = try #require(order.next(repeatMode: .off, automatic: true, failed: []))
        order.setShuffling(false)
        order.setShuffling(true)
        order.confirm(reserved)
        #expect(order.currentID == ids[3])
        var rest: [UUID] = []
        while let next = order.next(repeatMode: .off, automatic: true, failed: []) {
            rest.append(next.id)
            order.confirm(next)
        }
        #expect(Set(rest) == Set([ids[1], ids[2]]))
    }

    @Test("新增和删除协调顺序，排序不改变随机剩余部分")
    func mutations() throws {
        let (order, ids) = setup()
        let before = order.next(repeatMode: .off, automatic: true, failed: [])
        order.reconcile(ids: Array(ids.reversed()))
        #expect(order.next(repeatMode: .off, automatic: true, failed: []) == before)
        let added = UUID()
        order.reconcile(ids: [ids[0], ids[1], ids[2], added])
        var rest: [UUID] = []
        while let next = order.next(repeatMode: .off, automatic: true, failed: []) {
            rest.append(next.id)
            order.confirm(next)
        }
        #expect(Set(rest) == Set([ids[1], ids[2], added]))
    }

    @Test("顺序播放边界、循环回绕与失败跳过")
    func sequentialNavigation() throws {
        let (order, ids) = setup(3)
        order.setShuffling(false)
        #expect(order.previous(repeatMode: .off, failed: []) == nil)
        #expect(order.previous(repeatMode: .all, failed: [ids[2]])?.id == ids[1])
        #expect(order.next(repeatMode: .one, automatic: false, failed: [ids[1]])?.id == ids[2])
        order.confirm(order.select(ids[2]))
        #expect(order.next(repeatMode: .off, automatic: false, failed: []) == nil)
        #expect(order.next(repeatMode: .all, automatic: false, failed: [])?.id == ids[0])
    }

    @Test("删除历史后连续回退的请求仍有效")
    func deleteHistoryDuringRequest() throws {
        let (order, ids) = setup(4)
        for _ in 0..<3 { order.confirm(try #require(order.next(repeatMode: .off, automatic: false, failed: []))) }
        order.request(try #require(order.previous(repeatMode: .off, failed: [])))
        order.reconcile(ids: Array(ids.dropFirst()))
        #expect(order.previous(repeatMode: .off, failed: [])?.id == ids[3])
    }

    @Test("空列表和单曲边界")
    func boundaries() throws {
        let (empty, _) = setup(0)
        #expect(empty.next(repeatMode: .all, automatic: true, failed: []) == nil)
        let (one, ids) = setup(1)
        #expect(one.next(repeatMode: .off, automatic: true, failed: []) == nil)
        #expect(one.next(repeatMode: .all, automatic: true, failed: [])?.id == ids[0])
        #expect(one.previous(repeatMode: .all, failed: []) == nil)
    }

    @Test("关闭随机后使用最新原列表，来源重建清除旧历史")
    func sourceAndMode() throws {
        let (order, ids) = setup()
        order.reconcile(ids: [ids[3], ids[0], ids[2], ids[1]])
        order.setShuffling(false)
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[2])
        let other = UUID()
        order.reset(ids: [other], currentID: other, shuffling: true)
        #expect(order.history.isEmpty)
        #expect(order.next(repeatMode: .off, automatic: true, failed: []) == nil)
    }

    @Test("加载中的选择跨随机切换保留锚点，旧确认不跳过新顺序")
    func pendingSelectionSurvivesModeChange() throws {
        let (order, ids) = setup()
        order.setShuffling(false)
        let pending = try #require(order.next(repeatMode: .off, automatic: false, failed: []))
        order.request(pending)
        order.setShuffling(true)
        // The load task may start after the mode changed, carrying its original selection.
        order.request(pending)
        #expect(order.requested?.id == ids[1])
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[3])
        order.confirm(pending)
        var rest: [UUID] = []
        while let next = order.next(repeatMode: .off, automatic: true, failed: []) {
            rest.append(next.id)
            order.confirm(next)
        }
        #expect(rest == [ids[3], ids[2]])
        #expect(order.history == [ids[0], ids[1], ids[3], ids[2]])
    }

    @Test("删除历史及切换模式不改变已选历史实例", arguments: [1, 2], [false, true])
    func pendingHistorySurvivesDeletion(rounds: Int, changeMode: Bool) throws {
        let ids = (0..<4).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: true)
        order.confirm(order.select(ids[0]))
        for _ in 1..<(4 * rounds) {
            order.confirm(try #require(order.next(repeatMode: .all, automatic: true, failed: [])))
        }
        let history = order.history
        let pending = try #require(order.previous(repeatMode: .off, failed: []))
        order.request(pending)
        if changeMode {
            order.setShuffling(false)
            order.setShuffling(true)
        }
        order.reconcile(ids: ids.filter { $0 != ids[1] })
        // The loader still holds this original value, including its old revision.
        order.confirm(pending)
        #expect(order.history == history.filter { $0 != ids[1] })
        #expect(order.currentID == ids[2])
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[3])
        #expect(order.previous(repeatMode: .off, failed: [])?.id == ids[0])
    }

    @Test("已预定后继前新增曲目不会被漏播，含跨轮预定", arguments: [false, true])
    func insertionBeforeReservedSuccessor(startsNewRound: Bool) throws {
        let (order, ids) = setup()
        if startsNewRound {
            for _ in 0..<3 {
                order.confirm(try #require(order.next(repeatMode: .off, automatic: true, failed: [])))
            }
        }
        let reserved = try #require(order.next(repeatMode: .all, automatic: true, failed: []))
        let added = UUID()
        order.reconcile(ids: ids + [added])
        order.confirm(reserved)
        var rest: [UUID] = []
        while let next = order.next(repeatMode: .off, automatic: true, failed: []) {
            rest.append(next.id)
            order.confirm(next)
        }
        let expected = Set(ids + [added]).subtracting(startsNewRound ? [reserved.id] : [ids[0], reserved.id])
        #expect(Set(rest) == expected)
        #expect(rest.count == expected.count)
    }

    @Test("顺序回退跨模式切换保留历史位置，连续反向操作沿原路径", arguments: [RepeatMode.off, .all, .one], [false, true])
    func sequentialBackAcrossModes(mode: RepeatMode, confirmIntermediate: Bool) throws {
        let ids = (0..<6).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: false)
        for id in ids.prefix(4) { order.confirm(order.select(id)) }
        let originalHistory = order.history
        func move(back: Bool, to index: Int) throws {
            let selected = try #require(back ? order.previous(repeatMode: mode, failed: [])
                : order.next(repeatMode: mode, automatic: false, failed: []))
            #expect(selected.id == ids[index])
            order.request(selected)
            if confirmIntermediate { order.confirm(selected) }
        }
        try move(back: true, to: 2)
        order.setShuffling(true)
        try move(back: true, to: 1)
        order.setShuffling(false)
        try move(back: true, to: 0)
        order.setShuffling(true)
        for index in 1...3 { try move(back: false, to: index) }
        try move(back: true, to: 2)
        if let pending = order.requested { order.confirm(pending) }
        #expect(order.currentID == ids[2])
        #expect(order.history == originalHistory)
        #expect(order.next(repeatMode: mode, automatic: false, failed: [])?.id == ids[3])
    }

    @Test("连续前进越过历史后保持待播位置，反向只回到已播放历史", arguments: [RepeatMode.off, .all, .one], [false, true])
    func rapidNextAcrossHistoryFrontier(mode: RepeatMode, reverseBeforeConfirm: Bool) throws {
        let ids = (0..<6).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: true)
        order.confirm(order.select(ids[0]))
        for _ in 0..<3 { order.confirm(try #require(order.next(repeatMode: mode, automatic: false, failed: []))) }
        for _ in 0..<2 { order.confirm(try #require(order.previous(repeatMode: mode, failed: []))) }
        for index in 2...5 {
            let next = try #require(order.next(repeatMode: mode, automatic: false, failed: []))
            #expect(next.id == ids[index])
            #expect(order.next(repeatMode: mode, automatic: false, failed: []) == next)
            order.request(next)
        }
        #expect(order.currentID == ids[1])
        #expect(order.history == Array(ids.prefix(4)))
        if reverseBeforeConfirm {
            for index in [3, 2] {
                let back = try #require(order.previous(repeatMode: mode, failed: []))
                #expect(back.id == ids[index])
                order.request(back)
            }
            for index in 3...5 {
                let next = try #require(order.next(repeatMode: mode, automatic: false, failed: []))
                #expect(next.id == ids[index])
                order.request(next)
            }
        }
        order.confirm(try #require(order.requested))
        #expect(order.history == [ids[0], ids[1], ids[5]])
        #expect(order.next(repeatMode: .off, automatic: false, failed: []) == nil)
        #expect(order.previous(repeatMode: mode, failed: [])?.id == ids[1])
    }

    @Test("重复轮次中的顺序导航匹配最近的历史实例", arguments: [false, true])
    func sequentialHistoryInstances(confirmBeforeToggle: Bool) throws {
        let ids = (0..<4).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: false)
        order.confirm(order.select(ids[0]))
        for _ in 0..<7 { order.confirm(try #require(order.next(repeatMode: .all, automatic: false, failed: []))) }
        let history = order.history
        let back = try #require(order.previous(repeatMode: .all, failed: []))
        order.request(back)
        if confirmBeforeToggle { order.confirm(back) }
        order.setShuffling(true)
        for index in [1, 0, 3, 2, 1, 0] {
            let previous = try #require(order.previous(repeatMode: .all, failed: []))
            #expect(previous.id == ids[index])
            order.request(previous)
        }
        #expect(order.previous(repeatMode: .all, failed: []) == nil)
        order.confirm(try #require(order.requested))
        #expect(order.history == history)
        for id in history.dropFirst() {
            let next = try #require(order.next(repeatMode: .off, automatic: false, failed: []))
            #expect(next.id == id)
            order.confirm(next)
        }
        #expect(order.history == history)
    }

    @Test("历史外的顺序请求切回随机后不能复用旧历史游标")
    func sequentialRequestOutsideHistory() throws {
        let ids = (0..<6).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: false)
        for id in ids.prefix(4) { order.confirm(order.select(id)) }
        order.confirm(try #require(order.previous(repeatMode: .off, failed: []))) // C
        order.confirm(try #require(order.previous(repeatMode: .off, failed: []))) // B
        for index in 2...4 {
            let next = try #require(order.next(repeatMode: .off, automatic: false, failed: []))
            #expect(next.id == ids[index])
            order.request(next)
        }
        order.setShuffling(true) // E is retained ahead of the new round A C D F.
        #expect(order.next(repeatMode: .off, automatic: false, failed: [])?.id == ids[0])
        #expect(order.previous(repeatMode: .off, failed: [])?.id == ids[3])
        #expect(order.next(repeatMode: .one, automatic: true, failed: [])?.id == ids[1])
    }

    @Test("顺序回退跨模式及历史删除后，旧请求仍指向同一实例")
    func sequentialBackWithDeletionAndFailures() throws {
        let ids = (0..<6).map { _ in UUID() }
        let order = PlaybackOrderState(shuffle: { $0 })
        order.reset(ids: ids, currentID: ids[0], shuffling: false)
        for id in ids.prefix(5) { order.confirm(order.select(id)) }
        let back = try #require(order.previous(repeatMode: .off, failed: [ids[3]]))
        #expect(back.id == ids[2])
        order.request(back)
        order.setShuffling(true)
        order.reconcile(ids: Array(ids.dropFirst()))
        order.request(back) // A delayed load task still holds the old mode revision.
        #expect(order.previous(repeatMode: .off, failed: [])?.id == ids[1])
        order.confirm(back)
        #expect(order.history == Array(ids[1...4]))
        #expect(order.next(repeatMode: .off, automatic: false, failed: [ids[3]])?.id == ids[4])
    }

}
