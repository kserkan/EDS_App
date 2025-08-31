# EDS Takip Uygulaması

Bu proje, Flutter ile geliştirilmiş, araç içi bilgi eğlence sistemleri (Android Auto) için tasarlanmış bir hız takip uygulamasıdır. Uygulama, kullanıcının anlık hızını gösterir ve mini ekran (Picture-in-Picture) özelliği sayesinde diğer uygulamalarla birlikte kullanılabilir.

---

### Özellikler

- **Android Auto Desteği:** Araç içi ekranlar için optimize edilmiş kullanıcı arayüzü sunar.
- **Anlık Hız Takibi:** Gerçek zamanlı hız verilerini gösterir (Bu özellik için sensör entegrasyonu gereklidir).
- **Mini Ekran (Picture-in-Picture - PiP):** Uygulamayı küçük bir pencerede, diğer uygulamaların üzerinde çalıştırabilme.

---

### Ekran Görüntüleri

Bu bölümde uygulamanızın ekran görüntülerini ekleyebilirsiniz.

| Ana Ekran (Mobil) | Ana Ekran (Android Auto) |
|:---:|:---:|
| ![Ana Ekran Mobil](https://placehold.co/400x800) | ![Ana Ekran Araba](https://placehold.co/800x400) |
| PiP Modunda Uygulama | |
| ![PiP Modu](https://placehold.co/400x800) | |

---

### Kurulum

Bu projeyi yerel makinenizde çalıştırmak için aşağıdaki adımları izleyin.

#### Ön Gereksinimler

- Flutter SDK (Sürüm 3.19.0 veya üzeri önerilir)
- Android Studio
- JDK (Java Development Kit) 11 veya 17 (Ortam değişkenlerinin ayarlandığından emin olun)

#### Projeyi Klonlama

```bash
git clone [https://github.com/KULLANICI_ADINIZ/eds_app.git](https://github.com/KULLANICI_ADINIZ/eds_app.git)
cd eds_app
Bağımlılıkları Yükleme
Projenin kök dizininde, bağımlılıkları yüklemek için aşağıdaki komutu çalıştırın:

Bash

flutter pub get
Uygulamayı Çalıştırma
Projeyi standart bir Android cihazda çalıştırmak için:

Bash

flutter run
Android Auto emulatoründe çalıştırmak için, Android Auto geliştirici kılavuzunu takip ederek sanal bir araç birimi oluşturmanız gerekir.

Kullanılan Teknolojiler
Flutter - Uygulama geliştirme framework'ü

Kotlin - Android yerel kodu için

Android Auto - Araç içi ekran desteği için

androidx.car.app:app:1.6.0-beta01 - Android Auto kütüphanesi

com.android.tools:desugar_jdk_libs:2.1.4 - Java 8+ özellikleri için desugaring kütüphanesi

Lisans
Bu proje MIT Lisansı ile lisanslanmıştır. Daha fazla bilgi için LICENSE dosyasına bakın.
