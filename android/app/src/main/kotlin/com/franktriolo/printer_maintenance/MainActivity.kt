package com.franktriolo.printer_maintenance

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Two platform services the Flutter side cannot reach on its own:
 *
 *  * the scheduled digest is an alarm, and Android may defer or kill the app
 *    unless it is exempt from battery optimisation;
 *  * an update is an APK, and only the platform can hand it to the installer.
 */
class MainActivity : FlutterActivity() {
    private val batteryChannelName = "printer_maintenance/battery"
    private val updatesChannelName = "printer_maintenance/updates"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, batteryChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoring())
                    "requestIgnoreBatteryOptimizations" -> result.success(requestIgnore())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, updatesChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "installApk needs a path", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- Battery optimisation -------------------------------------------------

    private fun isIgnoring(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            power.isIgnoringBatteryOptimizations(packageName)
        } else {
            // Before Android 6 there was no per-app optimisation to exempt.
            true
        }

    /** Opens the "allow this app to run in the background" dialog. */
    private fun requestIgnore(): Boolean {
        if (isIgnoring()) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (error: Exception) {
            // Some builds do not offer the per-app dialog; fall back to the
            // list of apps so the user can still get there.
            openBatterySettings()
        }
    }

    private fun openBatterySettings(): Boolean =
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (error: Exception) {
            false
        }

    // --- Updates --------------------------------------------------------------

    /** Whether this app may launch the package installer at all. */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** The "install unknown apps" switch for PrintTender itself. */
    private fun openInstallSettings(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                )
                true
            } catch (error: Exception) {
                false
            }
        } else {
            // Not a per-app setting before Android 8.
            false
        }

    /**
     * Hands the downloaded APK to the system installer. Android always asks the
     * user to confirm the update; a sideloaded app cannot install silently.
     */
    private fun installApk(path: String): Boolean =
        try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            val intent =
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            startActivity(intent)
            true
        } catch (error: Exception) {
            false
        }
}
