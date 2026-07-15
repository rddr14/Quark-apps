package com.quarkgps

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.location.LocationManager
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.WebSettings
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowCompat

class MainActivity : AppCompatActivity() {
    private var site: String? = null

    private lateinit var webView: WebView
    private lateinit var locationManager: LocationManager
    private val LOCATION_PERMISSION_REQUEST_CODE = 123
    private var pendingGeoOrigin: String? = null
    private var pendingGeoCallback: GeolocationPermissions.Callback? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        supportActionBar?.hide()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        site = getString(R.string.string_site)
        setContentView(R.layout.activity_main)
        configureSystemBarsForTheme()

        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Inicialização da WebView logo após a definição do layout
        webView = findViewById(R.id.webView)

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.acceptCookie()

        // da WebView seja sobreposto pela barra de status
        ViewCompat.setOnApplyWindowInsetsListener(webView) { view, windowInsets ->
            val insets = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(insets.left, insets.top, insets.right, insets.bottom)
            windowInsets
        }


        webView.settings.javaScriptEnabled = true
        webView.settings.setGeolocationEnabled(true)
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.setSupportMultipleWindows(true)
        webView.settings.allowContentAccess = true
        webView.settings.allowFileAccess = false
        webView.settings.saveFormData = true
        webView.settings.cacheMode = WebSettings.LOAD_DEFAULT

//        webView.loadUrl(site!!)

        webView.webChromeClient = object : WebChromeClient() {
            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?
            ) {
                if (checkLocationPermission()) {
                    callback?.invoke(origin, true, false)
                } else {
                    pendingGeoOrigin = origin
                    pendingGeoCallback = callback
                    requestLocationPermission()
                }
            }

            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                consoleMessage?.let { message ->
                    if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                        Log.w(
                            "WebViewConsole",
                            "Erro Javascript: ${message.message()} source: ${message.sourceId()} line: ${message.lineNumber()}"
                        )
                        // **Removido 'return true' para não ignorar tratamento padrão de erros JS**
                    } else {
                        Log.d(
                            "WebViewConsole",
                            "${message.messageLevel()}: ${message.message()} source: ${message.sourceId()} line: ${message.lineNumber()}"
                        )
                    }
                }
                return super.onConsoleMessage(consoleMessage)
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                // Geolocalização para sites no WebView é tratada por onGeolocationPermissionsShowPrompt.
                // Nega outros tipos de permissão por segurança.
                request?.deny()
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: SslError?
            ) {
                Log.w("WebViewSSL", "SSL Error: $error, Connection blocked for security.")
                handler?.cancel() // **Tratamento seguro: Cancelar conexão em erro SSL**
            }

            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                if (url != null && !url.startsWith(site!!)) {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    startActivity(intent)
                    return true
                }
                return false
            }
            // ... other WebViewClient methods ...
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            cookieManager.setAcceptThirdPartyCookies(webView, true)
        }

        webView.loadUrl(site!!)

        if (checkLocationPermission()) {
            getLocation()
        } else {
            requestLocationPermission()
        }
    }

    private fun configureSystemBarsForTheme() {
        val insetsController = WindowCompat.getInsetsController(window, window.decorView)
        
        // Verifica se o modo noturno (tema escuro) está ativo no dispositivo
        val isNightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

        if (isNightMode) {
            // Tema Escuro: Fundo preto, texto/ícones claros (brancos)
            window.statusBarColor = Color.BLACK
            window.navigationBarColor = Color.BLACK
            insetsController.isAppearanceLightStatusBars = false
            insetsController.isAppearanceLightNavigationBars = false
        } else {
            // Tema Claro: Fundo branco, texto/ícones escuros (pretos)
            window.statusBarColor = Color.WHITE
            window.navigationBarColor = Color.WHITE
            insetsController.isAppearanceLightStatusBars = true
            insetsController.isAppearanceLightNavigationBars = true
        }
    }


    @SuppressLint("MissingPermission")
    private fun getLocation() {
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val location =
            locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)

        location?.let {
            val latitude = it.latitude
            val longitude = it.longitude
            Log.d("LocationDebug", "Latitude: $latitude, Longitude: $longitude")

            val jsCode =
                "navigator.geolocation.getCurrentPosition = function(success, error, options) { " +
                        "   var position = { coords: { latitude: $latitude, longitude: $longitude }, timestamp: Date.now() };" +
                        "   success(position);" +
                        "}"
            webView.evaluateJavascript(jsCode, null)

        } ?: run {
            Log.d("LocationDebug", "Localização não encontrada")
            // Lidar com o caso em que a localização não foi obtida
        }
    }

    private fun checkLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                pendingGeoCallback?.invoke(pendingGeoOrigin, true, false)
                pendingGeoOrigin = null
                pendingGeoCallback = null
                getLocation()
            } else {
                pendingGeoCallback?.invoke(pendingGeoOrigin, false, false)
                pendingGeoOrigin = null
                pendingGeoCallback = null
                Log.d("LocationDebug", "Permissão de localização negada")
            }
        }
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }
}