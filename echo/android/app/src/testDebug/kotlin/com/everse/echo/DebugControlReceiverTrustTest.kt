package com.everse.echo

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// E1：DebugControlReceiver 调用方 uid 白名单纯逻辑测试
/// （交接单 E1 验收——抽纯函数 isCallerTrusted 做 Kotlin 侧 JVM 单测）。
///
/// 信任边界是 root(0)/shell(2000) 两个 uid：前者为 root adb，
/// 后者为 `adb shell` / `am broadcast` 的实际发起 uid。
class DebugControlReceiverTrustTest {

    @Test
    fun rootUidIsTrusted() {
        assertTrue(DebugControlReceiver.isCallerTrusted(DebugControlReceiver.ROOT_UID))
    }

    @Test
    fun shellUidIsTrusted() {
        // 真机 echo-cmd 链路即 uid 2000，误判会直接掐断正常 adb。
        assertTrue(DebugControlReceiver.isCallerTrusted(DebugControlReceiver.SHELL_UID))
        assertTrue(DebugControlReceiver.isCallerTrusted(2000))
    }

    @Test
    fun otherUidsAreRejected() {
        // system(1000)、普通第三方 App（>=10000，含本 App 自身 uid）、
        // 孤立零（root 已单独放行之外的边界值）一律静默拒绝。
        assertFalse(DebugControlReceiver.isCallerTrusted(1000))
        assertFalse(DebugControlReceiver.isCallerTrusted(10001))
        assertFalse(DebugControlReceiver.isCallerTrusted(99999))
        assertFalse(DebugControlReceiver.isCallerTrusted(-1))
    }
}
