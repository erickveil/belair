package net.erickveil.belair

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"belair/android_downloads"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"saveToDownloads" -> {
					val sourcePath = call.argument<String>("sourcePath")
					val displayName = call.argument<String>("displayName")
					val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

					if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
						result.error("invalid_args", "sourcePath and displayName are required.", null)
						return@setMethodCallHandler
					}

					try {
						result.success(saveToDownloads(sourcePath, displayName, mimeType))
					} catch (error: Exception) {
						result.error("save_failed", error.message, null)
					}
				}

				else -> result.notImplemented()
			}
		}
	}

	@Throws(IOException::class)
	private fun saveToDownloads(sourcePath: String, displayName: String, mimeType: String): String {
		val sourceFile = File(sourcePath)
		if (!sourceFile.exists()) {
			throw IOException("Source file does not exist.")
		}

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			val resolver = applicationContext.contentResolver
			val values = ContentValues().apply {
				put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
				put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
				put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
				put(MediaStore.MediaColumns.IS_PENDING, 1)
			}

			val itemUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
				?: throw IOException("Could not create a Downloads entry.")

			resolver.openOutputStream(itemUri)?.use { outputStream ->
				sourceFile.inputStream().use { inputStream ->
					inputStream.copyTo(outputStream)
				}
			} ?: throw IOException("Could not open the Downloads entry for writing.")

			values.clear()
			values.put(MediaStore.MediaColumns.IS_PENDING, 0)
			resolver.update(itemUri, values, null, null)
			return itemUri.toString()
		}

		@Suppress("DEPRECATION")
		val downloadsDirectory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
		if (!downloadsDirectory.exists() && !downloadsDirectory.mkdirs()) {
			throw IOException("Could not create the public Downloads directory.")
		}

		val targetFile = File(downloadsDirectory, uniqueName(downloadsDirectory, displayName))
		sourceFile.copyTo(targetFile, overwrite = false)
		return targetFile.absolutePath
	}

	private fun uniqueName(directory: File, displayName: String): String {
		if (!File(directory, displayName).exists()) {
			return displayName
		}

		val dotIndex = displayName.lastIndexOf('.')
		val baseName = if (dotIndex > 0) displayName.substring(0, dotIndex) else displayName
		val extension = if (dotIndex > 0) displayName.substring(dotIndex) else ""
		var suffix = 1
		while (true) {
			val candidate = "$baseName ($suffix)$extension"
			if (!File(directory, candidate).exists()) {
				return candidate
			}
			suffix += 1
		}
	}
}
