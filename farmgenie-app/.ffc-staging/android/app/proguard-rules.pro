# shared_preferences_android 2.5.1 and JNI look up these Kotlin types by name.
# Preserve their names and method signatures in optimized release builds.
# See https://github.com/flutter/flutter/issues/194649
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }

# ML Kit face detection. vision-common ships no consumer rules, and R8 broke
# its internal component lookup: every camera frame failed in
# InputImage.fromByteArray with a NullPointerException ("The face scan could
# not run") in release builds only; debug builds worked.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }

# ONNX Runtime JNI resolves Java classes, constructors and members by name.
# Without this, R8 renames TensorInfo/OnnxJavaType and inference aborts the
# process in convertToTensorInfo (JNI GetMethodID: java_class == null).
-keep class ai.onnxruntime.** { *; }
