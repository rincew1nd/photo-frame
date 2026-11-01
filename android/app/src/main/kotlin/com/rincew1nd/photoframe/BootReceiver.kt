package com.rincew1nd.photoframe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }
        val enabled = context.getSharedPreferences("photo_frame", Context.MODE_PRIVATE)
            .getBoolean("start_on_boot", false)
        if (!enabled) {
            return
        }
        val launch = Intent(context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launch)
    }
}
