package com.example.field_manager_app.v2

import android.util.Log
import com.kakao.vectormap.KakaoMapSdk
import io.flutter.app.FlutterApplication

class FieldManagerApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        val appKey = BuildConfig.KAKAO_NATIVE_APP_KEY
        if (appKey.isBlank()) {
            Log.w(
                NativeKakaoMapRegistry.LOG_TAG,
                "KAKAO_NATIVE_APP_KEY is missing in android/local.properties; native Kakao map auth will not start."
            )
            return
        }

        KakaoMapSdk.init(this, appKey)
        Log.d(NativeKakaoMapRegistry.LOG_TAG, "KakaoMapSdk initialized with local native app key.")
    }
}
