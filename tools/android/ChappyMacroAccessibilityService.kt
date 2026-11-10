package dev.chappy.chappy_player

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * R1: a deliberately narrow accessibility proof of concept.
 *
 * The service receives events ONLY from its own package and discards all
 * events without inspection. It can run one fixed, user-initiated two-step
 * demo against an identified fixture in ChappyMacroLabActivity only.
 * There is no exported IPC, JS bridge, screenshot, screen text storage,
 * cross-app automation, networking, background trigger or scheduled run.
 */
class ChappyMacroAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile private var instance: ChappyMacroAccessibilityService? = null

        fun connected(): Boolean = instance != null
        fun active(): ChappyMacroAccessibilityService? = instance

        const val FIXTURE_MARKER = "chappy_macro_r1_fixture"
        const val TAP_MARKER = "chappy_macro_r1_target_tap"
        const val INPUT_MARKER = "chappy_macro_r1_target_input"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var epoch = 0

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Defense in depth: Android only delivers events from this app.
        val restricted = serviceInfo
        restricted.packageNames = arrayOf(packageName)
        serviceInfo = restricted
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // R1 never records, reads, or responds to incoming event contents.
    }

    override fun onInterrupt() {
        cancel()
    }

    override fun onDestroy() {
        cancel()
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun cancel() {
        epoch += 1
        handler.removeCallbacksAndMessages(null)
    }

    private fun target(
        root: AccessibilityNodeInfo,
        description: String
    ): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var inspected = 0
        while (queue.isNotEmpty() && inspected++ < 150) {
            val node = queue.removeFirst()
            if (node.packageName?.toString() == packageName &&
                node.contentDescription?.toString() == description) {
                return node
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    private fun fixtureRoot(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        if (root.packageName?.toString() != packageName) return null
        if (target(root, FIXTURE_MARKER) == null) return null
        return root
    }

    fun runFixedFixture(onResult: (String) -> Unit) {
        cancel()
        val operation = epoch
        val root = fixtureRoot()
        if (root == null) {
            onResult("中止：検証画面が前面にありません")
            return
        }
        val button = target(root, TAP_MARKER)
        if (button == null ||
            button.className?.toString() != "android.widget.Button" ||
            !button.isClickable ||
            !button.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            onResult("失敗：検証ボタンを押せませんでした")
            return
        }

        // Inter-step delay leaves time for the dedicated stop button.
        handler.postDelayed({
            if (operation != epoch) return@postDelayed
            val updated = fixtureRoot()
            if (updated == null) {
                onResult("中止：検証画面から離れました")
                return@postDelayed
            }
            val edit = target(updated, INPUT_MARKER)
            if (edit == null ||
                edit.className?.toString() != "android.widget.EditText" ||
                !edit.isEditable) {
                onResult("失敗：検証用入力欄を検出できません")
                return@postDelayed
            }
            val arguments = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    "Macro Lab R1 OK"
                )
            }
            if (edit.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
                onResult("成功：ボタン操作 → 固定文字入力（2ステップ）")
            } else {
                onResult("失敗：入力欄への文字設定が拒否されました")
            }
        }, 650L)
    }
}
