package dev.chappy.chappy_player

import android.content.Context

/**
 * Host-only recording confirmation setting. A mini-app never receives a path
 * to this preference and cannot opt out through video.start options.
 *
 * Flutter must require an explicit user confirmation before changing the
 * default askEveryTime=true to false.
 */
internal object RecorderConfirmationPreferences {
    private const val FILE = "chappy_recorder_host"
    private const val KEY = "ask_every_time"

    fun askEveryTime(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY, true)

    fun save(context: Context, askEveryTime: Boolean): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, askEveryTime).commit()
}
