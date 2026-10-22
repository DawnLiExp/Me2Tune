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
}
