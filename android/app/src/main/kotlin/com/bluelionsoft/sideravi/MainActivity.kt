package com.bluelionsoft.sideravi

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var diagnostics: SensorDiagnostics

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        diagnostics = SensorDiagnostics(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sidera_vi/sensor_diagnostics")
            .setMethodCallHandler(diagnostics::handle)
    }

    override fun onResume() {
        super.onResume()
        if (::diagnostics.isInitialized) diagnostics.resume()
    }

    override fun onPause() {
        if (::diagnostics.isInitialized) diagnostics.suspend()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::diagnostics.isInitialized) diagnostics.permissionsReturned(requestCode)
    }

    @Deprecated("Handles the existing Flutter Activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::diagnostics.isInitialized) diagnostics.documentReturned(requestCode, resultCode, data)
    }
}
