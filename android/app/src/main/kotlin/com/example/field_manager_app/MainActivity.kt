package com.example.field_manager_app.v2
// ⚠️ 맨 윗줄의 package com.example... 부분은 절대 지우지 말고 본인 것을 유지하세요!

import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.SystemClock
import android.os.Handler       // ⭐ 공식 타이머로 변경
import android.os.Looper        // ⭐ 공식 타이머로 변경
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app.mock.location"
    private val NATIVE_MAP_COMMAND_CHANNEL = "field_manager/native_kakao_map_commands"
    private val NATIVE_MAP_EVENT_CHANNEL = "field_manager/native_kakao_map_events"
    private var mockHandler: Handler? = null     // ⭐ 시스템 친화적 타이머
    private var mockRunnable: Runnable? = null   // ⭐ 시스템 친화적 작업

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                NativeKakaoMapViewFactory.VIEW_TYPE,
                NativeKakaoMapViewFactory()
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_MAP_COMMAND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "renderMarkers" -> {
                    NativeKakaoMapRegistry.renderMarkers(call.arguments)
                    result.success(null)
                }
                "renderLines" -> {
                    NativeKakaoMapRegistry.renderLines(call.arguments)
                    result.success(null)
                }
                "clearMarkers" -> {
                    NativeKakaoMapRegistry.clearMarkers()
                    result.success(null)
                }
                "moveTo" -> {
                    NativeKakaoMapRegistry.moveTo(call.arguments)
                    result.success(null)
                }
                "showCurrentLocation" -> {
                    NativeKakaoMapRegistry.showCurrentLocation(call.arguments)
                    result.success(null)
                }
                "clearCurrentLocation" -> {
                    NativeKakaoMapRegistry.clearCurrentLocation()
                    result.success(null)
                }
                "setShowAllLineLabels" -> {
                    NativeKakaoMapRegistry.setShowAllLineLabels(call.arguments)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        NativeKakaoMapRegistry.setEventChannel(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_MAP_EVENT_CHANNEL))

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startMockLocation") {
                val lat = call.argument<Double>("lat")
                val lng = call.argument<Double>("lng")
                if (lat != null && lng != null) {
                    try {
                        setMockLocation(lat, lng)
                        result.success("Mock Location Set")
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", "개발자 옵션 확인 필요", null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
            } else if (call.method == "stopMockLocation") {
                stopMockLocation()
                result.success("Mock Location Stopped")
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        NativeKakaoMapRegistry.resumeAll()
    }

    override fun onPause() {
        NativeKakaoMapRegistry.pauseAll()
        super.onPause()
    }

    override fun onDestroy() {
        NativeKakaoMapRegistry.finishAll()
        super.onDestroy()
    }

    private fun setMockLocation(lat: Double, lng: Double) {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = arrayOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)

        // 1. 기존 타이머가 돌고 있다면 안전하게 멈춤
        mockRunnable?.let { mockHandler?.removeCallbacks(it) }

        // 2. 가짜 GPS 채널 열기
        for (provider in providers) {
            try { locationManager.removeTestProvider(provider) } catch (e: Throwable) {}
            try {
                // 정확도 설정(1, 1) 유지
                locationManager.addTestProvider(provider, false, false, false, false, true, true, true, 1, 1)
                locationManager.setTestProviderEnabled(provider, true)
            } catch (e: SecurityException) {
                throw e
            } catch (e: Throwable) {}
        }

        // ⭐ 3. 안전망(Looper)이 장착된 메인 스레드에서 1초마다 무한 발사!
        mockHandler = Handler(Looper.getMainLooper())
        mockRunnable = object : Runnable {
            override fun run() {
                for (provider in providers) {
                    try {
                        val mockLocation = Location(provider)
                        mockLocation.latitude = lat
                        mockLocation.longitude = lng
                        mockLocation.accuracy = 1f
                        mockLocation.time = System.currentTimeMillis()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                            mockLocation.elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                        }
                        locationManager.setTestProviderLocation(provider, mockLocation)
                    } catch (e: Throwable) {
                        // 시스템 튕김 방지를 위해 모든 에러 흡수
                    }
                }
                // 1초(1000ms) 뒤에 자기 자신을 다시 호출 (무한 루프)
                mockHandler?.postDelayed(this, 1000)
            }
        }
        
        // 타이머 엔진 가동
        mockHandler?.post(mockRunnable!!)
    }

    private fun stopMockLocation() {
        // 1. 타이머 엔진 안전하게 정지
        mockRunnable?.let { mockHandler?.removeCallbacks(it) }
        mockHandler = null
        mockRunnable = null

        // 2. 채널 닫기
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = arrayOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        for (provider in providers) {
            try { locationManager.removeTestProvider(provider) } catch (e: Throwable) {}
        }
    }
}
