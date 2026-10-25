package com.pendatkill.my_radar

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal "myradar/red":
 *  - usarWifi / soltarWifi: la red "MyRadar" no tiene internet y Android manda el
 *    tráfico por datos móviles; se fija la app a la WiFi mientras dure la conexión.
 *  - multicast: algunos móviles descartan difusiones UDP sin este bloqueo.
 */
class MainActivity : FlutterActivity() {
    private var bloqueoMulticast: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myradar/red")
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                when (call.method) {
                    "usarWifi" -> {
                        @Suppress("DEPRECATION")
                        val wifi = cm.allNetworks.firstOrNull {
                            cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        }
                        result.success(wifi != null && cm.bindProcessToNetwork(wifi))
                    }
                    "soltarWifi" -> result.success(cm.bindProcessToNetwork(null))
                    "multicast" -> {
                        val activar = call.arguments as? Boolean ?: false
                        if (activar && bloqueoMulticast == null) {
                            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            bloqueoMulticast = wm.createMulticastLock("myradar").apply {
                                setReferenceCounted(false); acquire()
                            }
                        } else if (!activar) {
                            bloqueoMulticast?.release(); bloqueoMulticast = null
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
