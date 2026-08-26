# Firebase
# Firebase artifacts ship consumer ProGuard rules. Do not blanket-keep the
# whole Firebase tree, or R8 cannot shrink/optimize those dependencies.
-dontwarn com.google.firebase.**

# MLKit (pulled in transitively by the cunning_document_scanner plugin via
# the play-services-mlkit-document-scanner dependency forced in the root
# build.gradle)
# MLKit also ships consumer rules through Google Play Services artifacts.
-dontwarn com.google.mlkit.**

# Google Play Services
-dontwarn com.google.android.gms.**
