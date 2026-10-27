package com.mimbar.mimbar

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Hands flier files to other apps. Its own class so it can't clash with
 *  a plugin's FileProvider in the merged manifest. */
class MimbarFileProvider : FileProvider()

/**
 * Native bits for the "mimbar/native" channel: posting to a specific app
 * (Facebook / WhatsApp), picking a contact, and images shared into Mimbar
 * from other apps (e.g. a flier from WhatsApp).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingContact: MethodChannel.Result? = null
    private var sharedImage: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedImage = takeShare(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mimbar/native").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareTo" -> result.success(
                        shareTo(call.argument("package")!!, call.argument("text"), call.argument("path"))
                    )
                    "pickContact" -> pickContact(result)
                    "takeSharedImage" -> {
                        result.success(sharedImage)
                        sharedImage = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = takeShare(intent) ?: return
        channel?.invokeMethod("sharedImage", path)
    }

    // ------------------------------------------------------------ sharing

    private fun shareTo(pkg: String, text: String?, path: String?): Boolean {
        val send = Intent(Intent.ACTION_SEND).setPackage(pkg)
        if (path != null) {
            val uri = FileProvider.getUriForFile(this, "$packageName.mimbar.files", File(path))
            send.type = "image/jpeg"
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            send.type = "text/plain"
        }
        if (text != null) send.putExtra(Intent.EXTRA_TEXT, text)
        return try {
            startActivity(send)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Copies an image shared into Mimbar to the cache and returns its path.
     *  The intent is then cleared so a screen rotation doesn't repeat it. */
    private fun takeShare(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("image/") != true) return null
        val uri: Uri = (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }) ?: return null
        setIntent(Intent(this, MainActivity::class.java))
        return try {
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val out = File(dir, "shared-${System.currentTimeMillis()}.img")
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.path
        } catch (e: Exception) {
            null
        }
    }

    // ----------------------------------------------------------- contacts

    private fun pickContact(result: MethodChannel.Result) {
        pendingContact?.success(null)
        pendingContact = result
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            launchPicker()
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), REQ_CONTACTS)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CONTACTS) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            launchPicker()
        } else {
            pendingContact?.success(mapOf("denied" to true))
            pendingContact = null
        }
    }

    private fun launchPicker() {
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent(Intent.ACTION_PICK, ContactsContract.Contacts.CONTENT_URI), REQ_PICK)
        } catch (e: ActivityNotFoundException) {
            pendingContact?.success(null)
            pendingContact = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK) return
        val result = pendingContact ?: return
        pendingContact = null
        val uri = data?.data
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) readContact(uri) else null)
    }

    /** Name plus numbers: the default number first, then newest-added. */
    private fun readContact(uri: Uri): Map<String, Any>? {
        var id: String? = null
        var name = ""
        contentResolver.query(
            uri, arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            if (c.moveToFirst()) {
                id = c.getString(0)
                name = c.getString(1) ?: ""
            }
        }
        val contactId = id ?: return null
        val phones = mutableListOf<String>()
        contentResolver.query(
            Phone.CONTENT_URI, arrayOf(Phone.NUMBER), "${Phone.CONTACT_ID} = ?", arrayOf(contactId),
            "${Phone.IS_SUPER_PRIMARY} DESC, ${Phone.IS_PRIMARY} DESC, ${Phone._ID} DESC"
        )?.use { c ->
            while (c.moveToNext()) c.getString(0)?.let { phones.add(it) }
        }
        return mapOf("name" to name, "phones" to phones)
    }

    companion object {
        private const val REQ_CONTACTS = 0x4D31
        private const val REQ_PICK = 0x4D32
    }
}
