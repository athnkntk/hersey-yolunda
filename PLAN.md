# Herşey Yolunda — Ürün ve Geliştirme Planı

- Plan sürümü: 1.5
- Oluşturulma tarihi: 15 Eylül 2026
- Hedef platform: iOS
- Durum: Canlıya çıkış (Render) için kod hazır; `gh auth login` ve Render Blueprint kullanıcı adımları bekleniyor. Proje artık `~/Herşey Yolunda` (iCloud dışı).
- Çalışma biçimi: Bu dosya kapsam, kararlar, uygulama sırası ve kabul kriterleri için ana referanstır.
- Marka yazımı: Kullanıcının tercihiyle “Herşey Yolunda”. Normal Türkçe yazımı “Her Şey Yolunda”dır; mağaza ve görsel kimlikte kullanılacak nihai yazım geliştirme öncesi teyit edilecektir.

## Güncel karar — Telefon/SMS'siz hesap (v1.2)

Kullanıcı onayıyla giriş modeli revize edildi: Ad + kullanım tercihi → rastgele hesap ID'si → Keychain'de cihaz oturumu. Aynı isim ayrı hesaplar oluşturur; isim veya hesap ID'si giriş yetkisi vermez. Telefon/OTP yeni kayıt için kaldırılır; eski kayıt ve aktif oturumlar migration ile korunur.

Eşleşme, kalıcı hesap ID'sini yazmak yerine 48 saatlik tek kullanımlı davet bağlantısı, QR veya 12 karakterli okunabilir kodla yapılır. Sahip onayı değişmez. QR üretimi için uygulama kamera izni istemez; okutma diğer telefonun kamera/QR uygulamasıyla yapılır. Mevcut özel URL şeması uygulama yüklüyken çalışır; doğrulanmış HTTPS domain/Universal Links ve yükleme sonrası devam akışı henüz açık iştir.

Apple ile hesap koruma isteğe bağlı sonraki entegrasyondur; bu revizyonda çalışıyor gibi bir düğme sunulmaz. Oturum/telefon kaybında veya çıkışta, kurtarma yöntemi bağlanmadıysa yeni hesap ve yeniden aile onayı gerektiği açıkça gösterilir. Otomatik ID eşleşmesi hesap devralma anlamına gelmez.

Önceki doğrulama kayıtlarındaki OTP testleri tarihsel kayıttır; aşağıdaki güncel sprint, API ve güvenlik maddeleri bu revizyonu esas alır.

## 1. Ürün özeti

> Yaşlı kişi tek dokunuşla iyi olduğunu söyler, ailesi de günlük haberini alır.

Herşey Yolunda, yaşlı veya yalnız yaşayan bir kişinin bilinçli bir dokunuşla günlük “Ben iyiyim” bilgisini yetkilendirdiği yakınlarına iletmesini sağlayan iOS uygulamasıdır.

### Değer önerisi

> Yakınını takip etmek değil, iyi olduğunu bilmek.

- Check-in kullanıcısı: “İzlenmeden aileme kolayca haber veriyorum.”
- Yakın: “Bugün kendisi haber verdi; haber gelmezse makul bir süre sonra bilgilendiriliyorum.”
- Marka, kişinin sağlık veya güvenlik durumuna ilişkin sistem garantisi olarak kullanılmaz.

### Ürün sınırları

- GPS takip uygulaması değildir.
- Sağlık teşhisi veya sağlık izleme uygulaması değildir.
- Acil yardım merkezi değildir.
- Telefon hareketinden, ekran açılmasından veya şarjdan otomatik check-in üretmez.
- Aile görüşmelerinin yerine geçmez.
- Bildirimlerin kesin veya anında görülmesini garanti etmez.

Görünür açıklama:

> Bu uygulama acil yardım veya tıbbi müdahale hizmeti değildir.

## 2. Başarı tanımı

İlk hedef, çok özellik sunmak değil, küçük bir aile kohortunda günlük davranışın dört hafta boyunca sürdürülebildiğini göstermektir.

### Aktivasyon

Bir aile aşağıdaki adımlar tamamlandığında aktive olmuş sayılır:

1. Check-in kullanıcısı hesabını ve programını oluşturur.
2. En az bir yakın açıkça yetkilendirilir.
3. İlk gerçek check-in backend'e kaydedilir.
4. Yakın, güncel durumu uygulamada görüntüleyebilir.

### Ana KPI

Daily successful check-in rate:

`Yerel gün kapanmadan başarılı check-in bulunan uygun profil-gün / check-in beklenen uygun profil-gün`

Uygun profil-gün: kurulumu tamamlanmış, programı etkin, en az bir aktif yetkili yakını bulunan ve o gün kontrolü duraklatılmamış profil.

Payda yalnızca uygulamayı açan kişilerden oluşturulmaz. Duraklatma, program kapatma ve aile bağlantısı kaybı ayrıca raporlanır.

### Pilot hedefleri — doğrulanacak hipotezler

- Yardımsız günlük görev başarısı: en az %90.
- Normal ağda dokunuştan backend onayına p95: 3 saniyenin altında.
- Dört haftalık pilotta günlük check-in başarısı: en az %80.
- Davetten aktif ilişkiye dönüşüm: en az %60.
- Dördüncü hafta devamlılık: en az %50.
- Yetkisiz veri erişimi: 0.
- Backend'de zamanında kayıt varken üretilen yanlış gecikme uyarısı: hedef 0; her olay incelenir.

Bu oranlar sektör benchmark'ı veya verilmiş performans garantisi değildir.

## 3. Hedef kullanıcılar ve roller

### A. Check-in kullanıcısı

Akıllı telefon kullanabilen, bağımsız yaşayan ve ailesine günlük haber vermek isteyen kişi.

İhtiyaçlar:
- Büyük ve anlaşılır buton.
- Minimum form ve menü.
- Kontrolün kendisinde olması.
- Günlük kullanımda tekrar giriş yapmak zorunda kalmamak.

### B. Yakın / aile üyesi

Başka evde, şehirde veya ülkede yaşayan çocuk, eş, kardeş veya güvenilen kişi.

İhtiyaçlar:
- Son kullanıcı beyanını görmek.
- Makul bekleme süresi sonunda haber almak.
- Gerekirse telefonla aramak.

### Rol kuralları

- Aynı hesap hem check-in kullanıcısı hem yakın olabilir.
- Aile etiketi yetki sağlamaz.
- Ödeme yapan kişi veri sahibi veya otomatik yönetici olmaz.
- Yakın, başka kişi adına check-in yapamaz.
- Yeni bir izleyici, veri sahibinin açık yetkilendirmesi olmadan erişim kazanamaz.
- İleri bilişsel desteğe veya sürekli bakıma ihtiyaç duyan kişiler için tek başına güvenlik çözümü olarak sunulmaz.

## 4. Kapsam

### MVP — kesin kapsam

- [x] Adla cihaz hesabı oluşturma; rastgele ID ve güvenli oturum. — Backend ve iOS v1.2 testleri geçti; Apple ile kurtarma ayrı açık.
- [x] Basit kullanıcı profili. — Yerel API ve iOS UI testi.
- [x] Büyük BEN İYİYİM butonu. — Backend onayı sonrası başarı; başarısız yanıt testleri.
- [x] Günlük idempotent check-in kaydı. — 100 eşzamanlı istek ve retry testi.
- [ ] Aile üyesi daveti ve açık yetkilendirme.
- [x] Güven Çemberi ve ilişkiyi kaldırma. — Yetki ve revocation HTTP/worker testleri; iOS ekranı derlendi.
- [ ] Yakınlarım ve yakın detay ekranı.
- [ ] Push notification ve uygulama içi durum kaydı.
- [x] Günlük kontrol saati ve bekleme süresi. — Backend kuralları ve iOS program kaydetme testi.
- [ ] Aşamalı kullanıcı hatırlatmaları.
- [ ] Kaçırılmış check-in kontrolü ve aile bildirimi.
- [x] Sonradan tamamlanan check-in güncellemesi. — Alerted → completed ve eski uyarı bastırma testi.
- [ ] 30 günlük temel geçmiş.
- [x] Bugün kontrolü duraklatma ve yeniden etkinleştirme. — API testleri; iOS onay akışı derlendi.
- [ ] Basit bildirim ayarları.
- [ ] iOS ana ekran widget'ı.
- [ ] Hesap silme, veri dışa aktarma ve izin yönetimi.
- [ ] Gizlilik, KVKK aydınlatma ve hizmet sınırı ekranları.
- [ ] Cihaz/oturum yönetimi.
- [ ] Erişilebilirlik, operasyon metrikleri ve minimum analitik.

### MVP dışında

- Android uygulaması ve Android widget.
- GPS, konum ve geofence.
- Sağlık/ilaç takibi, AI teşhis, risk skoru.
- Kamera, mikrofon, rehber okuma.
- Pasif cihaz sinyallerinden otomatik check-in.
- Chat, sosyal akış, reklam.
- Apple Watch, Wear OS.
- Doktor, sigorta veya bakım şirketi entegrasyonu.
- Acil çağrı merkezi.
- Platform tarafından gönderilen davet SMS'i ve check-in SMS fallback.
- İlk sprintlerde ödeme ve abonelik ekranları.
- Çok günlük tatil ve karmaşık haftalık programlar.

OTP SMS'i MVP'den çıkarıldı. Yeni kayıt ve eşleşme için telefon numarası/operatör SMS'i gerekmez. Davet bağlantısı veya kodu sistem paylaşım menüsü üzerinden kullanıcının seçtiği kanalla paylaşılır; QR yerel olarak üretilir. İnternet bağlantısı yine gereklidir.

## 5. Ürün kuralları

1. Check-in yalnızca bilinçli kullanıcı etkileşimiyle oluşur.
2. Bir profil için bir yerel takvim gününde bir günlük kayıt vardır.
3. Aynı gün tekrar dokunma yeni kayıt veya yeni mantıksal bildirim oluşturmaz.
4. Kontrol saatinden önce check-in yapılabilir; o günü tamamlar.
5. Sonraki kontrol “şimdi +24 saat” değil, ertesi günün seçili saatidir.
6. Backend zamanı otoritedir. İstemci zamanı yalnızca yardımcı bilgidir.
7. Varsayılan saat dilimi Europe/Istanbul'dur; IANA saat dilimi saklanır.
8. Cihaz saat dilimi değiştiğinde program sessizce değişmez.
9. Program değişiklikleri varsayılan olarak ertesi gün yürürlüğe girer.
10. MVP'de kontrol saati ve bekleme süresi aynı yerel güne sığmalıdır. Geceyi aşan kombinasyon açıklanarak reddedilir.
11. Bildirim izni reddi check-in'i engellemez; kısıt açıklanır.
12. Aile paylaşımı istenildiğinde, aile onayı aranmadan kaldırılabilir.
13. Yeni yakın varsayılan olarak yetkilendirme tarihinden önceki geçmişi göremez.
14. Eski bir çevrimdışı istek ertesi günün check-in'i sayılmaz.
15. Sistemin bilinmeyen durumu “iyi” olarak gösterilmez.
16. Kontrol saati geçtikten sonra kurulan veya etkinleştirilen programda hatırlatma rutini ertesi gün başlar; ilk gün anında gecikme uyarısı üretilmez. Kullanıcı ilk gün gönüllü check-in yapabilir.
17. Yalnızca yakınlarından haber almak isteyen hesap için kişisel check-in programı kurulmaz; kullanıcı sonradan etkinleştirebilir.

### Bugün duraklatma

- Kalan günlük hatırlatmalar ve henüz gönderilmemiş aile uyarıları iptal edilir.
- Aile ekranında “Bugün kontrol devre dışı” görünür.
- Ertesi gün program otomatik devam eder.
- Kullanıcı açık gün içinde yeniden etkinleştirebilir.
- Önceden tamamlanmış check-in silinmez.
- Hastane veya hastalık gibi gerekçeler istenmez ve saklanmaz.

## 6. UX akışları

### Yakının başlattığı kurulum

`Tanıtım → Ad + yalnızca haber alma tercihi → Cihaz hesabı/ID → Davet bağlantısı veya kod paylaş → Yakın kendi adını girer → Paylaşım kapsamını görür ve kabul eder → Günlük saat → Bildirim izni → İlk check-in → İsteğe bağlı widget kurulumu`

Yakın kurulumda yardımcı olabilir; veri sahibinin yerine paylaşım izni veremez.

### Check-in kullanıcısının başlattığı kurulum

`Tanıtım → Ad + günlük haber verme tercihi → Cihaz hesabı/ID → Yakın daveti (link/QR/kod) → Karşı taraf kabulü + veri sahibi onayı → BEN İYİYİM`

Henüz yakın yoksa: “İyi olduğunuz kaydedildi. Haber vermek için bir yakınınızı ekleyin.”

### Günlük akış

`Hatırlatma / widget / uygulama → BEN İYİYİM → Gönderiliyor → Backend onayı → Bugünkü haberiniz kaydedildi`

Günlük akışta form, yeniden OTP, paywall veya gereksiz onay adımı yoktur.

### Kaçırılmış check-in

`Kontrol saati → Aşamalı hatırlatma → Bekleme süresi sonu → Backend'de tekrar kontrol → Gerekirse yakın bildirimi → Sonradan check-in gelirse durum güncellemesi`

### Paylaşımı kaldırma

`Ailem → Kişi → Paylaşımı durdur → Sonucu açıklayan onay → İlişki iptali → API ve yeni bildirim erişimini kes`

## 7. Ekran listesi

### Giriş ve kurulum

- [ ] Kısa ürün tanıtımı ve hizmet sınırları.
- [ ] Adla hesap oluşturma ve kullanım tercihi.
- [ ] Bağlantı kesilirse aynı hesap oluşturma işlemini sürdürme; açık yeni hesap onayı.
- [ ] Giriş/kurtarma sorunu.
- [ ] Kullanım amacı seçimi.
- [ ] Ad/profil.
- [ ] Kontrol saati ve bekleme süresi.
- [ ] Bildirim izni ön açıklaması.

### Günlük deneyim

- [ ] Check-in ana ekranı.
- [ ] Gönderiliyor durumu.
- [ ] Başarılı kayıt durumu.
- [ ] Ağ/oturum hatası ve yeniden deneme.
- [ ] Bugün duraklatma.
- [ ] Geçmiş.

### Aile

- [ ] Yakınlarım.
- [ ] Yakın detay.
- [ ] Son bildirimler.
- [ ] Güven Çemberim.
- [ ] İlişki detayı ve paylaşımı kaldırma.
- [ ] Davet oluşturma/paylaşma.
- [ ] Davet önizleme, kabul/red.
- [ ] Süresi dolmuş veya geçersiz davet.

### Ayarlar ve destek

- [ ] Program ayarları.
- [ ] Bildirim tercihleri.
- [ ] Widget ekleme rehberi.
- [ ] Cihazlar ve oturumlar.
- [ ] Aydınlatma ve gizlilik.
- [ ] İzin yönetimi.
- [ ] Veri dışa aktarma.
- [ ] Hesap silme.
- [ ] Yardım, teknik sorunlar ve destek.

Bunların bir kısmı ayrı sayfa yerine sheet veya ekran durumu olarak uygulanabilir. Yaşlı ana ekranında tek baskın işlem bulunur.

## 8. UI tasarım sistemi

### Tasarım yönü

Sade, sıcak, sakin, yüksek kontrastlı ve yaşlı kullanıcıyı çocuklaştırmayan bir arayüz.

### Başlangıç token'ları

| Öğe | Öneri |
|---|---|
| Zemin | #FAFAF7 |
| Ana metin | #17211B |
| Ana buton | #176B45, beyaz yazı |
| Bekleyen durum | Açık sarı zemin ve koyu metin |
| Devre dışı durum | Nötr gri ve açık durum etiketi |
| Başlık | 28–34 pt |
| Gövde | 20–22 pt |
| Yardımcı metin | Tercihen en az 18 pt |
| Ana buton yüksekliği | Yaklaşık 140–180 pt; ekran ve yazı ölçeğine uyarlanır |
| Diğer dokunma alanları | En az 56×56 pt |
| Boşluklar | 8 / 16 / 24 / 32 pt |
| Köşe yarıçapı | 16–24 pt |

### Erişilebilirlik kabulü

- [ ] Dynamic Type ve büyük erişilebilirlik boyutları.
- [ ] VoiceOver etiketleri ve mantıklı odak sırası.
- [ ] Renk dışında metin/ikonla durum açıklaması.
- [ ] Normal metinde en az 4,5:1 kontrast.
- [ ] Büyük metinde en az 3:1 kontrast.
- [ ] %200 yazı ölçeğinde ana görevin tamamlanabilmesi.
- [ ] Reduce Motion desteği.
- [ ] Uzun basma, swipe veya küçük ikon gerektirmeyen ana görev.
- [ ] Tek elle ve motor güçlüğüyle kullanım testleri.
- [ ] Fotoğraf zorunlu değil; baş harf avatarı yeterli.

## 9. İçerik ve bildirim dili

### Ana ekran

“Günaydın Ayşe”

“Bugün henüz haber vermediniz.”

“BEN İYİYİM”

“Hatırlatma: Bugün 09.00”

“Son haberiniz: Dün 09.12”

### Başarı

“Bugünkü haberiniz kaydedildi.”

“Aileniz uygulamada iyi olduğunuzu görebilir.”

“Bugün 09.04”

### Aile durumu

“Ayşe bugün iyi olduğunu bildirdi. 09.04”

### Bekleme

“Kontrol bekleniyor.”

### Gecikme

“Ayşe’nin bugün henüz İyiyim bildirimi alınmadı. Kendisini aramak isteyebilirsiniz.”

### Ağ hatası

“Haberiniz henüz gönderilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.”

### Teknik belirsizlik

“Teknik bir sorun nedeniyle günlük durum güncellenemiyor.”

### Kullanılmayacak ifadeler

- “Kesinlikle güvende.”
- “Başına bir şey gelmiş olabilir.”
- “Aileniz artık biliyor.” — okunduğu doğrulanmadan kesin teslimat anlamında.
- “Her gün aramanıza gerek yok.”
- “Herşey Yolunda” — teknik durum veya sağlık garantisi olarak.

## 10. iOS mimarisi

### Önerilen teknoloji

Yalnızca iOS hedeflendiği için önceki cross-platform önerisi yerine native geliştirme önerilir:

- Swift ve SwiftUI.
- WidgetKit ve App Intents.
- URLSession ve Swift Concurrency.
- Keychain ile güvenli kimlik bilgisi saklama.
- App Groups ile minimum widget/uygulama durum paylaşımı.
- XCTest ve XCUITest.
- Swift Package Manager; gereksiz üçüncü taraf bağımlılık eklenmez.

### Platform tabanı

Öneri: iOS 17 ve üzeri, interaktif widget deneyimini sadeleştirmek için.

Bu karar pilot kullanıcıların cihazları incelenmeden kesinleştirilmez. iOS 16 desteği gerekirse widget dokunuşu uygulamadaki check-in ekranını açar; bu alternatifin UX maliyeti değerlendirilir.

### Katmanlar

- Presentation: SwiftUI ekranları ve erişilebilirlik.
- Feature state: ekran durumları ve kullanıcı niyetleri.
- Domain: check-in, program ve ilişki kuralları.
- Data: API istemcisi, repository'ler, güvenli saklama.
- Shared core: uygulama ve widget'ın ortak API sözleşmeleri.
- Widget extension: Flutter/React Native veya ana uygulama yaşam döngüsüne bağımlı olmayan işlem yolu.

### Minimum yerel veri

- Aktif profil kimliği.
- Son sunucu onaylı günlük durum ve tarihi.
- Sonraki kontrol zamanı.
- Bekleyen kısa süreli işlem kimliği.
- Sunucu eşitleme zamanı.

Token'lar UserDefaults veya düz App Group dosyasında saklanmaz. Aile geçmişinin tamamı widget ile paylaşılmaz.

## 11. Widget mimarisi

### Ana işleyiş

`Widget butonu → AppIntent → Güvenli oturum → Aynı check-in API'si → Backend onayı → Ortak durum cache'i → Timeline reload isteği`

- Buton, backend onayı gelmeden başarı rengine geçmez.
- Widget üzerinde tarih ve saat bulunur.
- Dünkü başarı bugün tamamlanmış gibi görünmez.
- Hesaptan çıkışta veya hesap değişiminde cache ve widget kimliği temizlenir.
- AppIntent içinde kullanıcı kimliği ve occurrence doğrulanır.
- Uygulama ile extension arasındaki refresh yarışları koordine edilir.
- Widget ve uygulama aynı idempotency kurallarını kullanır.
- OS'nin ağ süresini, arka plan çalışmasını veya görsel güncellemeyi garanti etmediği kabul edilir.

### Durumlar

- Bugün haber ver.
- Gönderiliyor.
- Bugün haber verdiniz — saat.
- Gönderilemedi — uygulamayı açıp yeniden deneyin.
- Oturum açmanız gerekiyor.
- Bugün kontrol devre dışı.

### Çevrimdışı politika

- Kısa süreli retry; başlangıç hipotezi en fazla 5 dakika.
- Aynı occurrence ve idempotency key korunur.
- Hiç kaydedilmemiş eski işlem, saatler sonra otomatik güncel beyana dönüşmez.
- Gün değiştiğinde eski istek bugüne uygulanmaz.
- Sunucu kaydetmiş ama yanıt kaybolmuşsa tekrar mevcut sonucu döndürür.
- Sunucu kaydı yok ve geçerlilik süresi dolmuşsa yeniden bilinçli dokunuş istenir.

## 12. Backend mimarisi

### Başlangıç seçimi

- TypeScript / NestJS modüler monolit.
- PostgreSQL.
- PostgreSQL tabanlı dayanıklı job sistemi.
- Transactional outbox.
- APNs; FCM ancak operasyonel ihtiyacı gerekçelendirilirse.
- API ve worker ayrı süreçler, ortak kod tabanı.
- Şifreli nesne depolama yalnızca dışa aktarma gibi ihtiyaçlarda.
- PII maskelenmiş log, metrik ve trace.

### Neden

- Küçük ekiple yönetilebilir.
- Check-in transaction'ı ve bildirim niyeti atomik yazılabilir.
- Redis, Kafka, Kubernetes ve mikroservisler ilk sürüm için zorunlu değildir.
- Mobil uygulama zamanlayıcısı aile uyarılarının otoritesi olmaz.

### Akış

`iOS / Widget → HTTPS API → PostgreSQL + Outbox → Worker → APNs → Yetkili yakının iOS uygulaması`

### Operasyon hedefleri — test edilecek

- Check-in API aylık erişilebilirliği için başlangıç SLO adayı: %99,9.
- Scheduler gecikmesi ve queue age için alarm eşikleri yük testiyle belirlenir.
- RPO/RTO hedefleri sağlayıcı ve bütçeyle onaylanır; başlangıç önerisi RPO ≤15 dakika, RTO ≤4 saat.
- Bu hedefler kullanıcıya acil hizmet garantisi olarak sunulmaz.
- Restore, provider kesintisi ve birikmiş işlerin güvenli toparlanması tatbikatla doğrulanır.

## 13. Veri modeli

### Temel entity'ler

| Entity | Alanlar / amaç |
|---|---|
| User | id, name, enabled, created_at, activated_at; eski telefon/hash alanları nullable ve yalnızca geçmiş kayıtlar için korunur |
| Profile | id, user_id unique, display_name, timezone, checkin_enabled |
| FamilyRelationship | subject_profile_id, viewer_user_id, status, label, permissions, authorized_at, revoked_at, history_visible_from |
| CheckInSchedule | profile_id, local_time, timezone, grace_minutes, reminder_offsets, version, effective_from/to |
| CheckInOccurrence | profile_id, local_date, schedule_version, due_at, deadline_at, closes_at, state, version |
| CheckIn | occurrence_id, actor_user_id, device_id, source, received_at, client_action_at, idempotency_key |
| Reminder | occurrence_id, step, scheduled_at, state, attempt_count |
| Notification | event_id, occurrence_id, relationship_id, recipient_user_id, channel, type, status, accepted_at, opened_at |
| NotificationPreference | user_id, relationship_id, event_type, enabled, quiet_hours, timezone |
| Invitation | creator, subject, recipient, token_hash, code_hash (HMAC), label, status, expires_at; telefon hedefleme yok |
| Device | user_id, platform, şifreli push token, permission_state, app_version, last_seen_at, revoked_at |
| Session | user_id, device_name, access_hash, refresh_hash, family_id, access/refresh expiry, revoked |
| AccountRegistration | secret_hash, user_id, fingerprint, family_id, expires_at; 10 dakikalık kayıt tekrar penceresi, kalıcı kurtarma yöntemi değil |
| Consent | user_id, purpose, document_version, status, granted_at, withdrawn_at |
| AuditLog | actor, action, resource, outcome, request_id, created_at |
| OutboxEvent | aggregate_id, type, minimum payload, created_at, published_at, attempt_count |
| Subscription | Faz 2: payer_user_id, store, product_id, transaction_ref, status, expires_at, verified_at |

Consent tablosu her işlemin rızaya dayandığı anlamına gelmez. Aydınlatma sunumu, işlem bazlı hukuki dayanak envanteri ve isteğe bağlı açık rıza ayrı değerlendirilir.

### Kritik kurallar

- UNIQUE(profile_id, local_date): günlük occurrence.
- UNIQUE(occurrence_id): günlük check-in.
- UNIQUE(actor_user_id, idempotency_key): istek tekrarı.
- UNIQUE(occurrence_id, step): hatırlatma adımı.
- UNIQUE(event_id, recipient_user_id, channel): mantıksal bildirim.
- Aktif subject/viewer ilişkisi için partial unique index.
- Açık occurrence deadline'larına, bekleyen işlerin scheduled_at alanına ve ilişki lookup'larına indeks.

### Many-to-many

Bir profil birden çok yakına, bir yakın birden çok profile bağlanabilir. İlişkiler birbirine yetki devretmez. Ürün limitleri veritabanı modeline sabit yazılmaz.

## 14. Check-in durum makinesi

| Durum | Anlam |
|---|---|
| pending | Gün açık, beyan yok |
| reminded | Hatırlatma işi oluşturuldu/işlendi; görüldüğü anlamına gelmez |
| completed | Kullanıcının beyanı backend'e kaydedildi |
| overdue | Bekleme süresi doldu, beyan yok |
| alerted | Aile bilgilendirmesi mantıksal olarak oluşturuldu; teslimat ayrı |
| cancelled | Günlük kontrol kullanıcı tarafından kapatıldı |

### Geçişler

- pending → reminded → completed.
- pending → completed.
- pending veya reminded → overdue.
- overdue → alerted.
- overdue veya alerted → completed.
- pending/reminded/overdue/alerted → cancelled.
- cancelled → pending: yalnızca açık gün yeniden etkinleştiriliyorsa.

### Tutarlılık

- Tamamlanmış kayıt normal akışta geri alınmaz.
- Gün kapanınca çözülmemiş durum geçmişte kalır; ertesi güne tamamlandı olarak taşınmaz.
- Gün kapandıktan sonra eski check-in yeni gün yerine işlenmez.
- Eski uyarılar sonsuza kadar yeniden gönderilmez.
- Check-in ve uyarı worker'ı aynı occurrence üzerinde kilit/versiyon denetimi kullanır.
- Uyarı gönderilmeden önce güncel state ve ilişki tekrar kontrol edilir.
- Sağlayıcıya çıkmış push geri alınamayabilir; sonradan tamamlandı bilgisiyle durum düzeltilir.

## 15. API sözleşmesi

Tüm endpoint'ler /v1 altında, server-side yetkilendirme ile çalışır.

### Auth ve hesap

- POST /auth/device — ad, enabled, cihaz etiketi ve rastgele kayıt tekrar anahtarı; ID + access/refresh session döndürür.
- Eski /auth/otp/start ve /auth/otp/verify endpoint'leri 410 auth_method_removed döndürür; eski aktif oturumlar geçerliliğini korur.
- POST /auth/refresh
- POST /auth/logout
- GET /me
- PATCH /me/profile
- GET /me/sessions
- DELETE /me/sessions/{id}
- POST /me/devices
- PATCH /me/devices/{id}

### Check-in ve program

- GET /me/checkin/today
- POST /me/checkins
- GET /profiles/{id}/checkins
- GET /me/checkin-schedule
- PUT /me/checkin-schedule
- POST /me/checkin/today/pause
- POST /me/checkin/today/resume

### İlişki ve davet

- GET /me/relatives
- GET /profiles/{id}/status
- GET /me/relationships
- DELETE /me/relationships/{id}
- POST /invitations
- POST /invitations/preview — token request body'de; loglanmaz
- POST /invitations/{id}/accept
- POST /invitations/{id}/decline
- POST /invitations/{id}/approve-sharing

### Bildirim ve gizlilik

- GET /me/notifications
- POST /me/notifications/{id}/opened
- GET/PATCH /me/notification-preferences
- GET/PATCH /me/consents
- POST /me/exports
- GET /me/exports/{id}
- DELETE /me

### Check-in request

Header: Idempotency-Key: rastgele UUID.

Body: occurrence_id, source, client_action_at.

Response: checkin_id, status, received_at, already_completed, notification_state, next_due_at.

- source: app veya ios_widget.
- client_action_at güvenilir sunucu zamanı yerine kullanılmaz.
- Aynı key farklı payload ile gelirse conflict.
- Aynı occurrence farklı key ile tekrar gelirse mevcut günlük kayıt döner.
- Geçersiz gün, süre aşımı ve yetki sorunları makine tarafından ayrıştırılabilen hata kodları döndürür.
- Liste endpoint'leri cursor pagination kullanır.

## 16. Bildirim altyapısı

### Örnek program

| Saat | İşlem |
|---|---|
| 09.00 | İlk kullanıcı hatırlatması |
| 10.00 | İkinci nazik hatırlatma |
| 12.00 | Son kullanıcı hatırlatması |
| 13.00 | Kayıt hâlâ yoksa aile bilgilendirmesi |

Bunlar örnektir. Hatırlatma yoğunluğu pilotta test edilir; her kullanıcıya zorunlu dört mesaj uygulanmaz.

### Outbox akışı

1. Check-in ve outbox event aynı transaction'da yazılır.
2. Worker aktif ilişki ve tercihleri kontrol eder.
3. Alıcı başına mantıksal notification oluşturulur.
4. APNs isteği gönderilir.
5. Geçici hatalarda exponential backoff + jitter.
6. Geçersiz token pasifleştirilir.
7. Kalıcı hatalar ve tüketilmiş retry'lar incelenebilir kuyruğa alınır.
8. Mutabakat işi kayıp/takılmış işleri denetler.

### Teslimat semantiği

queued → sending → provider_accepted → opened (yalnızca gözlenebiliyorsa).

Alternatif: retryable_failed / permanently_failed / suppressed.

- Provider kabulü cihaz teslimi değildir.
- Cihaz teslimi okunma değildir.
- Backend mantıksal tekrarları önler; dağıtık push için fiziksel exactly-once sözü verilmez.
- TTL ve stale mesaj bastırma kuralları tanımlanır.
- Başarı ve missed bildirimleri ayrı tercihlerdir.
- Sessiz saatler kullanıcıdan habersiz aşılmaz.
- MVP'de Critical Alerts veya acil durum yetkileri talep edilmez.

### Mahremiyet

Varsayılan kilit ekranı mesajı: “Yakınınızdan yeni bir haber var.”

İsimli içerik isteğe bağlıdır. Push payload'ı minimum olay kimliği taşır; telefon, geçmiş veya sağlık bilgisi taşımaz.

### Kesintiler

Bilinen altyapı kesintisinde durum güvenilir değerlendirilemiyorsa kullanıcı gecikmesiyle teknik sorun karıştırılmaz. Toparlanma sırasında geçmiş uyarılar topluca gönderilmez; güncellik ve state tekrar kontrol edilir.

## 17. Güvenlik planı

### Kimlik

- [ ] Kısa ömürlü access token ve döndürülen refresh token.
- [ ] Refresh token hash ve reuse detection.
- [ ] JWT issuer/audience/expiry ve imza doğrulama.
- [ ] Keychain saklama ve extension erişim sınırı.
- [ ] Cihaz/oturum iptali.
- [ ] Yeni cihaz/oturum kaybı için Apple ile isteğe bağlı kurtarma entegrasyonu.
- [x] Aynı adla veya hesap ID'siyle eski hesabı devralma engeli.

### Telefon/SMS'siz cihaz hesabı

- [x] Rastgele hesap ID'si; isim veya ID ile oturum açılamaz.
- [x] Kayıt için cihazda 256-bit rastgele anahtar; sunucuda yalnızca hash saklanır.
- [x] Bağlantı hatası tekrarında aynı hesabı tamamlama; 10 dakikalık pencere, eski yanıt token'larını iptal.
- [x] Ağ bazlı 10 yeni hesap/saat ve global kayıt limiti; IP HMAC ile sayaç anahtarı.
- [x] Hesaptan çıkış kayıt tekrar anahtarını da geçersiz kılar.
- [x] Eski OTP yolları 410 döndürür; aktif eski oturumlar korunur.
- [ ] İsteğe bağlı Apple hesabı bağlama/kurtarma; bu sürümde etkin değil.
- [ ] Üretim abuse izlemesi ve gerekirse platform attestation değerlendirmesi.
- [ ] Token, kayıt anahtarı veya davet kodu loglanmaz — üretim log denetimi ayrıca yapılmalı.

### Yetkilendirme

- [ ] Her profil/geçmiş/bildirim isteğinde aktif ilişki denetimi.
- [ ] IDOR/BOLA testleri.
- [ ] Yakınların program ve üyelikleri kendiliğinden değiştirememesi.
- [ ] Revocation sonrası eski oturumla da veri alınamaması.
- [ ] Export'un yalnızca yetkili kişinin kendi kapsamını içermesi.

### Davet

- [ ] Kriptografik rastgele token, veritabanında hash.
- [ ] Tek kullanım ve örneğin 48 saat geçerlilik.
- [ ] Hedef telefon varsa doğrulanmış numarayla eşleşme.
- [ ] Genel paylaşım linkinde gerçek alıcı için veri sahibi onayı.
- [ ] Önizlemede minimum veri.
- [ ] Davet spam limiti, engelleme ve red.

### Altyapı

- [ ] TLS ve encryption at rest.
- [ ] Hassas alanlarda ek şifreleme.
- [x] Davet kodu ve ağ sayaçları için keyed HMAC; kayıt/session sırları hash'lenir. Yeni telefon lookup yok.
- [ ] Secret manager/KMS ve anahtar rotasyonu.
- [ ] Yönetici MFA ve least privilege.
- [ ] PII maskelenmiş loglar.
- [ ] Secret/dependency taraması.
- [ ] Şifreli yedek ve restore tatbikatı.

## 18. KVKK ve veri yaşam döngüsü

Bu bölüm uygulamaya özel hukuk incelemesi gerektirir; hukuki uygunluk garantisi değildir.

### Gerekli çalışma

- [ ] Veri sorumlusu ve veri işleyenleri belirle.
- [ ] Veri işleme envanteri ve veri akış diyagramı oluştur.
- [ ] Her amaç için KVKK m.5, gerekiyorsa m.6 değerlendirmesi.
- [ ] Aydınlatma, hizmet şartları ve isteğe bağlı rızaları ayır.
- [ ] OS bildirim iznini KVKK rızası olarak kullanma.
- [ ] APNs/hosting/SMS/analytics/support sağlayıcılarını değerlendir.
- [ ] KVKK m.9 kapsamında yurt dışı aktarım mekanizmasını belirle.
- [ ] Standart sözleşme seçilirse taraf yapısı ve bildirim yükümlülüklerini doğrula.
- [ ] VERBİS ve diğer yükümlülükleri güncel koşullarla değerlendir.
- [ ] Veri sahibi başvuruları için kanal ve en geç 30 günlük cevap süreci kur.
- [ ] Veri ihlali bildirim ve müdahale prosedürü oluştur.

Türkiye'de hosting kullanılması APNs veya diğer yurt dışı servis aktarımlarını ortadan kaldırmaz. Sürekli aktarım basit bir zorunlu rıza kutusuyla çözümlenmiş sayılmaz.

### Başlangıç saklama önerileri

| Veri | Öneri |
|---|---|
| Hesap oluşturma tekrar anahtarı | 10 dakika içinde tekrar için geçerli; hash hesabın ömrü boyunca eski anahtarın yeniden kullanılmasını önlemek için tutulur, hesapla silinir |
| Süresi dolmuş davet | En fazla 30 gün |
| Check-in geçmişi | MVP 30 gün |
| Bildirim operasyon kaydı | 30 gün |
| Ham isteğe bağlı analitik | 90 gün |
| Güvenlik audit log | Gerekçelendirilmiş 180 gün |
| Yedek | 35 günlük döngü |
| Mali/abonelik kaydı | İlgili mevzuatla ayrıca belirlenir |

Bu süreler kanuni süre iddiası değil; hukuk ve operasyon onayına sunulacak ürün önerileridir.

### Hesap silme

- Talep sonrası yeni veri paylaşımı ve oturumlar hemen durdurulur.
- İlişkiler ve bekleyen işler iptal edilir.
- Aktif sistemlerden silme için somut SLA; başlangıç önerisi 30 gün.
- Yedeklerden çıkış süresi açıklanır.
- Hukuken tutulması gereken kayıtlar ayrıştırılır.
- Restore sonrası silme kayıtları yeniden uygulanır.
- Faz 2'de store abonelik iptali ayrıca anlatılır; silme bu işleme zorla bağlanmaz.

### Dışa aktarma

Kimlik doğrulama, kapsam kontrolü, kısa ömürlü erişim ve otomatik dosya silme uygulanır. KVKK hakları GDPR taşınabilirlik hükümleriyle birebir eşitlenmez; export ürün taahhüdü olarak sunulur.

## 19. Analytics planı

### Olaylar

- app_opened
- checkin_started
- checkin_completed — backend transaction kaynağı
- checkin_failed
- reminder_sent — sağlayıcı kabulü anlamında
- reminder_opened
- missed_checkin
- family_alert_sent
- family_alert_opened
- invite_created
- invite_accepted — ilişki aktif olduğunda
- checkin_paused
- relationship_revoked
- notification_permission_changed
- widget_checkin_started
- subscription_started / cancelled / expired — Faz 2

### Minimum alanlar

Pseudonymous user ID, event ID, platform, app version, source, result code, latency bucket ve gerekiyorsa experiment ID.

### Yasak alanlar

Ad, telefon, yakın adı, ilişki etiketi, davet token'ı, push içeriği, sağlık/duraklatma gerekçesi ve serbest metin.

Pseudonymous veri anonim değildir. Gerekli operasyon metrikleri ve isteğe bağlı ürün analitiği ayrılır. Analitiği reddetmek temel hizmeti engellemez.

### Ek KPI'lar

- Zamanında check-in ve deadline'da missed oranı.
- Weekly active check-in users.
- D7/D30 ve haftalık retention.
- Davet kabul oranı.
- Provider acceptance ve ölçülebilir açılma oranı.
- Check-in p50/p95 süresi.
- Widget kaynaklı başarı/hata oranı.
- Hatırlatma sonrası dönüşüm; nedensellik iddiası olmadan.
- Aktif yakın sayısı.
- Teknik yanlış uyarı oranı.
- Gönüllü kaygı azalması ve kontrol edilmiş hissetme araştırması.
- Faz 2: ödeme dönüşümü, iade, churn ve katkı payı.

## 20. Freemium ve ödeme

### Free

- Bir check-in profili.
- İki yetkili yakın.
- Günlük program ve temel hatırlatmalar.
- Kaçırılmış check-in bildirimi.
- iOS widget.
- 30 gün geçmiş.
- Bugün duraklatma.
- Tüm gizlilik ve erişilebilirlik işlevleri.

### Faz 2 Premium

- Daha büyük Güven Çemberi.
- Birden çok yakını tek panelde yönetme.
- Esnek programlar.
- Uzun geçmiş.
- Çok günlük duraklatma.
- Gelişmiş bildirim organizasyonu.
- Ayrı bütçeli SMS fallback paketi.

### Kurallar

- Temel güvenilirlik, widget ve hesap silme ücretli yapılmaz.
- Abonelik veri erişimi oluşturmaz.
- Downgrade mevcut temel haberleşmeyi habersiz kesmez.
- Limit aşımında yeni eklemeler sınırlandırılır; mevcut aile davranışı için güvenli geçiş tasarlanır.
- Çoklu ilişki veri modelinde baştan desteklenir, geniş yönetim arayüzü Faz 2'dir.

### Fiyat test hipotezleri

- 79 TL/ay veya 790 TL/yıl.
- 119 TL/ay veya 1.190 TL/yıl.
- 159 TL/ay veya 1.590 TL/yıl.

Önce nitel ödeme isteği görüşmeleri, sonra şeffaf ilgi testi, yeterli trafik oluştuğunda gerçek satın alma deneyi yapılır. Nihai fiyat değildir.

### iOS ödeme mimarisi

StoreKit 2, backend transaction doğrulama, App Store Server Notifications, restore, refund, billing retry, grace period ve expiry.

İstemcinin premium bilgisine güvenilmez. Store event'leri idempotent ve sıra dışı gelişe dayanıklıdır. Fiyat, yenileme ve iptal şartları açık gösterilir.

## 21. Rakip ve pazar araştırması özeti

15 Eylül 2026 tarihli önceki masa başı araştırmasına dayanır. Uygulamalar cihazda uçtan uca test edilmemiştir; fiyat ve mağaza metrikleri yayından önce yenilenmelidir.

| Rakip | Gözlem | Bizim ayrışmamız |
|---|---|---|
| İyiyim! | Türkiye App Store kaydı; konum, pil, hareket ve manuel durum. İncelenen vitrinde 5 değerlendirme/5,0; Play sayfasında 500+ indirme bandı | Konumsuz, yalnızca bilinçli beyan, sade ana görev |
| WozaiApp | Türkiye App Store'da görev/ilaç/aile paylaşımı, widget ve Watch; Play kaydı doğrulanamadı | Sağlık ve görev karmaşıklığı olmadan tek davranış |
| Snug | Günlük check-in, ücretsiz temel plan, ücretli dispatch | İnsanlı müdahale ve sağlık/güvenlik vaadi yok |
| Iamfine | Telefon aramasıyla günlük onay | Akıllı telefon kullanan segmentte widget kolaylığı |
| StaySafe | Yalnız çalışan ve kurumsal güvenlik | İşveren gözetimi ve B2B kapsamı yok |
| Telefon / WhatsApp | Mevcut aile rutini | Mesaj yazmadan hatırlatma ve tutarlı günlük durum |

Aktif kullanıcı sayıları bu araştırmada doğrulanmadı. İndirme bandı aktif kullanıcı sayısı değildir. Gizlilik etiketleri bağımsız denetim değildir.

Türkiye pazar büyüklüğü akıllı telefon kullanımı, gönüllü paylaşım ve aile aktivasyonu ile aşağıdan yukarı hesaplanmalıdır. Toplam yaşlı nüfus doğrudan erişilebilir müşteri sayısı değildir.

## 22. Marka ve landing page

### Marka kontrolü

- [ ] “Herşey Yolunda” ve “Her Şey Yolunda” yazımları.
- [ ] TÜRKPATENT aynı/benzer marka araştırması.
- [ ] Yazılım/SaaS ve ilgili hizmet sınıflarının uzmanla değerlendirilmesi.
- [ ] App Store arama ve karışıklık testi.
- [ ] Domain ve sosyal hesap uygunluğu.
- [ ] Yaşlı kullanıcı telaffuz ve hatırlama testi.

İsim kullanıcı tarafından seçilmiştir; marka tescili, mağaza veya domain uygunluğu henüz doğrulanmamıştır. Hiçbir domain boş kabul edilmez.

### Ana mesajlar

- “Bir dokunuşla ailene haber ver.”
- “Konumunu değil, haberini paylaş.”
- “Sohbetin yerini almaz. Aradaki merakı azaltır.”
- “Kimlerin haber alacağına sen karar ver.”

### Landing metni taslağı

Başlık: **Bir dokunuşla ‘Ben iyiyim.’**

Açıklama: Herşey Yolunda ile yakınlarınıza her gün kolayca haber verin. Konum paylaşmadan, takip edilmeden.

CTA: **Ailemle kullanmak istiyorum**

Nasıl çalışır:
1. Haber vermek istediğiniz kişileri seçin.
2. Size uygun saati belirleyin.
3. BEN İYİYİM butonuna dokunun.

Gecikme açıklaması: Belirlediğiniz bekleme süresinde haberiniz alınmazsa yakınlarınıza sizi aramak isteyebileceklerini belirten sakin bir bildirim gönderilir.

Mahremiyet: Konumunuz takip edilmez. Kamera ve mikrofon kullanılmaz. Paylaşımı istediğiniz zaman durdurabilirsiniz.

Sınır: Bu uygulama acil yardım veya tıbbi müdahale hizmeti değildir. İnternet ve bildirim ayarları gönderimi etkileyebilir.

## 23. Sprint planı ve kabul kapıları

Sprintler süre taahhüdü değildir. Her aşama bir öncekinin kabul kriterlerine bağlıdır.

### Sprint 0 — Kararlar, prototip ve teknik doğrulama

- [ ] Marka yazımı ve iOS minimum sürüm kararı.
- [ ] 10–15 yaşlı kullanıcı ve 10–15 yakın ile ihtiyaç görüşmesi.
- [x] Ana ekran, davet ve başarı prototipi. — Çalışan SwiftUI ekranları; check-in ve davet oluşturma UI testleri geçti.
- [x] SwiftUI erişilebilirlik denemesi. — En büyük Dynamic Type kategorisinde kaydırma ve giriş alanına erişim XCUITest ile geçti. VoiceOver/yaşlı kullanıcı araştırması ayrı açık.
- [x] Widget AppIntent → test backend teknik denemesi. — Gerçek yerel HTTP API'ye karşı AppIntent çalıştırıldı; dünkü cache yenilendi ve iki çağrıda tek ios_widget kaydı doğrulandı. SpringBoard dokunuşu/gerçek cihaz ayrı.
- [ ] Backend/hosting ve KVKK veri akış kararı. OTP sağlayıcısı artık giriş için gerekli değil.

Kabul: ana görev anlaşılır; widget kısıtları belgelenmiş; üretim servisi seçimleri açık.

### Sprint 1 — Temel hesap ve check-in

- [x] iOS proje iskeleti ve test altyapısı. — SwiftUI uygulaması, WidgetKit hedefi, XCTest ve XCUITest; 9 simülatör testi geçti.
- [ ] Backend, PostgreSQL ve migration altyapısı.
  - [x] NestJS, gömülü PostgreSQL, sürümlü migration, yeniden başlatmada kalıcılık.
  - [ ] Ayrı PostgreSQL sunucusunda ve üretim TLS/backup yapılandırmasında doğrulama.
- [ ] Cihaz hesabı, session ve güvenli saklama (v1.2).
  - [x] Adla yeni hesap, ID üretimi, kayıt retry, hash'li session ve migration testleri.
  - [x] Güncellenen adla giriş + shared Keychain iOS uçtan uca doğrulaması; telefon/OTP alanlarının bulunmadığı test edildi.
  - [ ] Apple ile kurtarma ve üretim abuse politikası.
- [x] Profil ve ana ekran. — Yerel API ile giriş/profil/check-in UI testi geçti; gerçek yaşlı kullanıcı testi açık.
- [x] Günlük occurrence ve idempotent check-in. — Gömülü PostgreSQL üzerinde eşzamanlı istek ve retry testleri geçti; üretim PostgreSQL testi ayrı.
- [ ] Temel CI kontrolleri.
  - [x] GitHub Actions iş akışı oluşturuldu; YAML parse ve yerel eşdeğer test/audit komutları geçti.
  - [ ] Uzak GitHub runner çalışması; repo henüz uzak sunucuya gönderilmedi.

Kabul: tek/çift dokunuş, timeout retry ve aynı gün tekrarı testleri geçer. Ödeme yok.

### Sprint 2 — Güven Çemberi

- [ ] Davet oluşturma/paylaşma/kabul/red.
- [x] Veri sahibi onayı. — Paylaşım kabulü ve ek onay öncesi erişim reddi test edildi.
- [x] İlişki tabanlı yetkilendirme. — Onaysız erişim ve revocation entegrasyon testleri geçti.
- [ ] Yakınlarım ve detay.
- [x] Paylaşımı kaldırma. — API ve iOS onay ekranı mevcut; revocation sonrası erişim/push engeli HTTP ve worker testleriyle doğrulandı.

Kabul: başka aile verisine erişim mümkün değil; iletilmiş davet linki otomatik yetki yaratmıyor.

### Sprint 3 — Günlük rutin ve bildirim

- [x] Program ve bekleme süresi. — Geceyi aşan program reddi, ertesi gün yürürlük backend testi ve program kaydetme UI testi geçti.
- [x] Scheduler ve transactional outbox. — Notification tablosu transactional outbox görevinde; per-device delivery, lease, retry ve kalıcılık testleri geçti. Üretim kapasite doğrulaması ayrı.
- [ ] APNs.
  - [x] HTTP/2 + ES256 gönderici, TTL/collapse ID, retry ve geçersiz cihaz yönetimi; fake transport testleri.
  - [ ] Apple hesabı, gerçek cihaz token'ı ve canlı teslimat testi.
- [ ] Hatırlatmalar ve aile uyarıları.
  - [x] Backend zamanlama, grace period, ilk gün koruması ve uygulama içi bildirim kayıtları.
  - [ ] Gerçek iPhone'larda zamanında push/izin/sessiz mod doğrulaması.
- [x] Sonradan tamamlandı akışı. — Alerted → completed, eski kuyruğun bastırılması ve yeni durum testi.
- [ ] Geçmiş ve bugün duraklatma.
- [ ] Retry, stale mesaj bastırma ve mutabakat.

Kabul: check-in/uyarı yarışları, provider kesintisi ve geçersiz token testleri geçer.

### Sprint 4 — Widget ve erişilebilirlik

- [ ] Üretim widget extension.
- [ ] App Groups/Keychain koordinasyonu.
  - [x] Shared Keychain ve App Group erişimi ad-hoc imzalı simülatörde; AppIntent ile snapshot/session kullanımı.
  - [ ] Gerçek cihazda iki süreçli app/widget eşzamanlı refresh, restart ve kilit ekranı testi.
- [ ] Ağ, oturum, tarih ve cache durumları.
- [x] Widget kurulum rehberi. — iOS yardım ekranı uygulandı ve derlendi; gerçek cihaz kurulum testi açık.
- [ ] VoiceOver/Dynamic Type testleri.

Kabul: gerçek cihazlarda yalancı başarı yok; günlük görev erişilebilir.

### Sprint 5 — Gizlilik, güvenlik ve beta

- [ ] Silme, export, izin ve cihaz yönetimi.
  - [x] API ve iOS ekranları; hesap silme/export kapsamı, session reuse ve logout sonrası cihaz token iptali testleri.
  - [ ] Gerçek cihazda izin değişimi, kurtarma ve üretim silme/yedek prosedürü.
- [ ] KVKK ve gizlilik ekranları.
  - [x] Veri minimizasyonu ve hizmet sınırlarını açıklayan taslak iOS ekranları; privacy manifest plist doğrulandı.
  - [ ] Veri sorumlusu bilgileri, sağlayıcılar ve hukuk onaylı nihai aydınlatma/aktarım metinleri.
- [ ] Yük testi ve scheduler doğrulaması.
  - [x] Yerelde 100 eşzamanlı check-in + deadline worker testi; tek kayıt ve stale uyarı bastırma.
  - [ ] Üretim PostgreSQL, gerçek trafik profili, queue lag ve SLO doğrulaması.
- [ ] Restore/silme tatbikatı.
  - [x] Yerel DB kapat/aç sonrasında kayıt ve kuyruk kalıcılığı; hesap silmenin korunması.
  - [ ] Ayrı yedekten geri yükleme, silme tombstone'ları ve RPO/RTO tatbikatı.
- [ ] Minimum analytics ve operasyon alarmları.
- [ ] TestFlight kapalı beta.
- [ ] Mağaza hazırlığı.

Kabul: kritik güvenlik sorunu yok; silme ve restore doğrulanmış; pilot destek süreci hazır.

Gizlilik ve güvenlik baştan uygulanır; Sprint 5 bunların ilk defa eklendiği değil, tamamlanıp doğrulandığı aşamadır.

## 24. Test planı

### İşlevsel ve tutarlılık

- [x] Tek check-in → tek günlük kayıt. — Backend entegrasyon testi.
- [x] Hızlı çift dokunuş → aynı kayıt. — Backend eşzamanlı istek testi.
- [x] Uygulama ve widget eşzamanlı → aynı kayıt. — İki source ile backend testi; gerçek widget etkileşimi ayrıca açık.
- [x] Sunucu kaydı sonrası yanıt kaybı → retry aynı sonucu döndürür. — Aynı idempotency key ile backend testi.
- [ ] Deadline anında check-in → tutarlı durum.
- [x] Uyarı sonrası check-in → ailede güncel durum. — Backend state ve notification testi.
- [x] Duraklatma → kalan işler bastırılır. — Scheduler testi.
- [x] Erken check-in → o gün tamamlanır. — Saat 08.00 beyanı testi.
- [ ] Program değişikliği → eski işler versiyon kontrolüyle etkisizleşir.
- [ ] Gece yarısı ve stale occurrence → yanlış gün tamamlanmaz.

### Güvenlik

- [ ] IDOR/BOLA, rol ve geçmiş sınırı.
- [ ] İlişki iptalinden sonra API/push.
- [ ] Başkasına iletilen davet ve token replay.
- [x] İsim/ID ile yetkisiz giriş, kayıt limiti ve davet kodu tahmin limiti testleri.
- [ ] Refresh reuse ve eşzamanlı app/widget refresh.
- [ ] Export kapsamı ve kısa ömürlü indirme.
- [ ] Hesap silme ve yedekten dönüş.

### iOS cihaz matrisi

- [ ] Desteklenen en eski ve güncel iOS.
- [ ] Küçük ekranlı cihaz.
- [ ] Düşük güç modu.
- [ ] Uygulama kapalı/sonlandırılmış.
- [ ] Cihaz yeniden başlatma.
- [ ] Wi-Fi/mobil veri geçişi ve uçak modu.
- [ ] Bildirim izni reddi ve sonradan kapatılması.
- [ ] Widget kaldırma/ekleme ve stale timeline.
- [ ] Hesap değişimi/çıkış.
- [ ] VoiceOver, büyük yazı ve Reduce Motion.

### Operasyon

- [ ] Database/worker yeniden başlatma.
- [ ] APNs geçici ve kalıcı hata.
- [ ] Queue backlog ve toplu stale mesaj bastırma.
- [ ] Yedekten dönüş ve silme kayıtlarının tekrar uygulanması.
- [ ] Loglarda PII/token olmaması.

## 25. Edge case kayıtları

| Durum | Beklenen yaklaşım |
|---|---|
| Yakın henüz yok | Kayıt alınır; aileye gönderildi denmez |
| Tüm ilişkiler kaldırıldı | Yeni aile bildirimi yok; kullanıcıya anlaşılır bilgi |
| Tüm yakın cihazları erişilemez | API kaydı korunur; teslimat garantisi verilmez |
| Kullanıcı yanlışlıkla bastı | Ürün beyanın doğruluğunu kanıtlayamaz; otomatik sağlık sonucu çıkarmaz |
| Başkası kullanıcının açık telefonunda bastı | Biyometrik sağlık doğrulaması iddiası yok; cihaz güvenliği sınırı açıklanır |
| Kullanıcı farklı ülkeye gitti | Program saat dilimi kullanıcı onayı olmadan değişmez |
| Yakın farklı saat diliminde | Profilin kontrol saati açık saat dilimiyle gösterilir |
| Telefon/oturum kayboldu | Ad veya hesap ID'si eski hesaba giriş sağlamaz; Apple kurtarma bağlanmadıysa yeni hesap ve yeniden açık eşleştirme |
| Gün içinde hesap silindi | İşler/ilişkiler iptal; missed uyarısı üretilmez |
| Teknik kesinti | Kullanıcı cevapsızlığıyla karıştırılmaz |
| Geç push geldi | Güncellik kontrolü; eski bildirimden açılan ekran güncel backend durumunu gösterir |
| Abonelik sona erdi | Faz 2'de temel haberleşme ani ve habersiz kesilmez |

## 26. App Store yayın kontrol listesi

- [ ] Apple Developer üyeliği ve gerekli yetkiler.
- [ ] Bundle ID, signing, provisioning.
- [ ] APNs development/production ayrımı.
- [ ] Widget extension ve App Group entitlement'ları.
- [ ] Universal Links ve davet fallback sayfası.
- [ ] Gizlilik politikası ve destek sayfası.
- [ ] App Privacy beyanı ve gerekli privacy manifest'ler.
- [ ] Uygulama içinden hesap silme başlatma.
- [ ] Gereksiz permission yok.
- [ ] Türkçe ekran görüntüleri ve gerçek özellik açıklaması.
- [ ] Yaş derecelendirmesi ve sağlık/acil hizmet iddialarının kontrolü.
- [ ] Reviewer için güvenli test erişimi; gerçek kişilere mesaj gitmez.
- [ ] TestFlight gerçek cihaz sonuçları.
- [ ] Faz 2: StoreKit ürünleri, restore, iptal/yenileme şeffaflığı.
- [ ] Yayın öncesi güncel Apple kurallarının tekrar kontrolü.

İlk sürümün yalnızca iOS olması, Android kullanan aile üyelerinin kullanamayacağı anlamına gelir. Pilot aile seçiminde her iki tarafın iOS erişimi doğrulanmalı; bu kısıt talep verisini etkileyen bir seçim yanlılığı olarak raporlanmalıdır.

## 27. Türkiye launch ve 90 günlük doğrulama

90 gün, çalışan kapalı beta başlangıcından itibaren ürün öğrenme planıdır; geliştirme süresi taahhüdü değildir.

| Dönem | Odak | Faaliyet |
|---|---|---|
| Gün 1–15 | Anlaşılabilirlik | 20–30 aile çifti, gözlemli kurulum, izin/davet testi |
| Gün 16–30 | Günlük davranış | Widget kurulumu, saat ve hatırlatma testleri, D7 |
| Gün 31–45 | Devamlılık | Kontrollü 50–100 aile ölçeği, D30 ve yanlış uyarı analizi |
| Gün 46–60 | Organik edinim | Kullanıcı başlatmalı davet, landing ve App Store metni testi |
| Gün 61–75 | Ödeme isteği | Premium görüşmeleri ve şeffaf fiyat ilgisi testi |
| Gün 76–90 | Karar | Çalışan kanala küçük bütçe; uygunsa Premium geliştirme kararı |

Sayılar operasyonel hedeflerdir; istatistiksel güç garantisi değildir.

### Edinim ilkeleri

- Kullanıcı değil aile aktivasyonunu optimize et.
- Yetişkin çocuklar üzerinden edinim, yaşlı kullanıcıdan açık kabul.
- Korku ve suçluluk reklamı kullanma.
- Sağlık verisine göre reklam hedefleme yapma.
- Rehber tarama veya habersiz toplu davet yok.
- Hikâye ve fotoğraflar için ayrı yayın izni al.
- Consumer doğrulanmadan B2B panel geliştirme.

## 28. Fazlar

### Faz 1

Bu dosyadaki iOS MVP ve dört haftalık davranış doğrulaması.

### Faz 2

Widget iyileştirmeleri, çoklu yakın paneli, Premium, esnek programlar, SMS fallback, Apple Watch. Android talebi bu aşamada ayrıca değerlendirilir; otomatik geliştirme taahhüdü değildir.

### Faz 3

Kullanıcı onaylı rutin önerileri ve yalnızca check-in geçmişine dayanan dikkatli kişiselleştirme. Otomatik “iyiyim”, sağlık teşhisi veya gizli sensör takibi yok.

### Faz 4

Consumer doğrulanırsa bakım şirketleri ve diğer B2B modelleri için ayrı yetki, sözleşme, sorumluluk ve veri kullanım tasarımı.

## 29. Karar kayıtları

| ID | Karar | Durum |
|---|---|---|
| D-001 | Çalışma adı Herşey Yolunda | Kullanıcı seçimi; uygunluk doğrulanacak |
| D-002 | İlk platform iOS | Kullanıcı talebi |
| D-003 | Native SwiftUI + WidgetKit | Kullanıcının başlama talebiyle yerel geliştirmede uygulandı |
| D-004 | iOS 17+ tabanı | Pilot cihaz verisiyle doğrulanacak öneri |
| D-005 | NestJS + PostgreSQL modüler monolit | NestJS ve PostgreSQL adaptörü uygulandı; yerel doğrulama PGlite, üretim PostgreSQL açık |
| D-006 | Backend kaynaklı scheduler ve outbox | Tasarım ilkesi |
| D-007 | Kullanıcı beyanı olmadan check-in yok | Tasarım ilkesi |
| D-008 | Widget ve temel uyarılar ücretsiz | Ürün önerisi |
| D-009 | Ödeme ilk sprintlerde yok | Kapsam ilkesi |
| D-010 | Konum/sağlık/AI/chat yok | Kapsam ilkesi |
| D-011 | APNs ana push kanalı | iOS odaklı teknik öneri |
| D-012 | Aynı yerel güne sığan program | MVP sadeleştirme kararı; UX doğrulanacak |
| D-013 | Backend Firebase'e taşınacak (kullanıcı kararı) | CloudKit önerisi reddedildi; alan adı/sunucu istenmiyor. Fonksiyon tabanlı API + Firestore + FCM + Cloud Scheduler |
| D-014 | App Store dağıtımı için takım 5XR3QN2NJ6 | Kullanıcı tarafından bildirildi; yerel profillerde yok, Xcode hesaplarına eklenmeli. Geliştirme imzası 2HBFPNCMR8 kalır |
| D-015 | Backend Render + Neon ücretsiz katmanına gider | Kullanıcı kararı (Blaze kart gerektirdiği için reddedildi). Kart ve alan adı gerekmez; push APNs transport ile çalışmaya devam eder. Firebase iskeleti pasif bırakıldı |
| D-016 | Üretimde dış zamanlayıcı (SCHEDULER_MODE=external) | Render boşta 15 dk'da uykuya girer ve Neon 5 dk'da ölçeklenir; 15 sn'lik dahili tarama yerine korumalı /tick ucu dışarıdan tetiklenir |

## 30. Geliştirme öncesi açık kararlar

- [ ] Marka yazımı: Herşey Yolunda / Her Şey Yolunda.
- [ ] iOS minimum sürüm ve hedef pilot cihazlar.
- [ ] Native SwiftUI ve backend stack onayı.
- [ ] Apple Developer hesabı ve erişimler.
- [ ] Hosting bölgesi/sağlayıcısı.
- [ ] İsteğe bağlı Apple ile hesap koruma yetkileri ve kullanıcı kurtarma politikası. SMS sağlayıcısı kayıt için gerekmiyor.
- [ ] Veri sorumlusu tüzel/gerçek kişi ve hukuki metin sahipliği.
- [ ] KVKK aktarım mekanizması ve servis sözleşmeleri.
- [ ] Destek kanalı ve operasyon sorumlusu.
- [ ] Pilot katılımcı edinim yöntemi.
- [ ] Ücretsiz plan ilişki limitlerinin nihai UX davranışı.

Bu kararlar verilmeden gerçek servis hesabı açılmaz, ödeme yapılmaz veya üretim verisi işlenmez. Tasarım prototipi ve mock veriyle teknik denemeler ayrı yürütülebilir.

## 31. Tamamlanma tanımı

Bir özellik yalnızca ekranda görünmesiyle tamamlanmış sayılmaz.

- [ ] Kabul kriterleri karşılandı.
- [ ] İlgili unit/integration/UI testleri geçti.
- [ ] Erişilebilirlik kontrol edildi.
- [ ] Yetkilendirme ve veri minimizasyonu kontrol edildi.
- [ ] Loading/empty/error/offline durumları tasarlandı.
- [ ] Gerçek cihazda gerekli doğrulama yapıldı.
- [ ] Log/analytics hassas veri içermiyor.
- [ ] Bilinen kısıt ve açık hata kaydı var.
- [ ] İlgili plan maddesi ve karar kaydı güncellendi.

### Çalışma kuralları

- Uygulamadan önce ilgili sprint ve kapsam bu dosyadan seçilir.
- Yeni özellik otomatik olarak MVP'ye alınmaz; gerekçe ve faz belirtilir.
- Tamamlanmayan maddeler işaretlenmez.
- Teknik öneriler kesin karar gibi sunulmaz.
- Hukuk, ödeme, yetki veya üretim servisi kararları kullanıcıyla netleştirilir.
- Her sprint sonunda çalışan davranış, test sonucu ve açık sorunlar gözden geçirilir.

## 32. Kaynaklar ve doğrulama sınırları

Önceki araştırmada incelenen kaynaklar:

- Apple widget/App Intents: https://developer.apple.com/documentation/appintents/widgets-live-activities-and-controls
- Apple hesap silme: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- KVKK yurt dışına aktarım: https://www.kvkk.gov.tr/Icerik/2053/Yurtdisina-Aktarim
- İyiyim!: https://iyiyim.tech/
- İyiyim! Türkiye App Store: https://apps.apple.com/tr/app/id6773049004
- İyiyim! Google Play: https://play.google.com/store/apps/details?id=com.iyiyimtech.iyiyim
- İyiyim! gizlilik: https://iyiyim.tech/yasal/gizlilik/
- WozaiApp Türkiye App Store: https://apps.apple.com/tr/app/id6781736451
- Snug fiyatlandırma: https://snug.helpscoutdocs.com/article/61-snug-pricing
- Iamfine: https://dailycall.iamfine.com/
- StaySafe: https://www.ecoonline.com/ehs-software/lone-worker/lone-worker-app/

Platform kuralları, fiyatlar, rakip verileri ve hukuki uygulamalar değişebilir. Yayın ve sözleşme öncesi güncel birincil kaynaklar tekrar kontrol edilir.

## 33. Uygulama takip kaydı

### 15 Eylül 2026 — başlangıç

- Kullanıcı, plan üzerinden geliştirmeye başlanmasını ve doğrulanmış maddelerin işaretlenmesini onayladı.
- Xcode 26.6, Swift 6.3.3, Node 26.3.0, npm 11.16.0 ve XcodeGen mevcut; iOS 26.5 simülatörü kullanılabilir.
- Yerel geliştirme tercihi: SwiftUI + WidgetKit, iOS 17+, NestJS. Pilot cihaz ve marka uygunluk kararları açık kalır.
- Docker ve PostgreSQL CLI bulunmadı. Yerel test için gömülü PostgreSQL motoru; üretim için PostgreSQL adaptörü uygulanacak. Üretim PostgreSQL doğrulaması ayrı kalır.
- Dış bağımlılıklar: Apple Developer/APNs, SMS sağlayıcısı, hosting, hukuki inceleme, gerçek cihaz ve kullanıcı görüşmeleri. Bu maddeler tamamlandı işaretlenmeyecek.
- İşaretleme kuralı: Sprint içindeki geniş maddeler yalnızca tüm kabul kriterleri geçtiğinde kapatılır; kısmi yerel doğrulamalar burada ayrıca kaydedilir.

### Backend ilk doğrulama

- `backend`: NestJS API, PGlite yerel veritabanı ve PostgreSQL adaptörü oluşturuldu.
- `npm run verify`: TypeScript kontrolü ve 11 backend entegrasyon testi geçti.
- Doğrulananlar: OTP deneme kilidi, tek günlük kayıt, app/widget eşzamanlı tekrar, idempotency conflict, açık davet onayı, erişim iptali, pause/resume, ertesi gün programı, stale işlem reddi, refresh reuse, hesap silme, scheduler ve geç check-in.
- Üretim OTP/APNs henüz bağlı değil. Bildirim kaydı/outbox mevcut; gerçek gönderim tamamlandı sayılmaz.
- iOS SwiftUI uygulaması ve WidgetKit extension ilk simülatör derlemesini geçti.
- İmzasız build App Group erişimini engelledi; ad-hoc simülatör imzası korundu. Documents altındaki build çıktıları Finder metadata nedeniyle imzalanamadığından DerivedData `/tmp/HerSeyYolundaDerived` yoluna taşındı; güvenlik kontrolü gevşetilmedi.
- Ad-hoc imzalı `xcodebuild test` başarıyla tamamlandı (exit 0). Swift domain testleri ve yerel API'ye bağlı giriş → profil → check-in UI akışı çalıştırıldı. Ayrıntılı xcresult kaydı aşağıdaki son doğrulama bölümünde yer alır.
- Backend doğrulaması genişletildi: 17 test geçti; migration tekrar çalıştırma, push kabulü, retry/backoff, revocation, geçersiz cihaz ve dead-letter testleri eklendi. APNs bu testlerde sahte transport kullanır; canlı teslimat doğrulanmış değildir.
- Ayrı gerçek HTTP testi auth/validation/davet/check-in/ilişki iptali/silme zincirinde geçti. Sadece bu testin oluşturduğu sentetik hesaplar temizlendi.
- `npm audit`: 0 bilinen açık. NestJS 11.2.3 ve Multer 2.3.0 sabitlendi; güvenlik politikaları değiştirilmedi.

### Son doğrulama — 15 Eylül 2026

| Kontrol | Sonuç | Kanıt / sınır |
|---|---|---|
| TypeScript | Geçti | `npm run build` |
| Backend veritabanı/iş kuralı testleri | 22/22 geçti | `npm run verify`; PGlite |
| Gerçek HTTP entegrasyonu | 1/1 geçti | `npm run test:http`; loopback API |
| iOS otomatik testler | 10/10 geçti; 0 atlanan | 8 unit/transport/AppIntent + 2 XCUITest, iPhone 17 Pro / iOS 26.5 |
| Widget AppIntent | Geçti | Dünkü snapshot → bugünkü API kaydı, tekrarda tek kayıt; SpringBoard/gerçek cihaz testi değildir |
| Eşzamanlılık | 100 istekte 1 check-in | Deadline worker ile birlikte; üretim yük/SLO testi değildir |
| Restart / kalıcılık | Geçti | Check-in ve kuyruk korunuyor; silinen hesap yeniden açılmıyor. Backup restore tatbikatı değildir |
| Dependency audit | 0 bilinen açık | `npm audit` |
| Release simülatör derlemesi | Geçti | Ad-hoc imzalı build; store archive değildir |
| Plist/entitlements/manifest | Geçti | `plutil -lint` |
| CI tanımı | YAML doğrulandı | Uzak GitHub çalışması yapılmadı |

Son iOS sonuç paketi: `/tmp/HerSeyYolundaDerived/Logs/Test/Test-HerseyYolunda-2026.09.15_17-28-06-+0300.xcresult`. Sonuç `xcresulttool get test-results summary` ile kontrol edildi. `/tmp` sonuçları sistem temizliğiyle silinebilir; testler bu bölümdeki çalıştırma komutlarıyla yeniden üretilebilir.

Yerel çalışma sürümü hazırdır; consumer MVP'nin canlı hizmet ve saha doğrulaması henüz tamamlanmamıştır. Gerçek kişisel veriyle veya bir güvenlik hizmeti gibi kullanılmamalıdır.

### Yerel uygulama kapsamı ve bilinçli teknik sadeleştirmeler

- iOS: SwiftUI giriş/profil, check-in, aile daveti, yakın listesi/detayı, geçmiş, program, pause/resume, tercihler, oturumlar, export/silme, gizlilik taslağı ve widget rehberi.
- Widget: Aynı API istemcisini kullanan AppIntent, shared Keychain, App Group cache, oturum kilidi, dünkü kaydı bugünkü başarı gibi göstermeyen timeline ve bilinçli check-in. SpringBoard üzerinden gerçek widget dokunuşu ve fiziksel cihaz ayrıca doğrulanmalıdır.
- Backend: NestJS, PGlite disk kalıcılığı, PostgreSQL adaptörü, 5 sürümlü migration, ilişki bazlı yetki, scheduler, per-device notification delivery, retry/lease ve APNs adaptörü. v5 eski verileri koruyarak telefonsuz kayıt ve davet kodu desteği ekler.
- `users` tablosunda tek kullanıcı/tek profil bilgileri birlikte tutulur; Profile API modeli ayrıdır. `notifications` transactional outbox görevi görür; henüz ayrı bir genel amaçlı OutboxEvent tablosu gerekmedi.
- JWT yerine sunucuda hash'lenmiş opaque access/refresh session token'ları kullanıldı; rotasyon, expiry ve reuse iptali test edildi.
- Veri export'u şimdilik doğrulanmış hesap üzerinden JSON cevabıdır; geçici dosya servisi gerektirmez. Büyük export iş kuyruğu MVP sonrası değerlendirilebilir.
- Davet paylaşımı ShareLink, özel URL şeması, yerel QR ve 12 karakterli tek kullanımlı kod ile çalışır. Universal Links ve mağazaya yönlenen fallback, doğrulanmış domain seçimi bekler. Yurt dışı kullanım için internetten erişilebilen HTTPS backend ayrıca gerekir.
- Üçüncü taraf analitik SDK'sı eklenmedi. İsteğe bağlı tercih kaydı mevcut; tam KPI paneli ve operasyon alarm bağlantısı açık.
- DB transaction'ları MVP'de tek advisory lock ile sıralanır. 100 eşzamanlı istek testi üretim ölçeklenebilirliği veya RPO/RTO kanıtı değildir.
- APNs gönderimi varsayılan kapalıdır. Release API adresi boş bırakılmıştır. v1.2'de cihaz hesabı oluşturma SMS gerektirmez; eski OTP endpoint'leri tüm ortamlarda 410 döndürür.

### Çalıştırma ve doğrulama

- Xcode projesi: `ios/HerseyYolunda.xcodeproj`.
- Projeyi yeniden üretme: `cd ios && xcodegen generate`.
- Yerel API: `cd backend && npm run dev`; varsayılan `127.0.0.1:3000`. HOST ortam değişkeni önceki cihaz kurulumu için eklenmiştir; mevcut doğrulama yalnızca loopback'te yapılır.
- v1.2 izole API: `LOCAL_DATABASE_PATH=/tmp/hersey-name-auth-db PORT=3100 HOST=127.0.0.1 node --import tsx src/main.ts`. Bu test veritabanı mevcut hesap yedeğinin yerine geçmez.
- Yerel testte yalnızca bir deneme adı girin; telefon ve OTP yoktur. Gerçek veri kullanılmamalıdır.
- Backend doğrulama: `cd backend && npm run verify`.
- API çalışırken HTTP testi: `cd backend && npm run test:http`.
- Güvenlik taraması: `cd backend && npm audit`.
- iOS v1.2 test: `cd ios && xcodebuild -project HerseyYolunda.xcodeproj -scheme HerseyYolunda -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/HerSeyYolundaNameAuth HY_API_URL=http://127.0.0.1:3100/v1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO test`.
- İzole API için HTTP test: `HY_TEST_API_URL=http://127.0.0.1:3100/v1 npm run test:http`.
- iOS UI ve AppIntent entegrasyon testleri için yerel backend önce başlatılmalıdır.
- İmzalı simülatör Release derlemesi başarıyla tamamlandı. Bu, gerçek cihaz archive/TestFlight doğrulaması değildir.
- App icon: 1024×1024, alpha kanalı yok; üretici kod `scripts/render-icon.swift`.
- Info.plist, entitlement ve privacy manifest dosyaları `plutil -lint` kontrolünden geçti.

### Gerçek iPhone kurulum ön kontrolü — 15 Eylül 2026

- Xcode'un son seçilmiş geliştirme takımı bulundu; takım parametresi yalnızca derleme komutuna verildi, proje takım ayarı kalıcı değiştirilmedi.
- Atahan iPhone'u (iPhone 15 Pro) eşleştirilmiş cihaz olarak kayıtlı; `devicectl` bağlantı durumunu `unavailable`, tüneli `unavailable` raporladı. Xcode kurulum hedefleri arasında fiziksel telefon görünmedi.
- Kayıtlı cihaz bilgisinde Geliştirici Modu açık. Kayıtlı bilgi canlı bağlantı kanıtı değildir.
- Gerçek cihaz SDK'sıyla imzalı build denendi. Mevcut `iOS Team Provisioning Profile: *` profilinde App Groups capability/entitlement bulunmadığı için uygulama ve widget hedefleri derlenemedi.
- App Group veya Keychain güvenlik yetkileri kaldırılmadı. Apple hesabı üyelik/takım yetkisi ve uygun provisioning profili doğrulanmalı; otomatik profil güncellemesi henüz çalıştırılmadı.
- İlk kontrolde telefonun canlı bağlantısı yoktu; aşağıdaki takip kontrolünde bağlantı kuruldu. Gerçek telefona uygulama kurulmuş sayılmaz.

### Telefon bağlandıktan sonraki kontrol

- Kullanıcı telefonu bağladıktan sonra `devicectl` durumu `available (paired)` ve tüneli `connected` raporladı; Geliştirici Modu açık.
- Canlı cihaz iOS 27.0 beta, kurulu Xcode 26.6. Cihaz bilgisi sorgusu `The developer disk image could not be mounted on this device` uyarısı verdi; DDI servisleri kullanılamıyor. Sürüm/cihaz destek paketi uyumluluğu ayrıca çözülmeli.
- Yenilenen Xcode hedef listesinde fiziksel telefon hâlâ kurulum hedefi olarak sunulmadı.
- Gerçek cihaz build yeniden denendi; mevcut wildcard provisioning profilinde App Groups yetkisi bulunmadığı için yine durdu.
- Bağlantı kısa süreli kuruldu ancak sonraki lockState sorgusu cihazı bulamadı; son `devicectl list devices` tekrar `unavailable` raporladı. Kararlı bağlantı ve DDI desteği açık.
- Kullanıcı otomatik provisioning güncellemesine açıkça onay verdi. `xcodebuild -allowProvisioningUpdates` mevcut takımla çalıştırıldı.
- Güncelleme denemesi ardından Xcode uygulama ve widget için ayrı `iOS Team Provisioning Profile: com.herseyyolunda.app` ve `.widget` profillerini seçti. Build bu kez profillerin `com.apple.security.application-groups` değerinin projedeki entitlement ile eşleşmemesi nedeniyle başarısız oldu.
- Apple App Group kimliği ve her iki App ID'ye bağlanması doğrulanmalı. Sistem bileşeni güncellemesi, güvenlik yetkisi kaldırma veya gerçek cihaza kurulum yapılmadı.
- Xcode arayüzünü System Events ile inceleme denemesi macOS tarafından `osascript için yardımcı erişime izin verilmiyor (-1728)` hatasıyla engellendi. GUI üzerinden devam için çalıştıran uygulamaya Erişilebilirlik/Otomasyon izni kullanıcı tarafından verilmelidir.

### macOS otomasyon izni sonrası kontrol

- Kullanıcı izin verdikten sonra Xcode pencere ve Apple Accounts ekranı erişilebilirlik API'sinden okunabildi; önceki yardımcı erişim engeli kalktı.
- Xcode takım ekranında Developer Team / Admin bilgisi görüldü. Bu bilgi tek başına ücretli üyelik veya App Groups yetkisinin doğrulaması olarak kullanılmadı.
- Proje editöründeki Signing & Capabilities denetimleri mevcut erişilebilirlik ağacında güvenilir biçimde elde edilemedi; App Group işaretleri körlemesine değiştirilmedi.
- Görsel doğrulama için ekran yakalama denemesi başarısız oldu; `CGPreflightScreenCaptureAccess()` ekran kaydı iznini `false` raporladı. Erişilebilirlik ve ekran kaydı izinleri ayrı.
- Telefon son bağlantı kontrolünde hâlâ erişilemez. Gerçek cihaza kurulum tamamlanmadı.

### Kullanıcı/sağlayıcı gerektiren yayın engelleri

| Engel | Neden açık? | Devam için gerekli |
|---|---|---|
| Apple Developer / gerçek cihaz | Team, provisioning, App Group, shared Keychain ve push yetkileri gerçek cihazda doğrulanmadı | Apple hesabı ve test iPhone'u |
| Hesap koruma / kurtarma | Yeni giriş SMS'siz; Apple ile bağlama henüz yok | Apple Sign In yetkisi, backend token doğrulama ve kurtarma akışı |
| Alan adı / canlı HTTPS sunucu | Davet kodu ve web varlıkları hazır; gerçek domain, DNS ve sunucu yok | Domain satın alma kararı, sunucu (VPS vb.) veya yönetilen hosting + DNS A kaydı |
| Universal Links etkinleştirme | AASA dosyası, Caddy yapılandırması ve link kodu hazır; entitlement bağlanmadı | Domain belirlendikten sonra Xcode'da Associated Domains (`applinks:domain`) eklenip yeniden derleme |
| App Store listesi | Açılış sayfası mağaza düğmesi placeholder olarak hazır | App Store Connect kaydı, inceleme süreci ve liste bağlantısının `web/public/index.html` içine yazılması |
| Üretim PostgreSQL / hosting | Docker/PostgreSQL servisi yok; yerel testler PGlite üzerinde | Seçilmiş hosting, DB/TLS ve backup politikası |
| KVKK / marka | Veri sorumlusu, aktarım sözleşmeleri, marka/domain uygunluğu kesinleşmedi | Hukuk incelemesi ve kullanıcı ticari bilgileri |
| Gerçek kullanıcı / erişilebilirlik | Otomatik testler yaşlı kullanıcı görüşmesinin yerini tutmaz | Pilot aileler, VoiceOver ve eski iOS cihazları |
| CI / TestFlight | Workflow yazıldı; uzak runner ve mağaza erişimi yok | Uzak repo ve Apple yayın yapılandırması |

Bu engeller tamamlandı olarak işaretlenmez. Yedekten geri yüklemede silme tombstone'ları, üretim cihaz hesabı abuse kontrolleri, Apple ile hesap kurtarma ve tam operasyon alarmı ayrıca üretim hazırlık işidir.

### v1.2 uygulama ve doğrulama kaydı — 15 Eylül 2026

- [x] `POST /auth/device`: Ad ve rol tercihiyle sunucuda UUID hesap oluşturulur. Aynı isimli hesaplar birbirinden ayrıdır; ID/isim oturum yerine geçmez.
- [x] 256-bit cihazda üretilen kayıt anahtarı Keychain'de saklanır; 10 dakika içinde aynı kayıt yeniden denenebilir. Kayıt tekrarı aynı hesabı korur; eski oturumu iptal edip yeni token'lar verir. Çıkış/oturum iptali eski kayıt anahtarıyla aşılamaz.
- [x] Migration v5: Yeni hesaplarda telefon alanları nullable. Eski hesap, telefon kaydı, session, relationship ve check-in verileri silinmez. v4 → v5 geçişi ayrı test fixture'ında doğrulandı.
- [x] Eski OTP endpoint'leri kaldırıldı (410). Geçerli eski access/refresh oturumları çalışmaya devam eder.
- [x] Davetler 48 saat geçerli token + 12 karakterli okunabilir kod taşır. Kod hash'i saklanır; başarısız tahminler de rate limit tüketir. Hesap ID'siyle davet kabul edilmez.
- [x] iOS: Adla giriş, kullanım tercihi, ShareLink, QR, kod/bağlantı yapıştırma, ID bilgi ekranı, kurtarma sınırları ve güçlü çıkış uyarısı.
- [x] QR içeriği CoreImage ile üretilip testte tekrar çözülerek link ile eşitliği doğrulandı; uygulama kamera izni istemez.
- [x] `npm run verify`: TypeScript ve 32 backend testi geçti. Aynı isim bağımsızlığı, kayıt retry, tahmin limiti, iptal edilmiş session, migration ve önceki check-in kuralları dahil.
- [x] Yeni giriş modeliyle gerçek HTTP entegrasyon testi geçti (izole loopback API).
- [x] iOS simülatör testleri: 12/12 geçti, 0 atlanan. Giriş → check-in → davet/QR/kod → program akışı, büyük yazı, AppIntent, link ayrıştırma ve QR çözümleme dahil.
- [x] Release simülatör derlemesi ve privacy manifest plist kontrolü geçti; `npm audit` 0 bilinen açık raporladı.
- [ ] Apple ile hesabı koruma: Henüz uygulanmadı. UI'da çalışıyor gibi gösterilmiyor; yetki ve backend doğrulama entegrasyonu ayrı yapılacak.
- [ ] Evrensel HTTPS davet bağlantısı ve mağaza kurulumundan sonra davete devam etme: Domain/hosting seçimi bekler. Mevcut özel link yalnızca uygulama yüklüyken açılır.
- [ ] Mevcut veri yedeğine canlı migration uygulama ve yeni sürümü gerçek iPhone'a tekrar yükleme: Bu revizyon kapsamında yapılmadı.

Son iOS sonuç paketi: `/tmp/HerSeyYolundaNameAuth/Logs/Test/Test-HerseyYolunda-2026.09.15_23-31-35-+0300.xcresult`.

Veri koruma notu: Önceki kurulum sırasında yerel DB `.data.bak-1789502779` adına taşınmıştı. Bu revizyonda yedek silinmedi, değiştirilmedi veya otomatik geri yüklenmedi. Yedek dizinleri gitignore'a eklendi. Kontroller `/tmp/hersey-name-auth-db` üzerinde ayrı örneklerle yapıldı; eski kullanıcının bu izole sunucuya bağlanması hesap taşıma sayılmaz.

Ortam notu: İlk Node/TypeScript çalıştırmalarında paket dosyası okuma gecikmesi gözlendi; process sample `node_modules/zod/v4/classic/parse.d.cts` dosyası okumasını gösterdi. Kontroller sonradan tamamlandı; veritabanını silme veya güvenlik kontrollerini gevşetme uygulanmadı. Eski telefonlu 3000-port test süreci kapatıldı; v1.2 izole sunucusu 127.0.0.1:3100'da çalıştırıldı.

### v1.3 uygulama ve doğrulama kaydı — 15 Eylül 2026

#### HTTPS davet bağlantısı ve mağaza yönlendirmesi

- [x] `InvitationInput`: Davet bağlantıları artık `https://<domain>/invite?token=...` biçiminde üretiliyor. Domain yapılandırılmamışsa geriye uyumlu olarak özel `herseyyolunda://` şeması kullanılıyor (`HYInviteDomain` Info.plist anahtarı / `HY_INVITE_DOMAIN` build ayarı).
- [x] HTTPS davet bağlantıları (ve `/invite/` varyantı) uygulama içinde ayrıştırılıyor; yalnız geçerli tek token kabul ediliyor. Yalnız `https` kabul edilir — `http` davet bağlantısı reddedilir. Çift token ve farklı path reddedilir.
- [x] `web/public/.well-known/apple-app-site-association`: Team/App ID (`2HBFPNCMR8.com.herseyyolunda.app`) `/invite` path'i için tanımlı; JSON doğrulandı. Apple'ın gerektirdiği biçimde `components` ve legacy `paths` birlikte içerir.
- [x] `web/public/index.html`: Türkçe açılış sayfası — uygulama yüklüyse özel şema ile açma düğmesi, yüklü değilse App Store düğmesi (mağaza listesi yoksa bilgi notu), acil hizmet uyarısı, `noindex`. Token sayfada gösterilmez; sunucu tarafında loglanmaz.
- [x] `web/Caddyfile`: AASA'nın `application/json` olarak sunulması, `/invite` path'inin açılış sayfasına rewrite edilmesi, `/v1/*` API reverse-proxy'si, güvenlik başlıkları ve otomatik HTTPS.
- [x] NOT: Associated Domains entitlement (`applinks:domain`) henüz projeye eklenmedi — domain belirlenmeden eklenmesi provisioning hatasına yol açar. Domain seçildikten sonra eklenmelidir.
- [x] Universal Links'in cihazda çalışması için ayrıca şartlar: gerçek HTTPS sunucu, doğrulanmış AASA (yönlendirmesiz, `application/json`), entitlement ve uygulamanın yeniden kurulmuş olması.

#### Gerçek iPhone'a yeniden kurulum

- [x] v1.2 kodu (adla cihaz hesabı, SMS'siz giriş) gerçek iPhone 15 Pro'ya derlendi, kuruldu ve başlatıldı (`devicectl install` + `launch` başarılı; exit 0).
- [x] LAN backend'i v1.2 modunda `0.0.0.0:3000` üzerinde çalışıyor; Mac'in LAN adresinden (`192.168.1.7:3000/v1/health`) sağlık kontrolü geçti. Telefon aynı Wi-Fi ağındayken uygulamaya `http://192.168.1.7:3000/v1` üzerinden erişilir.
- [x] Debug derlemesinde `APIClient` yalnız localhost ve özel LAN IP aralıklarına (10.x, 172.16–31.x, 192.168.x) HTTP'ye izin verir; Release yalnız `https` kabul eder. Sabit IP listesi kaldırıldı.
- [x] Bu kurulum taze yerel veritabanı (`.data`) kullandı; `.data.bak-1789502779` yedeğine dokunulmadı. Eski kurulumdaki hesaplar aktif sunucuda yoktur — telefon uygulaması yeni hesap oluşturmayı bekler.
- [x] iOS simülatör testleri yeni davet koduyla 12/12 geçti (sonuç paketi: `/tmp/HerSeyYolundaNameAuth/Logs/Test/Test-HerseyYolunda-2026.09.15_23-41-40-+0300.xcresult`).

#### Dağıtım paketi (yurt dışı dahil internetten erişilebilen HTTPS backend)

- [x] `backend/Dockerfile`: Node 24 Alpine, `npm ci`, healthcheck (`/v1/health`), non-root kullanıcı, tsx ile çalıştırma.
- [x] `docker-compose.yml`: PostgreSQL 17 (healthcheck'li) + API + Caddy (otomatik Let's Encrypt TLS). `DOMAIN`, `POSTGRES_PASSWORD`, `DATA_ENCRYPTION_KEY`, `LOOKUP_KEY`, APNs değişkenleri `.env` üzerinden zorunlu.
- [x] `backend/.env.example`: Tüm üretim değişkenleri açıklamalı; anahtar üretimi (`openssl rand -hex 32`) ve şifre anahtarı değişimi uyarısı dahil.
- [x] YAML ve AASA JSON sözdizimi doğrulandı. Docker yerel kurulu olmadığından imaj derlemesi ve uçtan uca TLS doğrulaması yapılamadı — canlı sunucuda yapılmalıdır.
- [ ] Canlı sunucuya deploy: domain + sunucu kararı ve DNS ayarı gerekir (aşağıdaki adımlar).

#### Canlı yayınlama adımları (kullanıcı kararları bekleniyor)

1. Alan adı seçimi ve satın alımı (ör. `herseyyolunda.com`).
2. Bir VPS/hizmet sağlayıcı (DigitalOcean, Hetzner, AWS vb.) veya yönetilen hosting kararı.
3. DNS A kaydının sunucu IP'sine yönlendirilmesi.
4. Sunucuda: `cp backend/.env.example .env` → değerleri doldur → `docker compose up -d --build`.
5. Doğrulama: `https://<domain>/v1/health` ve `https://<domain>/.well-known/apple-app-site-association`.
6. Xcode'da Associated Domains yeteneğine `applinks:<domain>` eklenip yeniden derleme (ücretli Apple Developer Program gerektirebilir).
7. `ios/project.yml` içinde `HY_INVITE_DOMAIN: '<domain>'` ayarlanıp yeniden derleme (https davet linkleri).
8. App Store Connect kaydı, inceleme süreci ve mağaza bağlantısının `web/public/index.html` içindeki `APP_STORE_URL` sabitine yazılması.
9. APNs üretim anahtarları (`.p8`) alınıp `.env`'e girilmesi; `APNS_ENABLED=true`.

### v1.4 uygulama ve doğrulama kaydı — 15 Eylül 2026 (Firebase geçiş kararı)

#### Karar ve mimari

- [x] Kullanıcı kararı: Backend Firebase'e taşınır (D-013). Gerekçe: alan adı ve sunucu istenmiyor. CloudKit önerisi (sunucusuz/domainsiz/ücretsiz ama istemci yeniden yazımı gerektiren yol) kullanıcı tarafından tercih edilmedi.
- Mimari eşleme (NestJS → Firebase):
  - REST API (NestJS) → **Cloud Functions (HTTPS)** — istemci tarafında yalnız API kök adresi değişir; mevcut `APIClient`, widget ve testlerin büyük bölümü korunur.
  - PostgreSQL/PGlite → **Cloud Firestore** (koleksiyonlar: users, sessions, checkins, invitations, relationships, notifications, devices, account_registrations).
  - APNs transport → **Firebase Admin Messaging (FCM)**.
  - `service.tick()` (setInterval) → **Cloud Scheduler** → HTTP tetiklemeli işlev (kaçırılan check-in taraması).
- Güvenlik duruşu: **İstemciler doğrudan Firestore'a erişemez** (deny-all güvenlik kuralları). Tüm erişim Admin SDK ile işlevler üzerinden; mevcut cihaz hesabı + Bearer oturum modeli aynen taşınır.

#### Oluşturulan iskelet (doğrulandı)

- [x] `firebase.json` (Firestore + Functions + emülatör yapılandırması; JSON doğrulandı)
- [x] `firestore.rules` (deny-all) ve `firestore.indexes.json` (JSON doğrulandı)
- [x] `functions/` (package.json, tsconfig.json, `src/index.ts` — bölge `europe-west1`, sağlık kontrolü işlevi ve port haritası; JSON'lar doğrulandı)
- [x] `.gitignore` güncellendi (functions derleme çıktıları, `.firebase/`, `google-service.json`)
- [x] NOT: `firebase-admin`/`firebase-functions` sürümleri ilk `firebase deploy` öncesinde güncel majörlere sabitlenip doğrulanmalı; iskelet bu nedenle "kurulum doğrulandı" düzeyindedir.

#### Kullanıcı tarafından yapılması gerekenler (Google tarafı — yalnız hesap sahibi yapabilir)

1. Google hesabıyla [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → ör. `hersey-yolunda` (Analytics isteğine "devre dışı" denebilir).
2. Proje içinde **Blaze (pay-as-you-go) plana geç** — Cloud Functions ve Cloud Scheduler için zorunlu. MVP ölçeğinde ücretsiz kotalar içinde kalınır; kart bilgisi ister, gerçek maliyet ~0.
3. **Build → Firestore Database → Create database** → bölge olarak **`europe-west1` (Belgium)** seç (KVKK: veri yerleşimi Avrupa'da kalsın) → güvenlik kuralları "production mode" ile başla.
4. **Project settings → Your apps → iOS** → Bundle ID: `com.herseyyolunda.app` → **GoogleService-Info.plist** dosyasını indir.
5. **App Store dağıtım takımı**: Xcode → Settings → Accounts'a `5XR3QN2NJ6` takımının hesabını ekle (yerel profillerde bulunamadı; gönderim aşamasında imzalama ona çevrilecek).

#### Kullanıcı adımlarının durumu — 16 Eylül 2026

- [x] Firebase projesi oluşturuldu: **`hersey-yolunda-51cb2`** (kullanıcı ekran görüntüsüyle doğrulandı).
- [x] Firestore veritabanı oluşturuldu (kullanıcı ekran görüntüsüyle doğrulandı; bölge `europe-west1` olarak seçildiği varsayıldı — deploy öncesi teyit edilecek).
- [x] iOS uygulaması kaydedildi ve **GoogleService-Info.plist indirildi**; `ios/App/` altına kopyalanıp doğrulandı (PROJECT_ID: `hersey-yolunda-51cb2`, BUNDLE_ID: `com.herseyyolunda.app`, plist lint OK).
- [ ] **Blaze planı hâlâ doğrulanmadı** (kullanıcı ekranında Spark görünüyordu). Cloud Functions deploy edilmeden önce Blaze'e geçilmeli.
- [ ] Fiyatlandırma sorgusu (16 Eylül 2026): Kullanıcı "Blaze'siz ücretsiz Spark ile çalışamaz mıyız?" dedi. Firebase dokümanlarıyla doğrulandı: **Cloud Functions yalnız Blaze planında** (deploy için şart; resmi doküman: "your project must be on the Blaze pricing plan"); Spark'ta istemciden doğrudan Firestore kullanılabilir ama **FCM push gönderilemez** ve zamanlayıcı çalışmaz — yani aileye bildirim düşmez, ürünün ana vaadi yerine gelmez. Blaze'in ücretsiz kotaları Spark ile aynı (Functions 2M çağrı/ay, 400K GB-saniye, 5 GB çıkış; Firestore 50K okuma/20K yazma/gün); MVP ölçeğinde fatura ~0, kart yalnız kota aşımına karşı istenir. Karar kullanıcıya sunuldu.
- [ ] Xcode hesaplarına `5XR3QN2NJ6` takımı eklenmedi (App Store gönderim aşaması).

#### iOS Firebase entegrasyonu (doğrulandı)

- [x] `ios/project.yml`: firebase-ios-sdk SPM paketi (`from: 12.5.0`) eklendi; hedef ürünler `FirebaseCore` + `FirebaseMessaging` (yalnız ana uygulama; widget Firebase'siz kalır). `FirebaseAppDelegateProxyEnabled: NO` eklendi.
- [x] `NotificationDelegate`: `FirebaseApp.configure()`, `MessagingDelegate` ile FCM token alımı (UserDefaults'a `fcmToken` olarak saklanıyor — Functions portunda kullanılacak), APNs token'ının FCM'ye aktarımı. Mevcut APNs/oturum akışı korundu.
- [x] GoogleService-Info.plist uygulama paketine kaynak olarak ekleniyor.
- [x] Derleme ve tam test paketi doğrulandı: **12/12 test geçti** (sonuç paketi: `/tmp/HerSeyYolundaFirebase/Logs/Test/Test-HerseyYolunda-2026.09.16_09-40-35-+0300.xcresult`). Önceki `token()` kullanımındaki deprecation, resmi `MessagingDelegate` yöntemiyle giderildi.
- [ ] FCM token'ı henüz backend'e gönderilmiyor; gerçek push teslimatı Functions portuyla gelecek. Bu adım tamamlanmadan "push çalışıyor" denmez.

#### Test ortamı notu — kayıt hız limiti

- iOS entegrasyon testleri uzun süre açık bir yerel sunucuda art arda çalıştığında **saatlik 10 hesap/IP kayıt limiti** dolabiliyor (`rate_limited`). Çözüm: taze `LOCAL_DATABASE_PATH` ile yeni test sunucusu veya az kullanımlı mevcut sunucu (3000) kullanıldı; son koşu 3000'e karşı yapıldı ve 12/12 geçti. Bu sınır kasıtlı bir kötüye kullanım korumasıdır; test kolaylığı için zayıflatılmadı.

#### Dürüst kısıtlar ve açık işler

- [ ] Google projesi oluşturulmadan: işlev derlemesi, FCM, Firestore okuma/yazma ve uçtan uca doğrulama **yapılamaz** — port "tamamlandı" olarak işaretlenmez.
- [ ] `GoogleService-Info.plist` iOS projesine eklenmeli; `functions` tam portu (auth/device, check-in idempotency, davet akışı, scheduler, FCM) proje açıldıktan sonra yapılacak.
- [ ] KVKK: Google (Firebase) veri işleyen olarak değerlendirilmeli; Firebase Data Processing Terms incelenmeli, Firestore bölgesi Avrupa'da tutulmalı, aydınlatma metni buna göre güncellenmeli. Bu bir hukuk incelemesi gerektirir; geliştirme öncesi netleştirilmeli.
- [ ] Blaze planı kart gerektirir; kullanım ücretsiz kotaları aşarsa maliyet doğar (MVP ölçeğinde beklenmez).
- [ ] Mevcut NestJS backend yerel testler için korunur; Firebase portu doğrulanana kadar silinmez.

### v1.5 uygulama ve doğrulama kaydı — 16 Eylül 2026 (canlıya çıkış hazırlığı)

#### iCloud sorunu ve proje taşınması

- Kullanıcı: "iCloud ile uygulamanın bir bağı olmasın." Teşhis: `~/Documents` iCloud Drive "Desktop & Documents" senkronizasyonu altında; disk ~12 GB boş olunca dosyalar "dataless" duruma düşüyor ve okumalar ~1 sn/file seviyesine çıkıyor. Bu, oturumdaki tüm gizemli takılmaların (sunucu açılışı, tsc, derleme) kök nedeniydi.
- Proje `~/Documents/Herşey Yolunda` → **`~/Herşey Yolunda`** taşındı (6 dk 21 sn; File Provider tüm dosyaları yerelleştirdi). Aynı dosya eskiden 1.27 sn, artık 4 ms okunuyor. Proje artık iCloud senkronizasyonu dışında; geri taşınmamalı.
- Uygulamanın kendisi zaten iCloud bağı yok (CloudKit yok, D-015 Render kararı). Sorun yalnızca geliştirme klasörü konumundaydı.
- Not: LAN IP değişti (192.168.1.7 → 10.23.17.172, farklı ağ). iOS Debug API adresi artık `http://Atahan-MacBook-Air.local:3000/v1` — modem değişimlerine dayanıklı; `isLANHost` artık `.local` adlarını kabul ediyor (+DomainTests; tam simülatör koşusu canlı URL ile yapılacak).

#### Render/Neon kararı (D-015) ve zamanlayıcı (D-016)

- Kullanıcı Blaze'i (kart gerektirdiği için) reddetti ve **Render + Neon** yolunu seçti; ardından "direk canlıya alalım" talimatı verdi.
- Hız için Render'ın kendi ücretsiz Postgres'i kullanılıyor (render.yaml `databases` bloğu; DATABASE_URL blueprint ile otomatik bağlanır — ayrı Neon hesabı şart değil). **Üretim DB'si 30 gün sonra silinir**; ciddi kullanımda Neon'a geçilecek (PLAN'da belgelendi).
- `SCHEDULER_MODE=external`: üretimde dahili 15 sn'lik tarama kapalı; korumalı `POST /v1/tick` ucu (TICK_SECRET + timingSafeEqual) dışarıdan tetikler. /tick transaction dışında çalışır — iç içe transaction PGlite'da kilitlenir (test yakaladı, düzeltildi).
- Neon uyku sorununa çözüm: tarama 10 dk'da bir tetiklenir → Render uyanık kalır (750 saat/ay, bir servis 24/7'ye yeter), Neon/CU bütçesi korunur.
- `.github/workflows/tick.yml`: GitHub Actions her 10 dk'da bir `/v1/tick`'i çağırır (`secrets.TICK_SECRET`, `vars.API_URL`). Yoğunlukta gecikebilir; daha hassas zamanlama gerekirse cron-job.org (PLAN'da not).

#### Doğrulananlar

- Backend: **33/33 test** (yeni `/tick` ucu: yanlış anahtar 403, doğru anahtar tick çalışır, anahtar yok 404). PGlite/PostgreSQL `sslmode=require` desteği (Neon uyumu).
- Git deposu açıldı: ilk commit `ff7823d` (62 dosya), ikinci `95b4249` (Render Postgres blueprint + tick workflow + .local adresi). Bayat `HerseyYolunda 2/3.xcodeproj` kopyaları depoya alınmadı (gitignore; Finder'dan silinebilir).
- Render için 3 gizli anahtar üretildi (sohbette kullanıcıya verildi; depoya asla girmez).
- `gh` CLI kuruldu (v2.101.0); kimlik doğrulama kullanıcıyı bekliyor.

#### Canlıya çıkış adımları (kalan)

1. Kullanıcı: `gh auth login` (tarayıcı, ~30 sn).
2. Devin: repo oluştur + push + `TICK_SECRET` repo secret'ı (görünürlük kararı: public = Actions sınırsız; private = 2000 dk/ay).
3. Kullanıcı: render.com → GitHub ile üye → **New → Blueprint** → repo seç → 3 anahtarı yapıştır → Apply (DATABASE_URL otomatik).
4. Devin: `API_URL` repo değişkenini ayarla; tick workflow'u elle tetikleyip doğrula.
5. Devin: iOS Release derlemesi `HY_API_URL=https://<servis>.onrender.com/v1` ile → gerçek iPhone'a kurulum → canlı aile testi.
6. Sonrası: APNs .p8 anahtarı (canlı push), App Store gönderimi (5XR3QN2NJ6 takımı).
- Uyarı: 30 gün DB sınırı; GitHub Actions zamanlaması yoğunlukta gecikebilir (cron-job.org yedek).

#### Release yapılandırması (16 Eylül 2026)

- `ios/project.yml` Release `HY_API_URL` artık `https://hersey-yolunda-api.onrender.com/v1` (render.yaml servis adından türetilen adres; Render deploy'u tamamlanınca çalışır). Widget'taki bayat `192.168.1.7` ATS istisnası kaldırıldı; Debug LAN adresi (`Atahan-MacBook-Air.local:3000`) geliştirme için korunuyor.
- Doğrulama: `xcodegen generate` + `xcodebuild -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/HerSeyYolundaRelease CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build` → **BUILD SUCCEEDED**. Derlenen Info.plist'te `HYAPIURL=https://hersey-yolunda-api.onrender.com/v1` doğrulandı; Release sürümü iPhone 17 Pro simülatörüne kurulup başlatıldı (PID 17245). Render deploy'u yapılmadığı için uygulama "İşlem tamamlanamadı" gösteriyor — beklenen davranış; servis ayağa kalkınca çalışır.
- Kalan kullanıcı adımları değişmedi: `gh auth login` → repo push → render.com Blueprint + 3 gizli anahtar → `API_URL` repo değişkeni → canlı doğrulama.

#### Canlı deploy kaydı — 16 Eylül 2026 (Render API ile)

- GitHub: `gh auth login` (kullanıcı `athnkntk`), repo **public** oluşturuldu: `github.com/athnkntk/hersey-yolunda` (tüm commit'ler push edildi). `TICK_SECRET` repo secret'ı ve `API_URL=https://hersey-yolunda-api.onrender.com` repo değişkeni ayarlandı.
- Render (API key ile, dashboard Blueprint yerine): Postgres `dpg-dal69k61egvs73emfb50-a` (free, **frankfurt**, PG17, 30 gün: 16 Ekim'de silinir) + web servisi `srv-dal6belbedkc73be8fs0` (free, frankfurt, Docker, health `/v1/health`, autoDeploy açık). Env: NODE_ENV/HOST/SCHEDULER_MODE=external + DATABASE_URL (internal) + 3 gizli anahtar. Yeni DB kullanıcısı `hersey_app` (API üzerinden, connection-info'dan alındı).
- İlk deploy `update_failed`: Dockerfile'da `ENV NODE_ENV=production` satırı `npm ci`'nin devDependencies'i atlamasına yol açtı → `tsx` yok → `ERR_MODULE_NOT_FOUND`. Düzeltme: `npm ci --include=dev` (+HEALTHCHECK `${PORT:-3000}`). İkinci deploy **live**.
- Canlı doğrulama: `GET /v1/health` → `{"status":"ok","mode":"production"}`; yanlış secret ile `/v1/tick` → 400, doğru secret → `{"ok":true}`; `gh workflow run tick.yml` → Actions'tan uçtan uca tick başarılı; `POST /v1/auth/device` → gerçek hesap/token üretildi (DB yazıyor).
- Simülatör: Release derlemesi canlı URL ile çalışıyor; eski yerel oturum "Yeniden giriş yapın" ile düştü (beklenen), onboarding ekranı açık.
- Not: `hersey_app` DB kullanıcısı varsayılan oldu; `hersey` kullanıcısı da duruyor. Secrets repoda yok; Render env'de + GitHub secret'ta.

#### Canlı test koşusu — 16 Eylül 2026

- Backend `npm run verify`: **33/33 geçti** (yerel, izole DB).
- `HY_TEST_API_URL=https://hersey-yolunda-api.onrender.com/v1 npm run test:http`: **1/1 geçti** — canlıda tam kontrat (auth/device, validasyon, profil, davet kabul, check-in idempotency, aile görünürlüğü, bildirim, iptal, silme). Test `mode` assert'i artık ortama duyarlı (https→production).
- iOS tam paket canlı API ile: `xcodebuild -project HerseyYolunda.xcodeproj -scheme HerseyYolunda -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/HerSeyYolundaLive HY_API_URL=https://hersey-yolunda-api.onrender.com/v1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO test` → **13/13 geçti** (11 unit + 2 UI; UI testi canlıda hesap açıp check-in/davet/program akışını yürüttü). Sonuç: `/tmp/HerSeyYolundaLive/Logs/Test/Test-HerseyYolunda-2026.09.16_13-03-24-+0300.xcresult`.
- Kayıt hız limiti (10 hesap/saat/IP) canlıda dolmadı.

#### Supabase geçişi ve Windows VPS denemesi — 16 Eylül 2026

- **Karar:** Render'ın ücretsiz Postgres'i 30 günde silindiği için DB **Supabase**'e taşındı (ücretsiz, süresiz, 500 MB). Windows VPS denemesi yarıda bırakıldı (IIS 80'i tutuyor, 443'te http.sys çakışması; sunucuda başka uygulama var). VPS'teki görevler devre dışı bırakılabilir.
- **Yapılan:** Supabase projesi `bsenfhvoytxwtkwcsbzl` (kullanıcı oluşturdu; bölge **ap-northeast-2/Seul** — Frankfurt→Seul ~250ms gecikme, MVP için kabul edilebilir). Render `DATABASE_URL` → Supavisor **session pooler** `aws-0-ap-northeast-2.pooler.supabase.com:5432` + `sslmode=require`. Session modu şart: transaction pooler advisory lock'u bozar.
- **Doğrulama:** Render loglarında `database_ready`; `/v1/health` ok; `POST /auth/device` canlıda hesap üretti (migration'lar boş Supabase DB'sinde çalıştı).
- Windows kurulum paketi `deploy/windows/` repoda duruyor (setup.ps1 + TLS-ALPN Caddyfile) — ileride Linux VPS'e geçilirse veya IIS'siz sunucuda referans. `docker-compose.yml`'e `SCHEDULER_MODE` eklendi. `main.ts` artık `startup_failed`'in asıl hatasını basıyor.
- Render Postgres `dpg-dal69k61egvs73emfb50-a` artık kullanılmıyor; 16 Ekim'de kendiliğinden silinir (yalnız test verisi içeriyor).
- Uyarı: Supabase free 7 gün inaktivitede uyur — 10 dk'lık GitHub Actions tick'i uyanık tutar.

#### Premium abonelik (StoreKit 2) — 16 Eylül 2026

- **Model:** Aylık otomatik yenilenen `premium_monthly` aboneliği — 199,99 TL/ay, **1 ay ücretsiz deneme** (intro offer, 175 ülke). Diğer ülkeler Apple eşdeğer kurunda (örn. ABD $3,99).
- **ASC:** Grup "Premium" (22389833), abonelik `6812755028` (productId `premium_monthly`, ONE_MONTH). Lokalizasyon tr ("Premium Aylık"), availability 175 ülke, fiyatlar equalization noktalarıyla, intro offer FREE_TRIAL/ONE_MONTH tüm bölgelerde. İnceleme görseli (paywall) `subscriptionAppStoreReviewScreenshots` ile yüklendi → `READY_TO_SUBMIT`.
- **iOS:** `StoreKitManager` (Product load, purchase, restore/AppStore.sync, Transaction.updates listener, currentEntitlements → isPremium). `PaywallView`: fiyat/deneme beyanı, iptal koşulları, Gizlilik + Kullanım Koşulları (Apple EULA) linkleri, restore — Apple 3.1.2 gereksinimleri. Ailem sekmesi premium: yakın daveti, durum görme, geçmiş, bildirimler; **check-in ve davet kabulü ücretsiz** (yaşlı yakın ödeme yapmaz). UI testleri `--uitest-premium` ile gate'i aşar, `--uitest-signed-in` sahte oturum sağlar.
- **Sınır:** Entitlement yalnızca istemcide (StoreKit doğrulamalı transaction). Backend doğrulaması + App Store Server Notifications (V2) hâlâ açık — revocation/refund sunucuda işlenmiyor; Faz 2 maddesi güncel değil, kısmen uygulandı.
- Build 3 (0.1.0/3) yüklendi, `usesNonExemptEncryption=false` beyan edildi, versiyona bağlandı. İlk submission (build 2, aboneliksiz) iptal edildi (item eklenemiyordu); yeni submission `7c92e133-…` = appStoreVersion + subscriptionVersion + subscriptionGroupVersion (ilk onay gereği grup da item) → `submitted` → **WAITING_FOR_REVIEW**.

#### İkon ortalama + aile akışı canlı testi — 16 Eylül 2026

- **İkon:** Kaynak 1024 görselde kalp/kişi sanatı yukarıda kalıyordu (y-bbox +81, merkez ~113px kayık) ve köşeler beyaz (yuvarlak ikon içi beyaz). ImageMagick ile artwork maskelenip krem tam-bleed zemine dikey/yatay ortalandı; 21 boyut yeniden üretildi. Build 4 (0.1.0/4) yüklendi ve submission build'i 4'e güncellendi.
- **Info.plist notu:** Çalışan `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` değerleri bir ara çalışma kopyasında `1.0`/`1`'e geri dönmüştü — build 4 öncesi tekrar düzeltildi; yükleme hatası ("version must be higher than 1") bu yüzdendi.
- **Aile akışı canlı API testi (Supabase):** share_mine → kod önizleme → accept(awaiting_approval) → creator approve → /me/relatives'te profil+today durumu göründü. request_theirs → accept → anında bağlantı. decline, geçersiz kod 404, kendi davetini kabul 403, ilişki DELETE ve liste boşalması hepsi doğrulandı.

#### App Store gönderimi — 16 Eylül 2026

- IconKitchen tam icon seti `AppIcon.appiconset`'e eklendi (21 boyut). Elle yazılan Info.plist'lerdeki sabit `1.0`/`1` sürümleri `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` değişkenlerine bağlandı.
- İmza takımı: **2HBFPNCMR8** (Xcode'da kayıtlı hesap; `5XR3QN2NJ6` App Store Connect **API Key ID**'sidir, imzalama takımı değil — D-014 düzeltmesi). ASC API: Issuer `b2ed3fe2-...`, Key `5XR3QN2NJ6`, `.p8` `~/private_keys/` altında.
- ASC app kaydı web'den oluşturuldu (Apple API'de CREATE kapalı): app id `6812729799`.
- Build 1 (0.1.0/1) yüklendi; iPad multitasking reddi → `UIRequiresFullScreen=true` eklendi. Build 2 (0.1.0/2) yüklendi — içinde **widget "BEN İYİYİM" buton görünürlük düzeltmesi** var (VStack'teki `.foregroundStyle(green)` buton yazısını yeşil yapıyordu; `.foregroundStyle(.white)` eklendi).
- Upload komutu: `xcodebuild -exportArchive -exportOptionsPlist (method app-store-connect, destination upload) -authenticationKeyPath/ID/IssuerID`. İnceleme için metadata/ekran görüntüsü/gizlilik formu web'de doldurulup build 2 seçilecek.

## 34. Değişiklik geçmişi

| Sürüm | Tarih | Değişiklik |
|---|---|---|
| 1.0 | 15 Eylül 2026 | Önceki kapsamlı ürün çalışması Herşey Yolunda adıyla iOS odaklı, takip edilebilir geliştirme planına dönüştürüldü. Native SwiftUI önerisi, sprintler, kabul kriterleri ve açık kararlar eklendi. |
| 1.1 | 15 Eylül 2026 | iOS uygulaması, widget, yerel/backend altyapısı ve otomatik testler uygulandı. Doğrulanmış maddeler işaretlendi; üretim bağımlılıkları, teknik sadeleştirmeler ve çalıştırma komutları kaydedildi. |
| 1.2 | 15 Eylül 2026 | Telefon/OTP yerine adla cihaz hesabı; güvenli kayıt tekrar anahtarı, ID tabanlı ilişkiler, süreli link/QR/kod daveti, veri koruyan migration ve güncellenen testler. Apple kurtarma açık iş olarak ayrıldı. |
| 1.3 | 15 Eylül 2026 | HTTPS davet bağlantısı (AASA + açılış sayfası + Caddy), v1.2 sürümünün gerçek iPhone'a kurulumu, LAN erişimi ve Docker/Caddy dağıtım paketi. Canlı yayın için domain/sunucu/mağaza kararları açık bırakıldı. |
| 1.4 | 15 Eylül 2026 | Firebase'e geçiş kararı (D-013) ve iskelet: firebase.json, deny-all Firestore kuralları, functions yapısı, kullanıcı Google adım listesi. App Store takımı 5XR3QN2NJ6 kaydedildi (D-014). |
| 1.5 | 16 Eylül 2026 | iCloud teşhisi ve projenin ~/Herşey Yolunda'ya taşınması; Render/Neon kararı (D-015), dış zamanlayıcı /tick (D-016), 33 backend testi, git deposu + Render Postgres blueprint + tick workflow; canlıya çıkış adımları netleştirildi. |
| 1.6 | 16 Eylül 2026 | Freemium katmanı: StoreKit 2 aylık abonelik (199,99 TL, 1 ay deneme), paywall, Ailem gate'i, ASC ürün/fiyat/deneme yapılandırması, build 3 ve üç-parçalı inceleme gönderimi; ayrıca ayar kaydet butonlarının kalıcı pasif bug'ı, 12s→30s API timeout ve Info.plist sürüm değişkenleri düzeltildi. |

---

**Bir sonraki adım:** Kullanıcı `gh auth login` ile GitHub kimliğini doğrular (repo görünürlüğü kararı ile); Devin repo'yu oluşturup push eder ve `TICK_SECRET` secret'ını ayarlar. Kullanıcı render.com'da GitHub ile üye olup Blueprint akışıyla 3 gizli anahtarı girer ve servisi başlatır. Devin canlı `/v1/health` + `/v1/tick` doğrulaması yapar, iOS Release derlemesini canlı URL ile telefona kurar ve aile testine geçilir. Sonrası: APNs .p8 (canlı push) ve App Store gönderimi (5XR3QN2NJ6). Teknik kayıtlar Bölüm 33'tedir.
