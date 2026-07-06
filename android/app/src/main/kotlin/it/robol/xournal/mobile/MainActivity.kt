package it.robol.xournal.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val storageChannel = "it.robol.xournal.mobile/storage"
    private val intentChannel = "it.robol.xournal.mobile/intent"
    private val createDocumentRequestCode = 49317
    private var pendingCreateResult: MethodChannel.Result? = null
    private var pendingCreateBytes: ByteArray? = null
    private var openIntentChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createDocument" -> {
                        val fileName = call.argument<String>("fileName") ?: "xournalpp-export"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("missing_bytes", "No document bytes were provided.", null)
                            return@setMethodCallHandler
                        }
                        createDocument(fileName, bytes, result)
                    }
                    "readDocument" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("missing_uri", "No document URI was provided.", null)
                            return@setMethodCallHandler
                        }
                        readDocument(Uri.parse(uri), result)
                    }
                    "writeDocument" -> {
                        val uri = call.argument<String>("uri")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (uri == null || bytes == null) {
                            result.error("missing_args", "Document URI and bytes are required.", null)
                            return@setMethodCallHandler
                        }
                        writeDocument(Uri.parse(uri), bytes, result)
                    }
                    "persistDocumentAccess" -> {
                        val uri = call.argument<String>("uri")
                        val writable = call.argument<Boolean>("writable") ?: false
                        if (uri == null) {
                            result.error("missing_uri", "No document URI was provided.", null)
                            return@setMethodCallHandler
                        }
                        persistDocumentAccess(Uri.parse(uri), writable, result)
                    }
                    else -> result.notImplemented()
                }
            }
        openIntentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, intentChannel)
        openIntentChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialOpenIntent" -> result.success(openIntentPayload(intent))
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openIntentPayload(intent)?.let {
            openIntentChannel?.invokeMethod("openIntent", it)
        }
    }

    private fun createDocument(fileName: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (pendingCreateResult != null) {
            result.error("already_active", "A document save operation is already active.", null)
            return
        }

        pendingCreateResult = result
        pendingCreateBytes = bytes

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/x-xopp"
            putExtra(Intent.EXTRA_TITLE, fileName)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }

        startActivityForResult(intent, createDocumentRequestCode)
    }

    private fun readDocument(uri: Uri, result: MethodChannel.Result) {
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) {
                result.error("read_failed", "Could not open document for reading.", uri.toString())
                return
            }
            result.success(bytes)
        } catch (error: Exception) {
            result.error("read_failed", error.message, uri.toString())
        }
    }

    private fun writeDocument(uri: Uri, bytes: ByteArray, result: MethodChannel.Result) {
        try {
            contentResolver.openFileDescriptor(uri, "rwt")?.use { descriptor ->
                FileOutputStream(descriptor.fileDescriptor).use { output ->
                    output.write(bytes)
                    output.flush()
                }
            }
                ?: run {
                    result.error("write_failed", "Could not open document for writing.", uri.toString())
                    return
                }
            result.success(null)
        } catch (error: Exception) {
            result.error("write_failed", error.message, uri.toString())
        }
    }

    private fun persistDocumentAccess(uri: Uri, writable: Boolean, result: MethodChannel.Result) {
        val readFlag = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val requestedFlags = if (writable) {
            readFlag or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        } else {
            readFlag
        }

        try {
            contentResolver.takePersistableUriPermission(uri, requestedFlags)
            result.success(true)
        } catch (_: SecurityException) {
            if (!writable) {
                result.success(false)
                return
            }

            try {
                contentResolver.takePersistableUriPermission(uri, readFlag)
                result.success(true)
            } catch (_: SecurityException) {
                result.success(false)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == createDocumentRequestCode) {
            handleCreateDocumentResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handleCreateDocumentResult(resultCode: Int, data: Intent?) {
        val result = pendingCreateResult
        val bytes = pendingCreateBytes
        pendingCreateResult = null
        pendingCreateBytes = null

        if (result == null || bytes == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        val persistableFlags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        if (persistableFlags != 0) {
            try {
                contentResolver.takePersistableUriPermission(uri, persistableFlags)
            } catch (_: SecurityException) {
            }
        }

        try {
            contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                ?: run {
                    result.error("write_failed", "Could not open document for writing.", uri.toString())
                    return
                }
            result.success(uri.toString())
        } catch (error: Exception) {
            result.error("write_failed", error.message, uri.toString())
        }
    }

    private fun openIntentPayload(intent: Intent?): Map<String, String?>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null

        val uri = intent.data ?: return null
        persistReadableIntentPermission(intent, uri)

        return mapOf(
            "uri" to uri.toString(),
            "mimeType" to intent.type,
            "displayName" to displayName(uri)
        )
    }

    private fun persistReadableIntentPermission(intent: Intent, uri: Uri) {
        val flags = intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (flags == 0) return

        try {
            contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (index >= 0) return cursor.getString(index)
                        }
                    }
            } catch (_: Exception) {
            }
        }

        return uri.lastPathSegment
    }
}
