package com.example.eds_app

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator

// Android Auto'nun uygulamanızla iletişim kurmasını sağlayan ana servis
class MyCarAppService : CarAppService() {
    override fun onCreateSession(): androidx.car.app.Session {
        return MyCarSession()
    }

    // Android Auto host'unun uygulamanızı çalıştırmasına izin veren metot
    override fun createHostValidator(): HostValidator {
        // Şimdilik test için tüm hostlara izin verelim
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    inner class MyCarSession : androidx.car.app.Session() {
        override fun onCreateScreen(intent: Intent): Screen {
            return MainScreen(carContext)
        }
    }
}

// Araç ekranında gösterilecek ana ekran
class MainScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val speed = 85

        val pane = Pane.Builder()
            .addRow(
                Row.Builder()
                    .setTitle("Anlık Hız")
                    .addText("$speed km/s")
                    .build()
            )
            .build()

        return PaneTemplate.Builder(pane)
            .setTitle("EDS Takip")
            .setHeaderAction(Action.APP_ICON)
            .build()
    }
}
