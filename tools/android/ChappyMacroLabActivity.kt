package dev.chappy.chappy_player

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Trusted native test fixture. Accessibility is enabled only in Android
 * Settings and only a user-tapped button invokes a fixed demo sequence.
 */
class ChappyMacroLabActivity : Activity() {
    private lateinit var connectionStatus: TextView
    private lateinit var resultStatus: TextView
    private lateinit var editTarget: EditText
    private var tapCount = 0

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(22), dp(18), dp(28))
            setBackgroundColor(Color.rgb(17, 24, 39))
        }
        val scroll = ScrollView(this).apply { addView(content) }
        setContentView(scroll)

        fun label(text: String, size: Float = 16f): TextView =
            TextView(this).apply {
                this.text = text
                textSize = size
                setTextColor(Color.WHITE)
                setPadding(0, dp(8), 0, dp(10))
                content.addView(this)
            }

        label("Chappy Macro Lab — R1", 23f)
        label("実験対象はこの画面だけ。外部アプリの操作・読み取り・自動実行はできません。")
        label("アクセシビリティはAndroid設定から自分でON/OFF。"
                + " この実験では画面内容の保存・通信・監視は行いません。", 14f)
        connectionStatus = label("接続状態を確認中…")
        content.addView(Button(this).apply {
            text = "Androidユーザー補助設定を開く"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        })
        content.addView(Button(this).apply {
            text = "接続状態を更新"
            setOnClickListener { refreshConnection() }
        })

        label("▼ 固定2ステップの実験画面", 18f)
        TextView(this).apply {
            text = "Chappy Macro Lab の検証画面"
            contentDescription = ChappyMacroAccessibilityService.FIXTURE_MARKER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setTextColor(Color.LTGRAY)
            content.addView(this)
        }
        content.addView(Button(this).apply {
            text = "R1 検証用タップ対象"
            contentDescription = ChappyMacroAccessibilityService.TAP_MARKER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setOnClickListener {
                tapCount++
                resultStatus.text = "対象ボタンが押された回数：$tapCount"
            }
        })
        editTarget = EditText(this).apply {
            hint = "R1 入力対象"
            contentDescription = ChappyMacroAccessibilityService.INPUT_MARKER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setSingleLine(true)
        }
        content.addView(editTarget)
        resultStatus = label("実行前：まだマクロは動いていません")
        content.addView(Button(this).apply {
            text = "固定2ステップを実行（本人操作）"
            setOnClickListener {
                val service = ChappyMacroAccessibilityService.active()
                if (service == null) {
                    resultStatus.text = "未接続：Android設定でMacro LabをONにしてください"
                } else {
                    editTarget.setText("")
                    resultStatus.text = "実行中：タップ → 文字入力"
                    service.runFixedFixture { result ->
                        if (!isFinishing && !isDestroyed) resultStatus.text = result
                    }
                }
            }
        })
        content.addView(Button(this).apply {
            text = "緊急停止（いつでも）"
            setOnClickListener {
                ChappyMacroAccessibilityService.active()?.cancel()
                resultStatus.text = "停止しました（続行しません）"
            }
        })
        label("Androidのユーザー補助設定をOFFにすればサービス自体も停止できます。", 13f)
        refreshConnection()
    }

    private fun refreshConnection() {
        connectionStatus.text = if (ChappyMacroAccessibilityService.connected()) {
            "接続：ON（この検証画面のみ操作）"
        } else {
            "接続：OFF（Android設定で本人が有効化）"
        }
    }

    override fun onResume() {
        super.onResume()
        if (::connectionStatus.isInitialized) refreshConnection()
    }

    override fun onPause() {
        ChappyMacroAccessibilityService.active()?.cancel()
        super.onPause()
    }
}
