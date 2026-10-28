# shared_preferences_android 2.5.0/2.5.1: R8 đổi tên các class Kotlin coroutine
# khiến JNI lookup theo tên (getAll với Continuation) fail ở release build —
# NoSuchMethodError SharedPreferencesApiRegistrar.getAll, flutter/flutter#194649.
# Đã fix chính thức bằng plugin 2.5.2 (PR flutter/packages#13311); giữ các
# keep rule này để chắc chắn với mọi cấu hình R8/AGP.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
