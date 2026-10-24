# shared_preferences_android 2.5.1 and JNI look up these Kotlin types by name.
# Preserve their names and method signatures in optimized release builds.
# See https://github.com/flutter/flutter/issues/194649
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
