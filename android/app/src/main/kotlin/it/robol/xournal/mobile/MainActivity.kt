package it.robol.xournal.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.io.File
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val documentWrites = Executors.newSingleThreadExecutor()
    private val storageChannel = "it.robol.xournal.mobile/storage"
    private val intentChannel = "it.robol.xournal.mobile/intent"
    private val folderRequestCode = 49318
    private var pendingFolderResult: MethodChannel.Result? = null
    private var pendingFolderSource: Uri? = null
    private val createDocumentRequestCode = 49317
    private var pendingCreateResult: MethodChannel.Result? = null
    private var pendingCreateBytes: ByteArray? = null
    private var openIntentChannel: MethodChannel? = null
    private val pendingOpenIntents = mutableListOf<Map<String, Any?>>()
    private var intentListenerReady = false

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (shouldConsumeStylusButtonEvent(event)) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        normalizeSamsungStylusButtonEvent(event)?.let { normalizedEvent ->
            return try {
                super.dispatchTouchEvent(normalizedEvent)
            } finally {
                normalizedEvent.recycle()
            }
        }
        if (shouldConsumeStylusButtonEvent(event)) return true
        return super.dispatchTouchEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notebookInFolder" -> {
                        try {
                            result.success(notebookInFolder(Uri.parse(call.argument<String>("folder")!!), Uri.parse(call.argument<String>("source")!!)))
                        } catch (error: Exception) { result.error("folder_failed", error.message, null) }
                    }
                    "deleteDocument" -> {
                        try {
                            val uri = Uri.parse(call.argument<String>("uri")!!)
                            check(DocumentsContract.deleteDocument(contentResolver, uri)) { "Provider refused deletion" }
                            result.success(null)
                        } catch (error: Exception) { result.error("delete_failed", error.message, null) }
                    }
                    "chooseNotebookFolder" -> {
                        if (pendingFolderResult != null) {
                            result.error("already_active", "Folder selection is active", null)
                        } else {
                            pendingFolderResult = result
                            pendingFolderSource = call.argument<String>("source")?.let { Uri.parse(it) }
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, folderRequestCode)
                        }
                    }
                    "createNotebookInFolder" -> {
                        try {
                            val tree = Uri.parse(call.argument<String>("folder")!!)
                            val name = call.argument<String>("name")!!
                            require(name.isNotBlank() && !name.contains('/') && !name.contains('\\'))
                            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                                while (cursor.moveToNext()) check(cursor.getString(0) != name) { "Name already exists; choose another name" }
                            } ?: error("Could not list folder")
                            val uri = DocumentsContract.createDocument(contentResolver, parent, "application/x-xopp", name) ?: error("Could not create notebook")
                            try {
                                // Providers may choose a unique name if another writer races us.
                                check(displayName(uri) == name) { "Provider changed the name; choose another name" }
                                contentResolver.openOutputStream(uri, "wt")?.use { it.write(call.argument<ByteArray>("bytes")!!) } ?: error("Could not write notebook")
                                result.success(uri.toString())
                            } catch (error: Exception) {
                                DocumentsContract.deleteDocument(contentResolver, uri)
                                throw error
                            }
                        } catch (error: Exception) { result.error("create_failed", error.message, null) }
                    }
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
                        documentWrites.execute { writeDocument(Uri.parse(uri), bytes, result) }
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
        enqueueOpenIntent(intent)
        openIntentChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeOpenIntents" -> {
                    intentListenerReady = true
                    val pending = pendingOpenIntents.toList()
                    pendingOpenIntents.clear()
                    result.success(pending)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun normalizeSamsungStylusButtonEvent(event: MotionEvent): MotionEvent? {
        if (
            event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY == 0 ||
            !isStylusEvent(event)
        ) {
            return null
        }

        val normalizedAction =
            when (event.actionMasked) {
                samsungStylusActionDown -> MotionEvent.ACTION_DOWN
                samsungStylusActionMove -> MotionEvent.ACTION_MOVE
                samsungStylusActionUp -> MotionEvent.ACTION_UP
                else -> return null
            }
        return MotionEvent.obtain(event).apply {
            action = normalizedAction
        }
    }

    private fun isStylusEvent(event: MotionEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS) {
            return true
        }
        return (0 until event.pointerCount).any {
            event.getToolType(it) == MotionEvent.TOOL_TYPE_STYLUS
        }
    }

    private fun shouldConsumeStylusButtonEvent(event: MotionEvent): Boolean {
        if (
            event.actionMasked != MotionEvent.ACTION_BUTTON_PRESS &&
            event.actionMasked != MotionEvent.ACTION_BUTTON_RELEASE
        ) {
            return false
        }

        val stylusButtonMask =
            MotionEvent.BUTTON_STYLUS_PRIMARY or MotionEvent.BUTTON_STYLUS_SECONDARY
        if (((event.buttonState or event.actionButton) and stylusButtonMask) == 0) return false
        if ((event.source and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS) {
            return true
        }

        for (pointerIndex in 0 until event.pointerCount) {
            if (event.getToolType(pointerIndex) == MotionEvent.TOOL_TYPE_STYLUS) {
                return true
            }
        }

        return false
    }

    companion object {
        private const val samsungStylusActionDown = 211
        private const val samsungStylusActionUp = 212
        private const val samsungStylusActionMove = 213
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueOpenIntent(intent)
        if (intentListenerReady && pendingOpenIntents.isNotEmpty()) {
            openIntentChannel?.invokeMethod("openIntentsAvailable", null)
        }
    }

    // Document IDs are provider-owned: enumerate immediate children rather than
    // guessing a parent by splitting an opaque ID or trusting a picked folder.
    private fun notebookInFolder(tree: Uri, source: Uri): Boolean {
        if (tree.authority != source.authority) return false
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val sourceId = DocumentsContract.getDocumentId(source)
        var found = false
        contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) if (cursor.getString(0) == sourceId) found = true
        } ?: error("Could not list folder")
        return found
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

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }

    private fun retainSafRecovery(uri: Uri, bytes: ByteArray, kind: String): String {
        // path_provider's Android application-support directory is filesDir.
        // Publish a normal recovery draft only after its content is on disk.
        val directory = File(filesDir, "recovery_drafts")
        if (!directory.exists()) {
            check(directory.mkdir()) { "Could not create recovery directory" }
            syncDirectory(filesDir)
        }
        val id = "${System.currentTimeMillis() * 1000}_${UUID.randomUUID().leastSignificantBits and Long.MAX_VALUE}"
        val temporary = File(directory, "$id.tmp")
        val published = File(directory, "$id.json")
        check(temporary.createNewFile() && !published.exists()) { "Recovery name collision" }
        val name = (displayName(uri) ?: "Notebook").removeSuffix(".xopp")
        val metadata = JSONObject().apply {
            put("version", 1)
            put("id", id)
            put("bytes", Base64.encodeToString(bytes, Base64.NO_WRAP))
            put("page", 0)
            put("title", name)
            put("safRecoveryKind", kind)
            // Deliberately omit originalPath/backendId: recovery must use Save As.
        }
        try {
            FileOutputStream(temporary).use { output ->
                output.write(metadata.toString().toByteArray(Charsets.UTF_8))
                output.flush()
                output.fd.sync()
            }
            check(temporary.renameTo(published)) { "Could not publish recovery copy" }
            syncDirectory(directory)
        } catch (error: Exception) {
            temporary.delete()
            throw error
        }
        return id
    }

    private fun writeDocument(uri: Uri, bytes: ByteArray, result: MethodChannel.Result) {
        try {
            SafOverwrite.write(object : SafOverwrite.Document {
                override fun read(): ByteArray = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Could not read document for verification or backup")
                override fun write(data: ByteArray) {
                    // Provider-specific truncation is allowed only after both durable copies exist.
                    contentResolver.openFileDescriptor(uri, "rwt")?.use { descriptor ->
                        FileOutputStream(descriptor.fileDescriptor).use { output ->
                            output.write(data)
                            output.flush()
                        }
                    } ?: error("Could not open document for writing")
                }
            }, object : SafOverwrite.Recovery {
                override fun retain(data: ByteArray, kind: String): String = retainSafRecovery(uri, data, kind)
                override fun remove(id: String) {
                    val directory = File(filesDir, "recovery_drafts")
                    check(File(directory, "$id.json").delete()) { "Could not remove recovery copy" }
                    syncDirectory(directory)
                }
            }, bytes)
            result.success(null)
        } catch (error: SafOverwrite.Failure) {
            result.error("write_failed", error.message, mapOf("recoveryAvailable" to error.recoveryAvailable))
        } catch (error: Exception) {
            result.error("write_failed", error.message, mapOf("recoveryAvailable" to false))
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
        if (requestCode == folderRequestCode) {
            val result = pendingFolderResult
            val source = pendingFolderSource
            pendingFolderResult = null
            pendingFolderSource = null
            val tree = data?.data
            if (resultCode != Activity.RESULT_OK || tree == null) { result?.success(null); return }
            try {
                val flags = (data.flags) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(tree, flags)
                check(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) { "Folder is not writable" }
                if (source != null) {
                    check(notebookInFolder(tree, source)) { "Select the notebook's current folder" }
                }
                result?.success(tree.toString())
            } catch (error: Exception) { result?.error("folder_failed", error.message, null) }
            return
        }
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

    @Suppress("DEPRECATION")
    private fun enqueueOpenIntent(intent: Intent?) {
        if (intent == null) return
        val streams: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else -> emptyList()
        }
        val uris = if (streams.isNotEmpty()) streams else if (
            intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE
        ) {
            val clip = intent.clipData
            if (clip == null) emptyList() else (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        } else emptyList()
        for (uri in uris) {
            val persisted = persistIntentPermission(intent, uri)
            pendingOpenIntents.add(mapOf(
                "uri" to uri.toString(),
                "mimeType" to (intent.type ?: try { contentResolver.getType(uri) } catch (_: Exception) { null }),
                "displayName" to displayName(uri),
                "writable" to (persisted && intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
            ))
        }
        if (uris.isNotEmpty()) setIntent(Intent(Intent.ACTION_MAIN))
    }

    private fun persistIntentPermission(intent: Intent, uri: Uri): Boolean {
        val flags = intent.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (flags == 0) return false

        return try {
            contentResolver.takePersistableUriPermission(uri, flags)
            true
        } catch (_: SecurityException) {
            false
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
