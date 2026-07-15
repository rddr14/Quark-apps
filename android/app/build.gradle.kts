import java.io.FileInputStream
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val keystorePath = System.getenv("CM_KEYSTORE_PATH")
val keystoreAlias = System.getenv("CM_KEY_ALIAS") ?: System.getenv("CM_KEYSTORE_ALIAS")
val keystorePassword = System.getenv("CM_KEYSTORE_PASSWORD")
val keyAliasPassword = System.getenv("CM_KEY_PASSWORD")
val ciBuildNumber = System.getenv("BUILD_NUMBER")?.toIntOrNull()
val enableMinify = System.getenv("ANDROID_ENABLE_MINIFY") == "true"
val repoRoot = rootProject.projectDir.parentFile

data class BrandingConfig(
    val key: String,
    val appName: String,
    val siteURL: String,
    val allowedHost: String,
    val androidApplicationId: String,
    val androidVersionCode: Int,
    val androidVersionName: String,
)

fun loadBrandingConfig(brandingKey: String): BrandingConfig {
    val brandingFile = repoRoot.resolve("branding/$brandingKey/Branding.properties")
    if (!brandingFile.isFile) {
        throw GradleException("Branding file not found: ${brandingFile.absolutePath}")
    }

    val properties = Properties()
    FileInputStream(brandingFile).use { input ->
        properties.load(input)
    }

    fun resolvePlaceholders(value: String): String {
        val placeholderRegex = Regex("\\$\\{([^}]+)}")
        var resolved = value

        repeat(10) {
            val next = placeholderRegex.replace(resolved) { match ->
                val propertyName = match.groupValues[1]
                properties.getProperty(propertyName)?.trim()
                    ?: throw GradleException(
                        "Unknown placeholder '$propertyName' in ${brandingFile.absolutePath}"
                    )
            }

            if (next == resolved) {
                return@repeat
            }
            resolved = next
        }

        if (placeholderRegex.containsMatchIn(resolved)) {
            throw GradleException(
                "Unresolved placeholders in branding value '$value' from ${brandingFile.absolutePath}"
            )
        }

        return resolved
    }

    fun required(name: String): String {
        val rawValue = properties.getProperty(name)?.trim().orEmpty()
        if (rawValue.isBlank()) {
            throw GradleException("Missing '$name' in ${brandingFile.absolutePath}")
        }

        val resolvedValue = resolvePlaceholders(rawValue)
        if (resolvedValue.isBlank()) {
            throw GradleException("Missing '$name' in ${brandingFile.absolutePath}")
        }

        return resolvedValue
    }

    return BrandingConfig(
        key = required("key"),
        appName = required("appName"),
        siteURL = required("siteURL"),
        allowedHost = required("allowedHost"),
        androidApplicationId = required("androidApplicationId"),
        androidVersionCode = required("androidVersionCode").toIntOrNull()
            ?: throw GradleException("Invalid 'androidVersionCode' in ${brandingFile.absolutePath}"),
        androidVersionName = required("androidVersionName")
    )
}

val quarkBranding = loadBrandingConfig("quarkgps")
val auraBranding = loadBrandingConfig("auramonitoramento")
val rmBranding = loadBrandingConfig("rmrastreadores")
val atualizasomBranding = loadBrandingConfig("atualizasom")
val trackergpsrastreamentoBranding = loadBrandingConfig("trackergpsrastreamento")

val hasReleaseSigning = !keystorePath.isNullOrBlank() &&
    !keystoreAlias.isNullOrBlank() &&
    !keystorePassword.isNullOrBlank() &&
    !keyAliasPassword.isNullOrBlank()

if (System.getenv("CI") == "true" && !hasReleaseSigning) {
    throw GradleException(
        "Android release signing variables are missing in CI. " +
            "Check android_signing keystore reference in codemagic.yaml."
    )
}

android {
    namespace = "com.quarkgps"
    compileSdk = 34

    flavorDimensions += "brand"

    defaultConfig {
        applicationId = quarkBranding.androidApplicationId
        minSdk = 28
        targetSdk = 36
        versionCode = quarkBranding.androidVersionCode
        versionName = quarkBranding.androidVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    productFlavors {
        create("quark") {
            dimension = "brand"
            applicationId = quarkBranding.androidApplicationId
            versionCode = quarkBranding.androidVersionCode
            versionName = quarkBranding.androidVersionName
            resValue("string", "app_name", quarkBranding.appName)
            resValue("string", "string_site", quarkBranding.siteURL)
        }

        create("aura") {
            dimension = "brand"
            applicationId = auraBranding.androidApplicationId
            versionCode = auraBranding.androidVersionCode
            versionName = auraBranding.androidVersionName
            resValue("string", "app_name", auraBranding.appName)
            resValue("string", "string_site", auraBranding.siteURL)
        }

        create("rm") {
            dimension = "brand"
            applicationId = rmBranding.androidApplicationId
            versionCode = rmBranding.androidVersionCode
            versionName = rmBranding.androidVersionName
            resValue("string", "app_name", rmBranding.appName)
            resValue("string", "string_site", rmBranding.siteURL)
        }

        create("atualizasom") {
            dimension = "brand"
            applicationId = atualizasomBranding.androidApplicationId
            versionCode = atualizasomBranding.androidVersionCode
            versionName = atualizasomBranding.androidVersionName
            resValue("string", "app_name", atualizasomBranding.appName)
            resValue("string", "string_site", atualizasomBranding.siteURL)
        }

        create("trackergpsrastreamento") {
            dimension = "brand"
            applicationId = trackergpsrastreamentoBranding.androidApplicationId
            versionCode = trackergpsrastreamentoBranding.androidVersionCode
            versionName = trackergpsrastreamentoBranding.androidVersionName
            resValue("string", "app_name", trackergpsrastreamentoBranding.appName)
            resValue("string", "string_site", trackergpsrastreamentoBranding.siteURL)
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = keystoreAlias
                keyPassword = keyAliasPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = enableMinify
            isShrinkResources = enableMinify
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}


dependencies {

    implementation(libs.androidx.core.ktx.v1120)
    implementation(libs.androidx.appcompat.v170alpha03)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)

    // Dependência para WebView
    implementation(libs.androidx.webkit)

    // Dependências para Localização (Google Play Services Location)
    implementation(libs.play.services.location)

    // Dependências do Jetpack Compose
    implementation(platform(libs.androidx.compose.bom.v20240200))
    implementation(libs.ui)
    implementation(libs.ui.graphics)
    implementation(libs.material3)


    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit.v115)
    androidTestImplementation(libs.androidx.espresso.core.v351)

}