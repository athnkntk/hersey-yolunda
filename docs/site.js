/* Herşey Yolunda — bilingual support/privacy pages.
   English is the static HTML fallback; this script holds the Turkish strings
   and the initial English text is captured from the page itself. */
(function () {
  "use strict";

  var KEY = "hy-lang";
  var page = document.body.getAttribute("data-page") || "";

  /* Turkish translations keyed by data-i18n attribute. */
  var TR = {
    support: {
      title: "Herşey Yolunda — Destek",
      tagline: "Günlük “iyiyim” bildirimi — tek dokunuşla ailenize haber verin.",
      howTitle: "Nasıl çalışır?",
      how1: "Adınızı yazın — hesabınız bu cihaz için oluşur (telefon numarası, e-posta veya SMS gerekmez).",
      how2: "Yakınınızı davet bağlantısı, QR veya kod ile ekleyin.",
      how3: "Her gün tek dokunuşla “İyiyim” haberinizi gönderin.",
      how4: "İzin verdiğiniz yakınlarınız haberinizi uygulamada görür.",
      faqAccountTitle: "Hesap ve giriş",
      faqAccountBody: "Hesabınızı oluşturmak için yalnızca adınızı yazarsınız; telefon, e-posta veya SMS ile giriş yoktur. Adınız bir kimlik bilgisi değildir. Bu sürümde hesap kurtarma yoktur: cihazınızı veya oturumunuzu kaybederseniz yeni bir hesap oluşturmanız ve aile onayını yeniden almanız gerekir. Apple üzerinden satın alma geri yükleme, abonelik hakkını geri getirir; uygulama hesabınızı veya geçmişinizi geri getirmez.",
      faqRoutineTitle: "Günlük rutin",
      faqRoutineBody: "Haber vermek bilinçli bir “İyiyim” dokunuşu gerektirir; onay yalnızca sunucu haberi kaydettikten sonra görünür ve internet bağlantısı gerekir. Hatırlatmalar kişiseldir ve bildirim izninize bağlıdır. Programlar, hesap oluşturulurken kaydedilen hesap saat dilimini kullanır; seyahat ettiğinizde saat dilimi kendiliğinden değişmez. Program düzenlemeleri ertesi gün uygulanır; bugünü duraklatırsanız rutin ertesi gün devam eder.",
      faqConnectionsTitle: "Bağlantılar ve davetler",
      faqConnectionsBody: "Yakınlarınızı bağlantı, QR veya 12 karakterli kodla davet edersiniz. Davetler tek kullanımlıktır ve 48 saat geçerlidir. Paylaşım başlamadan önce haber sahibinin onayı gerekir. Bir kişinin haberini en fazla 10 kişi izleyebilir. Konum veya sağlık takibi yoktur ve uygulama sizin yerinize otomatik haber vermez.",
      faqPremiumTitle: "Premium",
      faqPremiumBody: "Kişisel haber verme, hatırlatmalar ve araç takımı ücretsizdir. Yakın davet etme, aile durumu ve geçmişi görüntüleme Premium gerektirir. Fiyat ve uygun deneme süresi App Store tarafından gösterilir. Aboneliğinizi App Store üzerinden yönetebilir veya iptal edebilirsiniz; hesabınızı silmek aboneliğinizi iptal etmez.",
      faqPremiumLink: "Aboneliği App Store’da yönet",
      faqNoUpdateTitle: "Haber gelmediyse",
      faqNoUpdateBody: "Yakınınızın internet bağlantısını ve bildirim iznini kontrol edin, listeyi yenilemek için aşağı çekin veya yeniden deneyin; gerekiyorsa telefonla arayın. Bildirimler gecikebilir veya görülmeyebilir; uygulama teslimat garantisi veya güvenlik doğrulaması vermez. Acil bir durumda bulunduğunuz yerdeki acil servisleri arayın.",
      contactTitle: "Destek",
      contactBody: "Sorular ve hata bildirimleri:",
      privacyLink: "Gizlilik bildirimi"
    },
    privacy: {
      title: "Herşey Yolunda — Gizlilik Bildirimi",
      pageTitle: "Gizlilik Bildirimi",
      updated: "Son güncelleme: 15 Ekim 2026",
      intro: "Herşey Yolunda, günlük “iyi olduğumu bildir” alışkanlığı için tasarlanmış bir aile uygulamasıdır. Bu bildirim, hangi verilerin neden işlendiğini açıklar.",
      dataTitle: "İşlenen veriler",
      data1a: "Hesap:",
      data1b: " görünen ad ve hesap kimliği; hesap saat dilimi ve tercihleriniz.",
      data2a: "Haber kayıtları:",
      data2b: " haber verdiğiniz gün ve saat, kaynağı ve geçmişiniz.",
      data3a: "Bağlantılar:",
      data3b: " onayladığınız aile bağlantıları ve oluşturduğunuz davetler.",
      data4a: "Bildirim bilgileri:",
      data4b: " cihaz bildirim anahtarı, bildirim izni ve dil tercihi.",
      data5a: "Güvenlik:",
      data5b: " oturum ve onay kayıtları; kötüye kullanım sınırları için ağ tanımlayıcıları açık olarak saklanmaz, özeti tutulur.",
      data6: "Barındırma sağlayıcıları, hizmeti çalıştırmak için teknik istek bilgilerini işleyebilir.",
      purposeTitle: "Kullanım amacı",
      purposeBody: "Veriler günlük haber verme, izin verdiğiniz kişilerle paylaşım, kişisel hatırlatmalar ve kullanılabilir olduğunda bildirim iletimi, hesap ve oturum güvenliği ile kötüye kullanımı önleme için kullanılır. Reklam veya izleme SDK’sı yoktur; konum, sağlık sensörü, kamera, mikrofon veya rehber erişimi yoktur. Haber yalnızca sizin bilinçli eyleminizle oluşur; uygulamanın olağan ağ istekleri bunun dışında da gerçekleşebilir.",
      sharingTitle: "Paylaşım ve sağlayıcılar",
      sharingBody: "İzin verdiğiniz kişiler, paylaşmayı seçtiğiniz günlük haberleri ve geçmişi görür. Davet alıcısı, davet edenin seçtiği görünen adı görür. Paylaşımı istediğiniz zaman kaldırabilirsiniz. Hizmet sağlayıcılar: Render (API barındırma), Supabase (Postgres veritabanı) ve Apple (App Store ödemeleri ile yapılandırıldığında bildirim iletimi).",
      securityTitle: "Güvenlik",
      securityBody: "Bağlantılar HTTPS üzerinden kurulur ve oturum kimlik bilgileri cihazınızın Keychain’inde tutulur.",
      retentionTitle: "Saklama ve silme",
      retentionBody: "Haber geçmişi 30 günlük temizliğe tabidir; süresi dolan davet kayıtları sürenin dolmasından 30 gün sonra temizlenir; güvenlik kayıtları 180 gün tutulur. Sağlayıcıların işletim yedekleri ayrı bir saklama süresine sahip olabilir. Ayarlar → “Verilerim” bölümünden verilerinizi dışa aktarabilir veya hesabınızı silebilirsiniz. Hesap silme, etkin veritabanındaki hesabı, bağlantıları ve kayıtları kaldırır; App Store aboneliğinizi iptal etmez.",
      limitsTitle: "Sınırlar",
      limitsBody: "Bu sürümde hesap kurtarma yoktur. Uygulama bir acil yardım veya tıbbi müdahale hizmeti değildir ve bildirimlerin ulaşacağı garanti edilmez.",
      contactTitle: "İletişim ve sağlayıcı",
      contactBody: "Sağlayıcı: Atahan Kantik — bağımsız geliştirici. Veri talepleri ve sorular için:",
      supportLink: "Destek"
    }
  };

  var dict = { en: {} };
  var tr = TR[page] || {};

  function captureEnglish() {
    var nodes = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute("data-i18n");
      dict.en[key] = nodes[i].textContent;
    }
    dict.en.title = document.title;
    dict.tr = tr;
    dict.tr.title = tr.title || document.title;
  }

  function detect() {
    var q;
    try { q = new URLSearchParams(location.search).get("lang"); } catch (e) { q = null; }
    if (q === "tr" || q === "en") return q;
    try {
      var saved = localStorage.getItem(KEY);
      if (saved === "tr" || saved === "en") return saved;
    } catch (e) {}
    var langs = navigator.languages || [navigator.language || ""];
    for (var i = 0; i < langs.length; i++) {
      var base = String(langs[i]).toLowerCase().split("-")[0];
      if (base === "tr" || base === "en") return base;
    }
    return "en";
  }

  function save(lang) {
    try { localStorage.setItem(KEY, lang); } catch (e) {}
  }

  function apply(lang) {
    var d = dict[lang] || dict.en;
    document.documentElement.lang = lang;
    document.title = d.title;
    var nodes = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      var key = nodes[i].getAttribute("data-i18n");
      if (d[key] !== undefined) nodes[i].textContent = d[key];
    }
    var links = document.querySelectorAll("a[data-lang-link]");
    for (var j = 0; j < links.length; j++) {
      var href = links[j].getAttribute("data-lang-link");
      links[j].setAttribute("href", href + "?lang=" + lang);
    }
    var buttons = document.querySelectorAll(".lang-btn");
    for (var k = 0; k < buttons.length; k++) {
      buttons[k].setAttribute("aria-pressed", buttons[k].getAttribute("lang") === lang ? "true" : "false");
    }
  }

  function init() {
    captureEnglish();
    var buttons = document.querySelectorAll(".lang-btn");
    for (var i = 0; i < buttons.length; i++) {
      (function (btn) {
        btn.addEventListener("click", function () {
          var lang = btn.getAttribute("lang") || "en";
          save(lang);
          apply(lang);
        });
      })(buttons[i]);
    }
    apply(detect());
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
