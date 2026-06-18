package com.example.dsc_demo

import android.hardware.usb.UsbManager
import android.os.Bundle
import android.util.Log
import android.widget.Toast

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import java.io.ByteArrayInputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.security.auth.x500.X500Principal

import `in`.co.precisionit.innait.dsc.pkcs11.USBHandler.USBHandler
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.CK_ATTRIBUTE
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.CK_MECHANISM
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.PKCS11
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.PKCS11Connector
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.PKCS11Constants
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.PKCS11Exception
import `in`.co.precisionit.innait.dsc.pkcs11.wrapper.PKCS11Implementation

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DSC_APP"
        private const val CHANNEL = "dsc_token_channel"
    }

    private lateinit var methodChannel: MethodChannel

    private var pkcs11Module: PKCS11? = null

    private var session: Long = 0

    /*
     * SLOT ID
     */
    private var slotId: Long = -1

    private var privateKeyHandle: Long = 0
    private var publicKeyHandle: Long = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        /*
         * GLOBAL CRASH HANDLER
         */
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->

            Log.e(
                TAG,
                "FATAL CRASH IN THREAD: ${thread.name}",
                throwable
            )

            sendLog(
                "FATAL_CRASH: ${throwable.message}"
            )

            throwable.stackTrace.forEach {
                Log.e(TAG, it.toString())
            }
        }
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                /*
                 * INITIALIZE
                 */
                "initialize" -> {

                    sendLog("initialize() called")

                    try {

                        initializeLibrary()

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Module Not Loaded"
                            )

                        sendLog(
                            "Calling C_Initialize..."
                        )

                        try {

                            module.C_Initialize(null)

                        } catch (e: Exception) {

                            sendLog(
                                "C_Initialize Warning: ${e.message}"
                            )
                        }

                        sendLog(
                            "PKCS11 initialized successfully"
                        )

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "INIT_ERROR: ${e.message}"
                        )

                        Log.e(
                            TAG,
                            "INIT_ERROR",
                            e
                        )

                        result.error(
                            "INIT_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * CHECK USB TOKEN
                 */
                "checkUsbToken" -> {

                    try {

                        val usbManager =
                            getSystemService(
                                USB_SERVICE
                            ) as UsbManager

                        val deviceList =
                            usbManager.deviceList

                        sendLog(
                            "USB Devices Count = ${deviceList.size}"
                        )

                        for (device in deviceList.values) {

                            sendLog(
                                """
                                USB Device Found:
                                Vendor=${device.vendorId}
                                Product=${device.productId}
                                Name=${device.deviceName}
                                """.trimIndent()
                            )
                        }

                        result.success(
                            deviceList.isNotEmpty()
                        )

                    } catch (e: Exception) {

                        sendLog(
                            "USB_CHECK_ERROR: ${e.message}"
                        )

                        result.success(false)
                    }
                }

                /*
                 * SLOT INFO
                 */
                "getSlotInfo" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        sendLog(
                            "Getting Slot Info..."
                        )

                        val slots =
                            module.C_GetSlotList(true)

                        sendLog(
                            "Slots Count = ${slots.size}"
                        )

                        slots.forEachIndexed { index, slot ->

                            sendLog(
                                "Slot[$index] = $slot"
                            )
                        }

                        if (slots.isEmpty()) {

                            sendLog(
                                "No token detected"
                            )

                            result.error(
                                "NO_SLOT",
                                "No token detected",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        slotId = slots[0]

                        sendLog(
                            "Selected Slot ID = $slotId"
                        )

                        val tokenInfo =
                            module.C_GetTokenInfo(
                                slotId
                            )

                        val label =
                            tokenInfo?.label
                                ?.trim()
                                ?: "Token Found"

                        sendLog(
                            "Token Label = $label"
                        )

                        result.success(label)

                    } catch (e: PKCS11Exception) {

                        sendLog(
                            "PKCS11 ERROR CODE = ${e.errorCode}"
                        )

                        sendLog(
                            "PKCS11 ERROR = ${e.message}"
                        )

                        Log.e(
                            TAG,
                            "PKCS11_EXCEPTION",
                            e
                        )

                        result.error(
                            "SLOT_ERROR",
                            "${e.errorCode} : ${e.message}",
                            null
                        )

                    } catch (e: Exception) {

                        sendLog(
                            "SLOT_ERROR: ${e.message}"
                        )

                        Log.e(
                            TAG,
                            "SLOT_ERROR",
                            e
                        )

                        result.error(
                            "SLOT_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * OPEN SESSION
                 */
                "openSession" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (slotId == -1L) {

                            throw Exception(
                                "Invalid Slot ID"
                            )
                        }

                        session = module.C_OpenSession(
                            slotId,
                            PKCS11Constants.CKF_SERIAL_SESSION or
                                    PKCS11Constants.CKF_RW_SESSION,
                            null,
                            null
                        )

                        sendLog(
                            "Session Opened = $session"
                        )

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "SESSION_ERROR: ${e.message}"
                        )

                        result.error(
                            "SESSION_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * LOGIN
                 */
                "loginUser" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {

                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        val pin =
                            call.argument<String>("pin")
                                ?: ""

                        sendLog(
                            "User Pin = $pin"
                        )

                        if (pin.isEmpty()) {

                            throw Exception(
                                "PIN Empty"
                            )
                        }

                        module.C_Login(
                            session,
                            PKCS11Constants.CKU_USER,
                            pin.toCharArray()
                        )

                        sendLog(
                            "Token Login Successful"
                        )

                        result.success(true)

                    } catch (e: PKCS11Exception) {

                        sendLog(
                            "LOGIN_ERROR: ${e.message}"
                        )

                        result.error(
                            "LOGIN_ERROR",
                            e.message,
                            null
                        )

                    } catch (e: Exception) {

                        sendLog(
                            "LOGIN_ERROR: ${e.message}"
                        )

                        result.error(
                            "LOGIN_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * GENERATE KEYPAIR
                 */
                "generateKeypair" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {

                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        val mechanism =
                            CK_MECHANISM().apply {

                                mechanism =
                                    PKCS11Constants.CKM_RSA_PKCS_KEY_PAIR_GEN

                                pParameter = null
                            }

                        /*
                         * DEFAULT TEMPLATES
                         * (CKA_MODULUS_BITS and CKA_PUBLIC_EXPONENT
                         *  are mandatory for RSA keypair generation
                         *  per the PKCS#11 spec; empty templates
                         *  return CKR_ARGUMENTS_BAD = 0x07)
                         */
                        val publicTemplate = arrayOf(
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_TOKEN
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_MODULUS_BITS
                                pValue = 2048L
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_PUBLIC_EXPONENT
                                pValue = byteArrayOf(0x01, 0x00, 0x01)
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_VERIFY
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_LABEL
                                pValue = "DSC RSA Public".toByteArray()
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_ID
                                pValue = byteArrayOf(0x01)
                            }
                        )

                        val privateTemplate = arrayOf(
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_TOKEN
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_PRIVATE
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_SENSITIVE
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_SIGN
                                pValue = true
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_LABEL
                                pValue = "DSC RSA Private".toByteArray()
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_ID
                                pValue = byteArrayOf(0x01)
                            }
                        )

                        val handles =
                            module.C_GenerateKeyPair(
                                session,
                                mechanism,
                                publicTemplate,
                                privateTemplate
                            )

                        if (handles == null ||
                            handles.size < 2
                        ) {

                            throw Exception(
                                "Invalid Keypair Handles"
                            )
                        }

                        publicKeyHandle =
                            handles[0]

                        privateKeyHandle =
                            handles[1]

                        val map =
                            HashMap<String, Any>()

                        map["publicKey"] =
                            publicKeyHandle

                        map["privateKey"] =
                            privateKeyHandle

                        sendLog(
                            "Keypair Generated"
                        )

                        result.success(map)

                    } catch (e: Exception) {

                        sendLog(
                            "KEYPAIR_ERROR: ${e.message}"
                        )

                        result.error(
                            "KEYPAIR_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * LIST KEY PAIRS
                 * (find all private keys on the token so the
                 *  user can pick one instead of generating a
                 *  new keypair every time)
                 */
                "listKeyPairs" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {

                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        val findTemplate = arrayOf(
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_CLASS
                                pValue = PKCS11Constants.CKO_PRIVATE_KEY
                            }
                        )

                        module.C_FindObjectsInit(
                            session,
                            findTemplate
                        )

                        val keyList =
                            ArrayList<HashMap<String, Any>>()

                        while (true) {

                            val found =
                                module.C_FindObjects(
                                    session,
                                    100
                                )

                            if (found == null ||
                                found.isEmpty()
                            ) {
                                break
                            }

                            for (handle in found) {

                                val attrs = arrayOf(
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_LABEL
                                    },
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_ID
                                    }
                                )

                                var label = ""
                                var idHex = ""

                                try {

                                    module.C_GetAttributeValue(
                                        session,
                                        handle,
                                        attrs
                                    )

                                    label =
                                        (attrs[0].pValue as? ByteArray)
                                            ?.toString(Charsets.UTF_8)
                                            ?.trim()
                                            ?: ""

                                    idHex =
                                        (attrs[1].pValue as? ByteArray)
                                            ?.joinToString("") {
                                                "%02X".format(it)
                                            }
                                            ?: ""

                                } catch (e: Exception) {

                                    sendLog(
                                        "Attr Read Warning: ${e.message}"
                                    )
                                }

                                val map =
                                    HashMap<String, Any>()

                                map["handle"] = handle

                                map["label"] =
                                    if (label.isEmpty())
                                        "Key (handle $handle)"
                                    else
                                        label

                                map["id"] = idHex

                                keyList.add(map)
                            }

                            if (found.size < 100) {
                                break
                            }
                        }

                        module.C_FindObjectsFinal(session)

                        /*
                         * RESOLVE CERTIFICATE HOLDER NAME (CN)
                         *
                         * The private key's CKA_LABEL is often a UUID
                         * (e.g. f05a86f3-...), not a human name. Build a
                         * catalog of ALL certificates on the token and
                         * map each key to its certificate, then use the
                         * certificate Subject CN as the display name:
                         *   1. match by CKA_ID    (key id    == cert id)
                         *   2. match by CKA_LABEL  (key label == cert label)
                         *   3. single-certificate fallback
                         *
                         * Some tokens give the certificate a different
                         * CKA_ID than the private key, so an id-only match
                         * leaves the UUID showing. Matching by label and
                         * the single-cert fallback recover the holder name.
                         */
                        val certs = listCertificates(module, session)

                        for (item in keyList) {

                            val keyId =
                                item["id"]?.toString() ?: ""

                            val keyLabel =
                                item["label"]?.toString() ?: ""

                            var cn = ""

                            // 1. match by CKA_ID
                            if (keyId.isNotEmpty()) {
                                cn = certs.firstOrNull {
                                    it.idHex.isNotEmpty() &&
                                        it.idHex.equals(keyId, ignoreCase = true)
                                }?.cn ?: ""
                            }

                            // 2. match by CKA_LABEL
                            if (cn.isEmpty() && keyLabel.isNotEmpty()) {
                                cn = certs.firstOrNull {
                                    it.label.isNotEmpty() &&
                                        it.label == keyLabel
                                }?.cn ?: ""
                            }

                            // 3. single-certificate fallback
                            if (cn.isEmpty() && certs.size == 1) {
                                cn = certs[0].cn
                            }

                            if (cn.isNotEmpty()) {
                                item["label"] = cn
                                sendLog(
                                    "Resolved holder name = $cn"
                                )
                            } else {
                                sendLog(
                                    "No certificate CN matched for key " +
                                        "(id=$keyId, label=$keyLabel)"
                                )
                            }
                        }

                        sendLog(
                            "Found ${keyList.size} private key(s)"
                        )

                        result.success(keyList)

                    } catch (e: Exception) {

                        sendLog(
                            "LIST_KEYS_ERROR: ${e.message}"
                        )

                        result.error(
                            "LIST_KEYS_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * SELECT KEY PAIR
                 * (use an existing private key for signing;
                 *  resolve the matching public key by CKA_ID
                 *  when available)
                 */
                "selectKeyPair" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {

                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        val handle =
                            (call.argument<Number>("handle"))
                                ?.toLong()
                                ?: throw Exception(
                                    "Key handle missing"
                                )

                        privateKeyHandle = handle
                        publicKeyHandle = 0

                        val idHex =
                            call.argument<String>("id") ?: ""

                        if (idHex.isNotEmpty()) {

                            try {

                                val idBytes =
                                    hexStringToByteArray(idHex)

                                val pubTemplate = arrayOf(
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_CLASS
                                        pValue = PKCS11Constants.CKO_PUBLIC_KEY
                                    },
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_ID
                                        pValue = idBytes
                                    }
                                )

                                module.C_FindObjectsInit(
                                    session,
                                    pubTemplate
                                )

                                val pub =
                                    module.C_FindObjects(
                                        session,
                                        1
                                    )

                                module.C_FindObjectsFinal(session)

                                if (pub != null &&
                                    pub.isNotEmpty()
                                ) {
                                    publicKeyHandle = pub[0]
                                }

                            } catch (e: Exception) {

                                sendLog(
                                    "Public Key Lookup Warning: ${e.message}"
                                )
                            }
                        }

                        sendLog(
                            "Selected Private Key Handle = $privateKeyHandle"
                        )

                        sendLog(
                            "Matched Public Key Handle = $publicKeyHandle"
                        )

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "SELECT_KEY_ERROR: ${e.message}"
                        )

                        result.error(
                            "SELECT_KEY_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * DELETE KEY PAIR
                 * (destroy the selected private key and its
                 *  matching public key, found by CKA_ID)
                 */
                "deleteKeyPair" -> {

                    try {
                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {
                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        val handle =
                            (call.argument<Number>("handle"))
                                ?.toLong()
                                ?: throw Exception(
                                    "Key handle missing"
                                )

                        val idHex =
                            call.argument<String>("id") ?: ""

                        /*
                         * DESTROY PRIVATE KEY
                         */
                        module.C_DestroyObject(
                            session,
                            handle
                        )

                        sendLog(
                            "Deleted Private Key Handle = $handle"
                        )

                        /*
                         * DESTROY MATCHING PUBLIC KEY(S)
                         */
                        if (idHex.isNotEmpty()) {

                            try {

                                val idBytes =
                                    hexStringToByteArray(idHex)

                                val pubTemplate = arrayOf(
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_CLASS
                                        pValue = PKCS11Constants.CKO_PUBLIC_KEY
                                    },
                                    CK_ATTRIBUTE().apply {
                                        type = PKCS11Constants.CKA_ID
                                        pValue = idBytes
                                    }
                                )

                                module.C_FindObjectsInit(
                                    session,
                                    pubTemplate
                                )

                                val pub =
                                    module.C_FindObjects(
                                        session,
                                        10
                                    )

                                module.C_FindObjectsFinal(session)

                                if (pub != null) {

                                    for (p in pub) {

                                        module.C_DestroyObject(
                                            session,
                                            p
                                        )

                                        sendLog(
                                            "Deleted Public Key Handle = $p"
                                        )
                                    }
                                }

                            } catch (e: Exception) {

                                sendLog(
                                    "Public Key Delete Warning: ${e.message}"
                                )
                            }
                        }

                        /*
                         * CLEAR STORED HANDLES IF DELETED
                         */
                        if (privateKeyHandle == handle) {
                            privateKeyHandle = 0
                            publicKeyHandle = 0
                        }

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "DELETE_KEY_ERROR: ${e.message}"
                        )

                        result.error(
                            "DELETE_KEY_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * SIGN DATA
                 */
                "signData" -> {

                    try {

                        val module = pkcs11Module
                            ?: throw Exception(
                                "PKCS11 Not Initialized"
                            )

                        if (session == 0L) {

                            throw Exception(
                                "Session Not Opened"
                            )
                        }

                        if (privateKeyHandle == 0L) {

                            throw Exception(
                                "Generate Keypair First"
                            )
                        }

                        /*
                         * GET HASHHEX FROM FLUTTER
                         */
                        val hashHex =
                            call.argument<String>(
                                "hashHex"
                            )

                        if (hashHex.isNullOrEmpty()) {

                            throw Exception(
                                "hashHex Empty"
                            )
                        }

                        sendLog(
                            "Received hashHex = $hashHex"
                        )

                        /*
                         * HEX STRING -> BYTE ARRAY
                         */
                        val data =
                            hexStringToByteArray(
                                hashHex
                            )

                        sendLog(
                            "Hash Byte Length = ${data.size}"
                        )

                        val mechanism =
                            CK_MECHANISM().apply {

                                mechanism =
                                    PKCS11Constants.CKM_SHA256_RSA_PKCS

                                pParameter = null
                            }

                        module.C_SignInit(
                            session,
                            mechanism,
                            privateKeyHandle
                        )

                        val signature =
                            module.C_Sign(
                                session,
                                data
                            )

                        val signatureHex =
                            signature.joinToString(" ") {
                                "%02X".format(it)
                            }

                        sendLog(
                            "Signature Generated"
                        )

                        result.success(signatureHex)

                    } catch (e: Exception) {

                        sendLog(
                            "SIGN_ERROR: ${e.message}"
                        )

                        result.error(
                            "SIGN_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * VERIFY
                 */
                "verifySignature" -> {

                    sendLog(
                        "verifySignature() called"
                    )

                    result.success(true)
                }

                /*
                 * LOGOUT
                 */
                "logout" -> {

                    try {

                        val module = pkcs11Module

                        if (module != null &&
                            session != 0L
                        ) {

                            module.C_Logout(session)

                            sendLog(
                                "Logout Successful"
                            )
                        }

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "LOGOUT_ERROR: ${e.message}"
                        )

                        result.error(
                            "LOGOUT_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                /*
                 * CLOSE SESSION
                 */
                "closeSession" -> {

                    try {

                        val module = pkcs11Module

                        if (module != null) {

                            if (session != 0L) {

                                try {

                                    module.C_CloseSession(
                                        session
                                    )

                                    sendLog(
                                        "Session Closed"
                                    )

                                } catch (e: Exception) {

                                    sendLog(
                                        "Close Session Warning: ${e.message}"
                                    )
                                }

                                session = 0
                            }

                            try {

                                module.C_Finalize(null)

                                sendLog(
                                    "PKCS11 Finalized"
                                )

                            } catch (e: Exception) {

                                sendLog(
                                    "Finalize Warning: ${e.message}"
                                )
                            }
                        }

                        pkcs11Module = null

                        privateKeyHandle = 0
                        publicKeyHandle = 0
                        slotId = -1

                        result.success(true)

                    } catch (e: Exception) {

                        sendLog(
                            "CLOSE_ERROR: ${e.message}"
                        )

                        result.error(
                            "CLOSE_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /*
     * HEX STRING TO BYTE ARRAY
     */
    private fun hexStringToByteArray(
        s: String
    ): ByteArray {

        val len = s.length

        val data =
            ByteArray(len / 2)

        var i = 0

        while (i < len) {

            data[i / 2] =
                (
                        (
                                Character.digit(
                                    s[i],
                                    16
                                ) shl 4
                                )
                                +
                                Character.digit(
                                    s[i + 1],
                                    16
                                )
                        ).toByte()

            i += 2
        }

        return data
    }

    /*
     * CERTIFICATE INFO READ FROM THE TOKEN
     */
    private data class CertInfo(
        val idHex: String,
        val label: String,
        val cn: String
    )

    /*
     * LIST ALL X.509 CERTIFICATES ON THE TOKEN
     * Reads each certificate's CKA_ID and CKA_LABEL, then
     * decodes its DER (CKA_VALUE) to extract the Subject
     * Common Name (holder name). Used to map a private key
     * to its human-readable certificate name.
     */
    private fun listCertificates(
        module: PKCS11,
        session: Long
    ): List<CertInfo> {

        val result = ArrayList<CertInfo>()

        val template = arrayOf(
            CK_ATTRIBUTE().apply {
                type = PKCS11Constants.CKA_CLASS
                pValue = PKCS11Constants.CKO_CERTIFICATE
            }
        )

        module.C_FindObjectsInit(session, template)

        try {

            while (true) {

                val found =
                    module.C_FindObjects(session, 100)

                if (found == null || found.isEmpty()) {
                    break
                }

                for (handle in found) {

                    var idHex = ""
                    var label = ""
                    var cn = ""

                    /*
                     * READ ID + LABEL
                     */
                    try {

                        val meta = arrayOf(
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_ID
                            },
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_LABEL
                            }
                        )

                        module.C_GetAttributeValue(
                            session,
                            handle,
                            meta
                        )

                        idHex =
                            (meta[0].pValue as? ByteArray)
                                ?.joinToString("") {
                                    "%02X".format(it)
                                } ?: ""

                        label =
                            (meta[1].pValue as? ByteArray)
                                ?.toString(Charsets.UTF_8)
                                ?.trim() ?: ""

                    } catch (e: Exception) {
                        sendLog("Cert Meta Warning: ${e.message}")
                    }

                    /*
                     * READ DER VALUE -> SUBJECT CN
                     */
                    try {

                        val valueAttr = arrayOf(
                            CK_ATTRIBUTE().apply {
                                type = PKCS11Constants.CKA_VALUE
                            }
                        )

                        module.C_GetAttributeValue(
                            session,
                            handle,
                            valueAttr
                        )

                        val der =
                            valueAttr[0].pValue as? ByteArray

                        if (der != null) {

                            val cert =
                                CertificateFactory
                                    .getInstance("X.509")
                                    .generateCertificate(
                                        ByteArrayInputStream(der)
                                    ) as X509Certificate

                            cn = extractCN(
                                cert.subjectX500Principal
                                    .getName(X500Principal.RFC2253)
                            )
                        }

                    } catch (e: Exception) {
                        sendLog("Cert Value Warning: ${e.message}")
                    }

                    result.add(CertInfo(idHex, label, cn))

                    sendLog(
                        "Cert found: id=$idHex label=$label cn=$cn"
                    )
                }

                if (found.size < 100) {
                    break
                }
            }

        } finally {
            module.C_FindObjectsFinal(session)
        }

        return result
    }

    /*
     * EXTRACT CN FROM AN RFC2253 SUBJECT DN
     * Honours backslash-escaped characters inside
     * attribute values (e.g. escaped commas).
     */
    private fun extractCN(dn: String): String {

        var i = 0
        val n = dn.length

        while (i < n) {

            val typeStart = i

            while (i < n && dn[i] != '=') {
                i++
            }

            val type =
                dn.substring(typeStart, i).trim()

            if (i < n) {
                i++ // skip '='
            }

            val sb = StringBuilder()

            while (i < n && dn[i] != ',') {

                if (dn[i] == '\\' && i + 1 < n) {
                    sb.append(dn[i + 1])
                    i += 2
                } else {
                    sb.append(dn[i])
                    i++
                }
            }

            if (i < n) {
                i++ // skip ','
            }

            if (type.equals("CN", ignoreCase = true)) {
                return sb.toString().trim()
            }
        }

        return ""
    }

    /*
     * SAFE LOGGER
     */
    private fun sendLog(message: String) {

        Log.d(TAG, message)

        try {

            runOnUiThread {

                try {

                    if (::methodChannel.isInitialized) {

                        methodChannel.invokeMethod(
                            "nativeLog",
                            "[ANDROID] $message"
                        )
                    }

                } catch (e: Exception) {

                    Log.e(
                        TAG,
                        "Flutter Log Error",
                        e
                    )
                }
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "sendLog Error",
                e
            )
        }
    }

    /*
     * INITIALIZE LIBRARY
     */
    private fun initializeLibrary() {

        try {

            sendLog(
                "initializeLibrary() started"
            )

            if (pkcs11Module != null) {

                sendLog(
                    "PKCS11 Already Initialized"
                )

                return
            }

            PKCS11Implementation
                .setApplicationContext(this)

            sendLog(
                "Application Context Set"
            )

            val usbManager =
                getSystemService(
                    USB_SERVICE
                ) as UsbManager

            val devices =
                usbManager.deviceList

            sendLog(
                "USB Device Count = ${devices.size}"
            )

            if (devices.isEmpty()) {

                throw Exception(
                    "No USB Token Connected"
                )
            }

            for (device in devices.values) {

                sendLog(
                    "Vendor=${device.vendorId}, Product=${device.productId}, Name=${device.deviceName}"
                )
            }

            try {

                val usbHandler =
                    USBHandler.getInstance(this)

                usbHandler.checkAndRequestPermission()

                sendLog(
                    "USB Permission Requested"
                )

                Thread.sleep(3000)

                sendLog(
                    "USB Permission Wait Completed"
                )

            } catch (e: Exception) {

                sendLog(
                    "USB_PERMISSION_ERROR: ${e.message}"
                )
            }

            val libPath =
                applicationContext
                    .applicationInfo
                    .nativeLibraryDir +
                        "/libInnaITPKCS11.so"

            sendLog(
                "PKCS11 Path = $libPath"
            )

            pkcs11Module =
                PKCS11Connector
                    .connectToPKCS11Module(
                        libPath
                    )

            if (pkcs11Module == null) {

                throw Exception(
                    "Failed To Load PKCS11"
                )
            }

            sendLog(
                "PKCS11 Module Connected"
            )

            Toast.makeText(
                this,
                "PKCS11 Loaded",
                Toast.LENGTH_SHORT
            ).show()

        } catch (e: Exception) {

            sendLog(
                "PKCS11_LOAD_ERROR: ${e.message}"
            )

            Log.e(
                TAG,
                "initializeLibrary Error",
                e
            )

            throw e
        }
    }
}