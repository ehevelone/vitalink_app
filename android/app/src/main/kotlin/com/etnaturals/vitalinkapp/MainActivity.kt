package com.etnaturals.vitalinkapp

import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val calendarChannel = "com.etnaturals.vitalinkapp/calendar"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            calendarChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "insertEvent") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val title = call.argument<String>("title") ?: "VitaLink Appointment"
            val description = call.argument<String>("description") ?: ""
            val startMillis = call.argument<Long>("startMillis")
            val endMillis = call.argument<Long>("endMillis")

            if (startMillis == null || endMillis == null) {
                result.success(false)
                return@setMethodCallHandler
            }

            val intent = Intent(Intent.ACTION_INSERT).apply {
                data = CalendarContract.Events.CONTENT_URI
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.Events.DESCRIPTION, description)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMillis)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis)
            }

            try {
                startActivity(intent)
                result.success(true)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }
}
