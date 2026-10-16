package app.ridescope.ridescope

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Bluetooth Classic serial (RFCOMM / SPP) link to an OBD adapter.
 * Dart side: lib/core/transport/spp_transport.dart.
 */
class SppPlugin(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val methods = MethodChannel(messenger, "app.ridescope/spp")
    private val events = EventChannel(messenger, "app.ridescope/spp/data")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var socket: BluetoothSocket? = null
    private var sink: EventChannel.EventSink? = null
    private var reader: Thread? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bondedDevices" -> {
                try {
                    val list = adapter?.bondedDevices?.map {
                        mapOf("name" to (it.name ?: it.address), "address" to it.address)
                    } ?: emptyList()
                    result.success(list)
                } catch (e: SecurityException) {
                    result.error("permission", "Bluetooth permission missing", null)
                }
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("args", "address missing", null)
                    return
                }
                io.execute { connect(address, result) }
            }
            "write" -> {
                val data = call.argument<ByteArray>("data")
                val s = socket
                if (data == null || s == null) {
                    result.error("state", "Not connected", null)
                    return
                }
                io.execute {
                    try {
                        s.outputStream.write(data)
                        s.outputStream.flush()
                        main.post { result.success(null) }
                    } catch (e: IOException) {
                        main.post { result.error("io", e.message, null) }
                    }
                }
            }
            "disconnect" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        close()
        val bt = adapter
        if (bt == null || !bt.isEnabled) {
            main.post { result.error("off", "Bluetooth is off", null) }
            return
        }
        try {
            bt.cancelDiscovery()
            val device = bt.getRemoteDevice(address)
            val s = try {
                device.createRfcommSocketToServiceRecord(sppUuid).also { it.connect() }
            } catch (first: IOException) {
                // Some clone adapters only accept the insecure variant.
                device.createInsecureRfcommSocketToServiceRecord(sppUuid).also { it.connect() }
            }
            socket = s
            startReader(s)
            main.post { result.success(null) }
        } catch (e: Exception) {
            close()
            main.post { result.error("connect", e.message ?: "connection failed", null) }
        }
    }

    private fun startReader(s: BluetoothSocket) {
        reader = Thread {
            val buf = ByteArray(1024)
            try {
                while (true) {
                    val n = s.inputStream.read(buf)
                    if (n < 0) break
                    val chunk = buf.copyOf(n)
                    main.post { sink?.success(chunk) }
                }
            } catch (_: IOException) {
                // Socket closed.
            }
            main.post { sink?.error("closed", "Adapter disconnected", null) }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun close() {
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        socket = null
        reader = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
