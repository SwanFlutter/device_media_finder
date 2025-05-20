package com.example.device_media_finder

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** DeviceMediaFinderPlugin */
class DeviceMediaFinderPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var pendingResult: Result? = null
  private var pendingOperation: String? = null

  private val executor = Executors.newCachedThreadPool()
  private val cacheDir by lazy { File(context.cacheDir, "media_thumbnails") }

  companion object {
    private const val TAG = "DeviceMediaFinder"
    private const val REQUEST_CODE_PERMISSIONS = 1001
    private val REQUIRED_PERMISSIONS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      arrayOf(
        Manifest.permission.READ_MEDIA_IMAGES,
        Manifest.permission.READ_MEDIA_VIDEO,
        Manifest.permission.READ_MEDIA_AUDIO
      )
    } else {
      arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_media_finder")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext

    // Create cache directory if it doesn't exist
    if (!cacheDir.exists()) {
      cacheDir.mkdirs()
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "getVideos" -> {
        if (checkAndRequestPermissions(result, "getVideos")) {
          executor.execute {
            try {
              val videos = getVideos()
              activity?.runOnUiThread {
                result.success(videos)
              }
            } catch (e: Exception) {
              Log.e(TAG, "Error in getVideos method call: ${e.message}")
              e.printStackTrace()
              activity?.runOnUiThread {
                result.error("VIDEO_FETCH_ERROR", "Failed to fetch videos: ${e.message}", null)
              }
            }
          }
        }
      }
      "getVideosByMimeType" -> {
        if (checkAndRequestPermissions(result, "getVideosByMimeType")) {
          val mimeTypes = call.argument<List<String>>("mimeTypes")

          executor.execute {
            try {
              val videos = if (mimeTypes.isNullOrEmpty()) {
                getVideos()
              } else {
                getVideosByMimeTypes(mimeTypes)
              }

              activity?.runOnUiThread {
                result.success(videos)
              }
            } catch (e: Exception) {
              Log.e(TAG, "Error in getVideosByMimeType method call: ${e.message}")
              e.printStackTrace()
              activity?.runOnUiThread {
                result.error("VIDEO_FETCH_ERROR", "Failed to fetch videos by mime type: ${e.message}", null)
              }
            }
          }
        }
      }
      "getAudios" -> {
        if (checkAndRequestPermissions(result, "getAudios")) {
          executor.execute {
            try {
              val audios = getAudios()
              activity?.runOnUiThread {
                result.success(audios)
              }
            } catch (e: Exception) {
              Log.e(TAG, "Error in getAudios method call: ${e.message}")
              e.printStackTrace()
              activity?.runOnUiThread {
                result.error("AUDIO_FETCH_ERROR", "Failed to fetch audios: ${e.message}", null)
              }
            }
          }
        }
      }
      "getVideoThumbnail" -> {
        if (checkAndRequestPermissions(result, "getVideoThumbnail")) {
          val videoId = call.argument<String>("videoId")
          val width = call.argument<Int>("width") ?: 128
          val height = call.argument<Int>("height") ?: 128

          if (videoId == null) {
            result.error("INVALID_ARGUMENT", "videoId is required", null)
            return
          }

          executor.execute {
            try {
              val thumbnail = getVideoThumbnail(videoId, width, height)
              activity?.runOnUiThread {
                result.success(thumbnail)
              }
            } catch (e: Exception) {
              Log.e(TAG, "Error in getVideoThumbnail method call: ${e.message}")
              e.printStackTrace()
              activity?.runOnUiThread {
                result.error("THUMBNAIL_ERROR", "Failed to get thumbnail: ${e.message}", null)
              }
            }
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun checkAndRequestPermissions(result: Result, operation: String): Boolean {
    if (activity == null) {
      result.error("ACTIVITY_NOT_AVAILABLE", "Activity is not available", null)
      return false
    }

    val missingPermissions = REQUIRED_PERMISSIONS.filter {
      ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
    }.toTypedArray()

    return if (missingPermissions.isEmpty()) {
      true
    } else {
      pendingResult = result
      pendingOperation = operation
      ActivityCompat.requestPermissions(activity!!, missingPermissions, REQUEST_CODE_PERMISSIONS)
      false
    }
  }

  private fun getVideos(): List<Map<String, Any>> {
    Log.d(TAG, "Starting to fetch videos")
    val videos = mutableListOf<Map<String, Any>>()
    val projection = arrayOf(
      MediaStore.Video.Media._ID,
      MediaStore.Video.Media.DISPLAY_NAME,
      MediaStore.Video.Media.DURATION,
      MediaStore.Video.Media.SIZE,
      MediaStore.Video.Media.DATA,
      MediaStore.Video.Media.DATE_ADDED,
      MediaStore.Video.Media.MIME_TYPE
    )

    // More inclusive selection that doesn't filter out videos with unknown duration
    val selection = "${MediaStore.Video.Media.SIZE} > 0"
    val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

    try {
      Log.d(TAG, "Querying content resolver for videos")
      val cursor = context.contentResolver.query(
        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        projection,
        selection,
        null,
        sortOrder
      )

      if (cursor == null) {
        Log.e(TAG, "Cursor is null when querying videos")
        return videos
      }

      Log.d(TAG, "Found ${cursor.count} videos in media store")

      cursor.use {
        val idColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
        val nameColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
        val durationColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
        val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
        val dataColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
        val dateAddedColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
        val mimeTypeColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)

        while (it.moveToNext()) {
          try {
            val id = it.getLong(idColumn)
            val name = it.getString(nameColumn) ?: "Unknown"
            // Handle case where duration might be null or invalid
            val duration = try {
              it.getLong(durationColumn)
            } catch (e: Exception) {
              0L // Default duration if not available
            }
            val size = it.getLong(sizeColumn)
            val path = it.getString(dataColumn) ?: ""
            val dateAdded = it.getLong(dateAddedColumn)
            val mimeType = it.getString(mimeTypeColumn) ?: "video/*"

            val contentUri = ContentUris.withAppendedId(
              MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
              id
            )

            // Check if the file exists
            val file = File(path)
            if (!file.exists()) {
              Log.w(TAG, "Skipping video as file doesn't exist: $path")
              continue
            }

            Log.d(TAG, "Found video: $name, mimeType: $mimeType, size: $size bytes")

            videos.add(mapOf(
              "id" to id.toString(),
              "name" to name,
              "duration" to duration,
              "size" to size,
              "path" to path,
              "uri" to contentUri.toString(),
              "dateAdded" to dateAdded,
              "mimeType" to mimeType
            ))
          } catch (e: Exception) {
            Log.e(TAG, "Error processing video item: ${e.message}")
          }
        }
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error querying videos: ${e.message}")
      e.printStackTrace()
    }

    Log.d(TAG, "Returning ${videos.size} videos")
    return videos
  }

  private fun getVideosByMimeTypes(mimeTypes: List<String>): List<Map<String, Any>> {
    Log.d(TAG, "Starting to fetch videos by MIME types: $mimeTypes")
    val videos = mutableListOf<Map<String, Any>>()
    val projection = arrayOf(
      MediaStore.Video.Media._ID,
      MediaStore.Video.Media.DISPLAY_NAME,
      MediaStore.Video.Media.DURATION,
      MediaStore.Video.Media.SIZE,
      MediaStore.Video.Media.DATA,
      MediaStore.Video.Media.DATE_ADDED,
      MediaStore.Video.Media.MIME_TYPE
    )

    // Build a selection clause for the specified MIME types
    val selectionBuilder = StringBuilder()
    val selectionArgs = mutableListOf<String>()

    selectionBuilder.append("${MediaStore.Video.Media.SIZE} > 0 AND (")

    mimeTypes.forEachIndexed { index, mimeType ->
      if (index > 0) {
        selectionBuilder.append(" OR ")
      }
      selectionBuilder.append("${MediaStore.Video.Media.MIME_TYPE} LIKE ?")

      // Use wildcards for more flexible matching
      if (mimeType.endsWith("/*")) {
        selectionArgs.add(mimeType.replace("/*", "%"))
      } else {
        selectionArgs.add(mimeType)
      }
    }

    selectionBuilder.append(")")

    val selection = selectionBuilder.toString()
    val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

    Log.d(TAG, "Video query selection: $selection")
    Log.d(TAG, "Video query selection args: $selectionArgs")

    try {
      val cursor = context.contentResolver.query(
        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        projection,
        selection,
        selectionArgs.toTypedArray(),
        sortOrder
      )

      if (cursor == null) {
        Log.e(TAG, "Cursor is null when querying videos by MIME types")
        return videos
      }

      Log.d(TAG, "Found ${cursor.count} videos matching the MIME types")

      cursor.use {
        val idColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
        val nameColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
        val durationColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
        val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
        val dataColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
        val dateAddedColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
        val mimeTypeColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)

        while (it.moveToNext()) {
          try {
            val id = it.getLong(idColumn)
            val name = it.getString(nameColumn) ?: "Unknown"
            val duration = try {
              it.getLong(durationColumn)
            } catch (e: Exception) {
              0L
            }
            val size = it.getLong(sizeColumn)
            val path = it.getString(dataColumn) ?: ""
            val dateAdded = it.getLong(dateAddedColumn)
            val mimeType = it.getString(mimeTypeColumn) ?: "video/*"

            val contentUri = ContentUris.withAppendedId(
              MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
              id
            )

            // Check if the file exists
            val file = File(path)
            if (!file.exists()) {
              Log.w(TAG, "Skipping video as file doesn't exist: $path")
              continue
            }

            Log.d(TAG, "Found video by MIME type: $name, mimeType: $mimeType, size: $size bytes")

            videos.add(mapOf(
              "id" to id.toString(),
              "name" to name,
              "duration" to duration,
              "size" to size,
              "path" to path,
              "uri" to contentUri.toString(),
              "dateAdded" to dateAdded,
              "mimeType" to mimeType
            ))
          } catch (e: Exception) {
            Log.e(TAG, "Error processing video item by MIME type: ${e.message}")
          }
        }
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error querying videos by MIME types: ${e.message}")
      e.printStackTrace()
    }

    Log.d(TAG, "Returning ${videos.size} videos matching the MIME types")
    return videos
  }

  private fun getAudios(): List<Map<String, Any>> {
    val audios = mutableListOf<Map<String, Any>>()
    val projection = arrayOf(
      MediaStore.Audio.Media._ID,
      MediaStore.Audio.Media.DISPLAY_NAME,
      MediaStore.Audio.Media.DURATION,
      MediaStore.Audio.Media.SIZE,
      MediaStore.Audio.Media.DATA,
      MediaStore.Audio.Media.DATE_ADDED,
      MediaStore.Audio.Media.MIME_TYPE,
      MediaStore.Audio.Media.ARTIST,
      MediaStore.Audio.Media.ALBUM
    )

    val selection = "${MediaStore.Audio.Media.SIZE} > 0 AND ${MediaStore.Audio.Media.IS_MUSIC} = 1"
    val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

    context.contentResolver.query(
      MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
      projection,
      selection,
      null,
      sortOrder
    )?.use { cursor ->
      val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
      val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
      val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
      val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
      val dataColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
      val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
      val mimeTypeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
      val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
      val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)

      while (cursor.moveToNext()) {
        val id = cursor.getLong(idColumn)
        val name = cursor.getString(nameColumn)
        val duration = cursor.getLong(durationColumn)
        val size = cursor.getLong(sizeColumn)
        val path = cursor.getString(dataColumn)
        val dateAdded = cursor.getLong(dateAddedColumn)
        val mimeType = cursor.getString(mimeTypeColumn)
        val artist = cursor.getString(artistColumn)
        val album = cursor.getString(albumColumn)

        val contentUri = ContentUris.withAppendedId(
          MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
          id
        )

        audios.add(mapOf(
          "id" to id.toString(),
          "name" to name,
          "duration" to duration,
          "size" to size,
          "path" to path,
          "uri" to contentUri.toString(),
          "dateAdded" to dateAdded,
          "mimeType" to mimeType,
          "artist" to artist,
          "album" to album
        ))
      }
    }

    return audios
  }

  private fun getVideoThumbnail(videoId: String, width: Int, height: Int): ByteArray? {
    // Check if thumbnail is cached
    val cacheFile = File(cacheDir, "video_$videoId.jpg")
    if (cacheFile.exists()) {
      return cacheFile.readBytes()
    }

    // Generate thumbnail
    val contentUri = ContentUris.withAppendedId(
      MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
      videoId.toLong()
    )

    val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      getThumbnailAndroid10Plus(contentUri, width, height)
    } else {
      getThumbnailLegacy(contentUri, width, height)
    }

    if (bitmap != null) {
      val outputStream = ByteArrayOutputStream()
      bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
      val byteArray = outputStream.toByteArray()

      // Cache the thumbnail
      try {
        FileOutputStream(cacheFile).use { fos ->
          fos.write(byteArray)
        }
      } catch (e: Exception) {
        Log.e(TAG, "Failed to cache thumbnail", e)
      }

      return byteArray
    }

    return null
  }

  @RequiresApi(Build.VERSION_CODES.Q)
  private fun getThumbnailAndroid10Plus(uri: Uri, width: Int, height: Int): Bitmap? {
    return try {
      context.contentResolver.loadThumbnail(uri, Size(width, height), null)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to load thumbnail for $uri", e)
      null
    }
  }

  private fun getThumbnailLegacy(uri: Uri, width: Int, height: Int): Bitmap? {
    val path = getPathFromUri(uri) ?: return null

    return try {
      val retriever = MediaMetadataRetriever()
      retriever.setDataSource(path)
      val frame = retriever.getFrameAtTime(TimeUnit.MILLISECONDS.toMicros(1000))
      retriever.release()

      if (frame != null) {
        ThumbnailUtils.extractThumbnail(frame, width, height)
      } else {
        null
      }
    } catch (e: Exception) {
      Log.e(TAG, "Failed to extract thumbnail for $path", e)
      null
    }
  }

  private fun getPathFromUri(uri: Uri): String? {
    val projection = arrayOf(MediaStore.Video.Media.DATA)
    context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) {
        val columnIndex = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
        return cursor.getString(columnIndex)
      }
    }
    return null
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    executor.shutdown()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
    if (requestCode == REQUEST_CODE_PERMISSIONS) {
      if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
        // Permissions granted, continue with the pending operation
        when (pendingOperation) {
          "getVideos" -> {
            executor.execute {
              try {
                val videos = getVideos()
                activity?.runOnUiThread {
                  pendingResult?.success(videos)
                }
              } catch (e: Exception) {
                Log.e(TAG, "Error in getVideos after permission granted: ${e.message}")
                e.printStackTrace()
                activity?.runOnUiThread {
                  pendingResult?.error("VIDEO_FETCH_ERROR", "Failed to fetch videos: ${e.message}", null)
                }
              } finally {
                pendingResult = null
                pendingOperation = null
              }
            }
          }
          "getVideosByMimeType" -> {
            // This would need the mimeTypes parameter which we don't have here
            // In a real implementation, you'd need to store these parameters when the original call was made
            pendingResult?.error("PERMISSION_ERROR", "Permission granted but cannot complete operation without parameters", null)
            pendingResult = null
            pendingOperation = null
          }
          "getAudios" -> {
            executor.execute {
              try {
                val audios = getAudios()
                activity?.runOnUiThread {
                  pendingResult?.success(audios)
                }
              } catch (e: Exception) {
                Log.e(TAG, "Error in getAudios after permission granted: ${e.message}")
                e.printStackTrace()
                activity?.runOnUiThread {
                  pendingResult?.error("AUDIO_FETCH_ERROR", "Failed to fetch audios: ${e.message}", null)
                }
              } finally {
                pendingResult = null
                pendingOperation = null
              }
            }
          }
          "getVideoThumbnail" -> {
            // This would need the videoId, width, and height parameters which we don't have here
            // In a real implementation, you'd need to store these parameters when the original call was made
            pendingResult?.error("PERMISSION_ERROR", "Permission granted but cannot complete operation without parameters", null)
            pendingResult = null
            pendingOperation = null
          }
        }
        return true
      } else {
        // Permissions denied
        Log.e(TAG, "Permissions denied: ${permissions.joinToString()}")
        pendingResult?.error("PERMISSION_DENIED", "Required permissions were not granted", null)
        pendingResult = null
        pendingOperation = null
        return true
      }
    }
    return false
  }
}
