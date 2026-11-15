package com.bluelionsoft.sideravi

import android.Manifest.permission.ACCESS_COARSE_LOCATION
import android.Manifest.permission.ACCESS_FINE_LOCATION
import android.Manifest.permission.ACTIVITY_RECOGNITION
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import android.widget.Toast
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.math.sqrt

/** Gives Flutter the same bounded foreground snapshots used on iOS. */
internal class SensorDiagnostics(private val activity: Activity) :
    SensorEventListener, LocationListener {
    private val sensors = activity.getSystemService(SensorManager::class.java)
    private val location = activity.getSystemService(LocationManager::class.java)
    private val prefs = activity.getSharedPreferences("sidera_local", Context.MODE_PRIVATE)
    private val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyro = sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val magnetometer = sensors.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
    private val rotation = sensors.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        ?: sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val stepSensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        ?: sensors.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
    private val compassPossible = accelerometer != null && magnetometer != null
    private val orientations = mutableListOf<Map<String, Any>>()
    private val fixes = mutableListOf<Map<String, Any>>()
    private val stepSamples = mutableListOf<Map<String, Any>>()
    private var wantsMotion = false
    private var wantsLocation = false
    private var wantsSteps = false
    private var foreground = false
    private var motionActive = false
    private var locationActive = false
    private var stepsActive = false
    private var permissionRequest = 0
    private var lastOrientation = 0L
    private var angularRate: Double? = null
    private var batch = 0
    private var generation = 0
    private var stepEpoch = 0.0
    private var stepStartedAt = 0L
    private var steps = StepWindow()
    private var export: String? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start", "startMotion", "startLocation" -> {
                if (!foreground) {
                    result.error("background", "Open SIDERA VI to use device sensors.", null)
                    return
                }
                if (call.method != "startLocation") {
                    wantsMotion = true
                    orientations.clear()
                }
                if (call.method != "startMotion") {
                    wantsLocation = true
                    wantsSteps = call.method == "startLocation"
                    fixes.clear()
                }
                refresh()
                if (call.method != "startMotion") requestLocationOrSteps()
                result.success(null)
            }
            "stop" -> {
                wantsMotion = false
                wantsLocation = false
                wantsSteps = false
                suspendStreams()
                result.success(null)
            }
            "stopLocation" -> {
                wantsLocation = false
                wantsSteps = false
                stopLocation()
                stopSteps()
                result.success(null)
            }
            "reset", "clearMotion" -> {
                orientations.clear()
                if (call.method == "reset") fixes.clear()
                result.success(null)
            }
            "restartPedometer" -> {
                if (wantsSteps) {
                    stopSteps()
                    refresh()
                }
                result.success(null)
            }
            "finishPedometerCapture" -> result.success(null)
            "snapshot" -> result.success(snapshot())
            "export", "exportMovement" -> exportReport(call, result)
            "readMissionChecklist" -> {
                val key = checklistKey(call.arguments as? String, result) ?: return
                result.success(prefs.getStringSet(key, emptySet())!!.sorted())
            }
            "writeMissionChecklist" -> {
                val key = checklistKey(call.argument<String>("scope"), result) ?: return
                val completed = call.argument<List<String>>("completed") ?: emptyList()
                prefs.edit().putStringSet(key, completed.toSet()).apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun checklistKey(scope: String?, result: MethodChannel.Result): String? {
        if (scope != null && scope.matches(Regex("[A-Za-z0-9:/-]{1,90}"))) {
            return "checklist/$scope"
        }
        result.error("invalid_checklist", "Mission checklist is unavailable.", null)
        return null
    }

    fun resume() {
        foreground = true
        refresh()
    }

    fun suspend() {
        foreground = false
        suspendStreams()
    }

    private fun suspendStreams() {
        sensors.unregisterListener(this)
        motionActive = false
        lastOrientation = 0L
        angularRate = null
        orientations.clear()
        stopLocation()
        stopSteps()
    }

    private fun granted(permission: String) =
        activity.checkSelfPermission(permission) == PERMISSION_GRANTED

    private val locationGranted: Boolean
        get() = granted(ACCESS_FINE_LOCATION) || granted(ACCESS_COARSE_LOCATION)
    private val stepsGranted: Boolean
        get() = Build.VERSION.SDK_INT < 29 || granted(ACTIVITY_RECOGNITION)

    private fun requestLocationOrSteps() {
        if (!foreground || permissionRequest != 0) return
        if (wantsLocation && !locationGranted &&
            (!prefs.getBoolean("askedLocation", false) ||
                activity.shouldShowRequestPermissionRationale(ACCESS_COARSE_LOCATION))) {
            permissionRequest = locationPermission
            prefs.edit().putBoolean("askedLocation", true).apply()
            activity.requestPermissions(
                arrayOf(ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION), locationPermission
            )
        } else {
            requestSteps()
        }
    }

    private fun requestSteps() {
        if (Build.VERSION.SDK_INT >= 29 && wantsSteps && stepSensor != null && !stepsGranted &&
            permissionRequest == 0 && (!prefs.getBoolean("askedSteps", false) ||
                activity.shouldShowRequestPermissionRationale(ACTIVITY_RECOGNITION))) {
            permissionRequest = stepPermission
            prefs.edit().putBoolean("askedSteps", true).apply()
            activity.requestPermissions(arrayOf(ACTIVITY_RECOGNITION), stepPermission)
        }
    }

    fun permissionsReturned(code: Int) {
        if (code != permissionRequest) return
        permissionRequest = 0
        refresh()
        if (code == locationPermission) requestSteps()
    }

    @SuppressLint("MissingPermission")
    private fun refresh() {
        if (!foreground) return
        if (wantsMotion && !motionActive && rotation != null) {
            motionActive = sensors.registerListener(this, rotation, 100_000)
            if (motionActive && gyro != null) sensors.registerListener(this, gyro, 100_000)
        }
        if (wantsLocation && !locationActive && locationGranted) {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            for (provider in providers) {
                if (!location.allProviders.contains(provider)) continue
                try {
                    location.requestLocationUpdates(provider, 1_000, 0f, this, Looper.getMainLooper())
                    locationActive = true
                } catch (_: SecurityException) {
                    // An approximate grant can exclude a provider.
                } catch (_: IllegalArgumentException) {
                    // A provider can disappear while the OS is changing settings.
                }
            }
        }
        if (wantsSteps && !stepsActive && stepsGranted && stepSensor != null) {
            stepStartedAt = SystemClock.elapsedRealtimeNanos()
            stepEpoch = System.currentTimeMillis() / 1000.0
            steps = StepWindow()
            generation++
            stepsActive = sensors.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    private fun stopLocation() {
        if (locationActive) location.removeUpdates(this)
        locationActive = false
        fixes.clear()
    }

    private fun stopSteps() {
        if (stepsActive && stepSensor != null) sensors.unregisterListener(this, stepSensor)
        stepsActive = false
        stepSamples.clear()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (!foreground) return
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                val (x, y, z) = event.values
                angularRate = Math.toDegrees(sqrt(x * x + y * y + z * z).toDouble())
            }
            Sensor.TYPE_STEP_COUNTER, Sensor.TYPE_STEP_DETECTOR -> recordSteps(event)
            Sensor.TYPE_GAME_ROTATION_VECTOR, Sensor.TYPE_ROTATION_VECTOR -> recordAttitude(event)
        }
    }

    @Suppress("DEPRECATION")
    private fun recordAttitude(event: SensorEvent) {
        if (!motionActive || event.timestamp - lastOrientation < 85_000_000L) return
        lastOrientation = event.timestamp
        val matrix = FloatArray(9)
        val screen = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        val orientation = activity.windowManager.defaultDisplay.rotation
        val (x, y, frame) = when (orientation) {
            Surface.ROTATION_90 -> Triple(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X, "Landscape left")
            Surface.ROTATION_180 -> Triple(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y, "Portrait upside down")
            Surface.ROTATION_270 -> Triple(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X, "Landscape right")
            else -> Triple(SensorManager.AXIS_X, SensorManager.AXIS_Y, "Portrait")
        }
        if (!SensorManager.remapCoordinateSystem(matrix, x, y, screen)) return
        val attitude = SensorManager.getOrientation(screen, FloatArray(3))
        val sample = mutableMapOf<String, Any>(
            "time" to wallTime(event.timestamp),
            "received" to System.currentTimeMillis() / 1000.0,
            "frame" to frame,
            "pitch" to Math.toDegrees(attitude[1].toDouble()),
            "roll" to Math.toDegrees(attitude[2].toDouble()),
        )
        val east = screen[1].toDouble()
        val north = screen[4].toDouble()
        screenTopAzimuth(east, north)?.let { sample["yaw"] = it }
        angularRate?.let { sample["rotationRate"] = it }
        append(orientations, sample, 48)
    }

    private fun recordSteps(event: SensorEvent) {
        if (!stepsActive || event.timestamp < stepStartedAt || !event.values[0].isFinite()) return
        val total = if (event.sensor.type == Sensor.TYPE_STEP_COUNTER) {
            steps.counter(event.values[0].toInt())
        } else {
            steps.detectedStep()
        }
        append(
            stepSamples, mapOf(
                "start" to stepEpoch, "end" to wallTime(event.timestamp).coerceAtLeast(stepEpoch),
                "received" to System.currentTimeMillis() / 1000.0, "steps" to total,
            ), 48
        )
    }

    override fun onLocationChanged(fix: Location) {
        if (!foreground || !wantsLocation || !fix.hasAccuracy()) return
        val sample = mutableMapOf<String, Any>(
            "latitude" to fix.latitude, "longitude" to fix.longitude,
            "accuracy" to fix.accuracy.toDouble(), "time" to fix.time / 1000.0,
            "received" to System.currentTimeMillis() / 1000.0, "callbackBatch" to ++batch,
            "simulatedBySoftware" to if (Build.VERSION.SDK_INT >= 31) fix.isMock
                else @Suppress("DEPRECATION") fix.isFromMockProvider,
        )
        if (fix.hasSpeed()) sample["speed"] = fix.speed.toDouble()
        if (fix.hasBearing()) sample["course"] = fix.bearing.toDouble()
        if (Build.VERSION.SDK_INT >= 26) {
            if (fix.hasSpeedAccuracy()) sample["speedAccuracy"] = fix.speedAccuracyMetersPerSecond.toDouble()
            if (fix.hasBearingAccuracy()) sample["courseAccuracy"] = fix.bearingAccuracyDegrees.toDouble()
        }
        append(fixes, sample, 64)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    override fun onProviderEnabled(provider: String) = Unit
    override fun onProviderDisabled(provider: String) = Unit
    @Deprecated("Older Android LocationListener compatibility")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    private fun snapshot(): Map<String, Any> {
        val stepAuth = when {
            stepSensor == null -> "unsupported"
            stepsGranted -> "authorized"
            prefs.getBoolean("askedSteps", false) -> "denied"
            else -> "notDetermined"
        }
        val steps = mutableMapOf<String, Any>(
            "stepCounting" to (stepSensor != null), "distance" to false, "cadence" to false,
            "authorization" to stepAuth, "stream" to generation,
            "samples" to drain(stepSamples),
        )
        if (stepsActive) steps["started"] = stepEpoch
        val services = if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled
            else location.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        return mapOf(
            "model" to Build.MODEL, "os" to "Android ${Build.VERSION.RELEASE}",
            "accelerometer" to (accelerometer != null), "gyro" to (gyro != null),
            "magnetometer" to (magnetometer != null), "motion" to (rotation != null),
            "compass" to compassPossible, "services" to services,
            "authorization" to when {
                locationGranted -> "Authorized"
                prefs.getBoolean("askedLocation", false) -> "Denied"
                else -> "Not determined"
            },
            "precise" to granted(ACCESS_FINE_LOCATION), "locations" to drain(fixes),
            "orientations" to drain(orientations), "stepCounting" to (stepSensor != null),
            "pedometerDistance" to false, "pedometerAuthorization" to when (stepAuth) {
                "authorized" -> 3
                "denied" -> 2
                else -> 0
            }, "pedometer" to steps,
        )
    }

    private fun wallTime(timestampNs: Long): Double =
        System.currentTimeMillis() / 1000.0 - (SystemClock.elapsedRealtimeNanos() - timestampNs) / 1e9

    private fun <T> append(queue: MutableList<T>, sample: T, limit: Int) {
        if (queue.size == limit) queue.removeAt(0)
        queue.add(sample)
    }

    private fun <T> drain(queue: MutableList<T>) = queue.toList().also { queue.clear() }

    @Suppress("DEPRECATION")
    private fun exportReport(call: MethodCall, result: MethodChannel.Result) {
        val json = call.arguments as? String
        if (json == null || export != null) {
            result.error("export_unavailable", "Report export is unavailable.", null)
            return
        }
        val kind = if (call.method == "exportMovement") "movement" else "sensor"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, "sidera-$kind-report-${UUID.randomUUID()}.json")
        }
        try {
            export = json
            activity.startActivityForResult(intent, saveReport)
            result.success(null)
        } catch (_: android.content.ActivityNotFoundException) {
            export = null
            result.error("export_unavailable", "The file picker is unavailable.", null)
        }
    }

    fun documentReturned(code: Int, result: Int, data: Intent?) {
        if (code != saveReport) return
        val json = export
        export = null
        val uri = data?.data
        if (result != Activity.RESULT_OK || uri == null || json == null) return
        Thread {
            try {
                val stream = checkNotNull(activity.contentResolver.openOutputStream(uri))
                stream.bufferedWriter().use { it.write(json) }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    Toast.makeText(activity, "Could not save the report.", Toast.LENGTH_SHORT).show()
                }
            }
        }.start()
    }

    private companion object {
        const val locationPermission = 6101
        const val stepPermission = 6102
        const val saveReport = 6103
    }
}
