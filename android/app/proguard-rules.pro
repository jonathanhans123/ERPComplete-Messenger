# Keep generic signatures (Gson TypeToken) and plugin classes.
# Without this, flutter_local_notifications crashes in release builds with:
# "TypeToken must be created with a type argument ... make sure that generic
# signatures are preserved."
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keep class com.dexterous.flutterlocalnotifications.** { *; }
