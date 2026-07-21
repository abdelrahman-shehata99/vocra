plugins {
    id("com.android.library")
    // No `org.jetbrains.kotlin.android` here — relies on Flutter's
    // built-in Kotlin support (Flutter >=3.44.0, this package's floor).
}

group = "com.vocra.voice_flutter"
version = "0.2.1"

android {
    namespace = "com.vocra.voice_flutter"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
