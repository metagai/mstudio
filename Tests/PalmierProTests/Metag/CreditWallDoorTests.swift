import Foundation
import Testing
@testable import PalmierPro

/// **撞墙那一刻要留一扇门，不是留一句指路。**
///
/// 30 天真数：撞上额度墙 4 人 → 打开收银台 1 人，**丢掉 75%** ——
/// 这是有真人走过的步骤里转化最差的一格。而那句话原来是
/// 「Not enough credits — top up or subscribe in Settings › Account.」
/// —— 它自己的注释写着「这是转化那一刻，而它原来是个句号」，
/// 然后把句号换成了一句**指路**。
///
/// 指路要他记住一条路径、退出这一屏、自己找过去；
/// 而他此刻手里正有一条刚看完的草案。
@Suite("撞墙那一刻的门")
@MainActor
struct CreditWallDoorTests {

    /// **只有余额不够那一种失败才配一扇充值的门。**
    /// 网络断了给他一个"充值"按钮，是在最糟的时刻要钱。
    @Test func onlyTheCreditWallGetsTheDoor() {
        let m = MetagDraftModel()
        m.noteDoorForTesting(MetagGateway.Failure.insufficientCredits)
        #expect(m.noteDoor == .topUp)

        m.noteDoor = nil
        m.noteDoorForTesting(MetagGateway.Failure.http(500))
        #expect(m.noteDoor == nil, "服务器 500 不是他的问题，别在这时候要钱")

        m.noteDoorForTesting(MetagGateway.Failure.signedOut)
        #expect(m.noteDoor == nil, "没登录该给登录，不是给收银台")
    }

    /// **选对了不等于画出来了。**
    ///
    /// 上面两条测的是"该不该有门"，而他看到的是屏幕。
    /// 同一句话渲两次 —— 有门的那次必须多出东西来。
    /// 比的是两次之间的差，不是一个绝对门槛：
    /// **门槛照非故障态标过一次，今天已经栽过了。**
    @Test func theDoorActuallyLandsOnTheScreen() throws {
        let line = L10n.string("Not enough credits — top up or subscribe in Settings › Account.")
        let without = ViewInk.litPixels(
            try ViewInk.bitmap(of: MetagNoteRow(note: line, door: nil), width: 460))
        let with = ViewInk.litPixels(
            try ViewInk.bitmap(of: MetagNoteRow(note: line, door: .topUp), width: 460))
        #expect(with > without + 200,
                "有门那次只多出 \(with - without) 个像素 —— 那扇门没画出来")
    }

    /// **重试之前要把旧的门收走。**
    /// 上一次撞墙留下的按钮，配着这一次的网络错误，是两句话拼在一起。
    @Test func aRetryClearsTheOldDoor() {
        let m = MetagDraftModel()
        m.noteDoorForTesting(MetagGateway.Failure.insufficientCredits)
        #expect(m.noteDoor == .topUp)
        m.clearNoteForTesting()
        #expect(m.noteDoor == nil)
        #expect(m.note == nil)
    }
}
