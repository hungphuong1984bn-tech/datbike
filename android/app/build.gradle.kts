import java.util.Properties

plugins {
    id("com.android.application")

    id("dev.flutter.flutter-gradle-plugin")
}

// ── Ký bản Release ──────────────────────────────────────────────────────────
// Thông tin khóa đọc từ android/key.properties (KHÔNG đưa vào Git) gồm:
//   storeFile=release.jks   (đường dẫn tương đối so với android/app)
//   storePassword=...  keyAlias=...  keyPassword=...
// CI tạo file này từ GitHub Secrets (xem docs/RELEASE_SIGNING.md).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keyProps.getProperty(it).isNullOrBlank() }
// CI đặt THBIKE_REQUIRE_RELEASE_SIGNING=true: thiếu khóa thì build Release THẤT BẠI,
// không bao giờ lặng lẽ ký bằng debug key.
val requireReleaseKey = System.getenv("THBIKE_REQUIRE_RELEASE_SIGNING") == "true"

android {
    namespace = "vn.mybike.mybike_app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {

        applicationId = "vn.mybike.mybike_app"

        minSdk = 26
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                requireReleaseKey -> throw GradleException(
                    "Thiếu android/key.properties: không được ký Release bằng debug key trong CI."
                )
                else -> {
                    logger.warn(
                        "CẢNH BÁO: không có android/key.properties — Release ký bằng debug key " +
                            "(chỉ dùng thử trên máy dev, KHÔNG phát hành)."
                    )
                    signingConfigs.getByName("debug")
                }
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
