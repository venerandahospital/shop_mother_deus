package com.veneranda.shop

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.veneranda.shop/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMotherApiForeground" -> {
                        try {
                            MotherApiForegroundService.start(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FG_SERVICE", e.message, null)
                        }
                    }
                    "stopMotherApiForeground" -> {
                        try {
                            MotherApiForegroundService.stop(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FG_SERVICE", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
