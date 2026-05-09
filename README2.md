# cluster-bootstrap — Ne var, ne işe yarıyor?

Bu repo bir Kubernetes cluster'ını sıfırdan ayağa kaldırmak ve yönetmek için gereken her şeyi içeriyor. Aşağıda her klasörün ve dosyanın ne olduğunu, neden var olduğunu ve birbiriyle nasıl konuştuğunu anlatıyorum.

---

## Büyük resim: Bu repo ne yapar?

Normalde bir sunucuya yazılım kurmak istediğinde terminale gidip komut yazarsın. Bir şeyi değiştirmek istediğinde tekrar komut yazarsın. Bu yaklaşımın sorunu şu: bir süre sonra sunucunun tam olarak hangi komutlarla o hale geldiğini kimse bilmez, bir şeyi yanlışlıkla değiştirirsen geri almak zordur, aynı kurulumu başka bir yerde tekrarlamak neredeyse imkânsızdır.

Bu repo bunun tam tersini yapar. **Cluster'da ne olması gerektiğini kod olarak burada tanımlarsın, bir araç (ArgoCD) sürekli bu repo'yu izler ve cluster'ı buradaki tanımlara göre tutar.** Bir şeyi değiştirmek istiyorsan terminale değil, bu repo'ya gelirsin. Buna **GitOps** denir.

---

## Klasör yapısı

```
cluster-bootstrap/
├── argocd/
├── addons/
├── policies/
├── bootstrap/
├── .github/
├── Makefile
└── .gitignore
```

---

### `argocd/` — Her şeyi izleyen araç

ArgoCD bu sistemin kalbi. "Bu repo'da şu tanımlar var, cluster'da da aynen öyle olsun" mantığıyla çalışan bir araç. Repo'da bir değişiklik görürse cluster'a otomatik olarak uygular.

**`argocd/install/values.yaml`**
ArgoCD'nin kendisinin nasıl kurulacağını tanımlar. Kaç kopya çalışacak, ne kadar bellek kullanacak, hangi adresten erişilebilir olacak gibi ayarlar burada. Dev ortamı için küçük tutulmuş — production'da daha büyük değerler girilir.

**`argocd/app-of-apps.yaml`**
Bu dosya ArgoCD'ye şunu söyler: "Bu repo'nun `addons/` klasörüne bak, orada ne bulursan hepsini cluster'a uygula." Yani bu tek dosya, aşağıdaki tüm addon içeriklerini tetikler. Yeni bir araç eklemek istediğinde sadece `addons/` klasörüne ekliyorsun, ArgoCD onu otomatik olarak fark edip kuruyor.

**`argocd/projects/platform.yaml`**
ArgoCD'de "proje" bir güvenlik sınırı gibi çalışır. Bu dosya "platform projesi" adında bir tanım oluşturur ve der ki: "Bu projedeki uygulamalar sadece bu repo'dan kaynak alabilir, sadece bu Helm repo'larını kullanabilir." Kimin neyi nereye deploy edebileceğini kısıtlamak için var.

---

### `addons/` — Cluster'ın üzerinde çalışan platform araçları

Her uygulama gibi Kubernetes üzerinde de bazı "altyapı araçları" çalışır. Bunlar business logic yazan servisler değil — TLS sertifikası üreten, trafiği yönlendiren, metrikleri toplayan araçlar. Her birinin kendi klasörü var ve her klasörde iki dosya bulunuyor:

- **`Application.yaml`**: ArgoCD'ye "bu aracı şu Helm chart'tan al, şu versiyonu kullan, şu namespace'e kur" diyen manifest.
- **`values.yaml`**: O aracın konfigürasyonu. Hangi özellikleri açık, kaç replica çalışacak, hangi domaine cevap verecek gibi ayarlar.

**`addons/cert-manager/`**
TLS sertifikası yöneticisi. Cluster'daki servisler HTTPS üzerinden erişilebilir olmak istediğinde sertifika ihtiyaç duyar. cert-manager bu sertifikaları otomatik olarak üretir ve yeniler. Sen bir servise "HTTPS istiyorum" dediğinde, cert-manager arka planda gerekli sertifikayı oluşturuyor. Dev ortamında self-signed sertifika üretiyor — tarayıcı "güvensiz" uyarısı verir ama teknik olarak şifreli bağlantı sağlanıyor. Production'da Let's Encrypt gibi gerçek bir sertifika otoritesiyle çalışır.

**`addons/ingress-nginx/`**
Cluster'a gelen HTTP/HTTPS trafiğini doğru servise yönlendiren kapı görevlisi. Örneğin `grafana.dev.local` adresine gelen istek Grafana pod'una, `api.dev.local` adresine gelen istek API pod'una gitmeli — bunu ingress-nginx halleder. k3s varsayılan olarak Traefik adlı benzer bir araç getiriyor ama bu kurulumda kapatılıp ingress-nginx tercih ediliyor çünkü konfigürasyonu daha standart ve yaygın.

**`addons/kube-prometheus-stack/`**
Monitoring yığını. Üç parçadan oluşuyor: Prometheus (cluster'daki her şeyden metrik toplar ve saklar), Grafana (bu metrikleri görsel dashboard'larla gösterir), Alertmanager (tanımlanan eşikler aşıldığında uyarı gönderir). Dev ortamı için küçük tutulmuş: 7 günlük veri saklama, 10GB disk, tek replica. k3s bazı Kubernetes bileşenlerini farklı şekilde expose ettiği için `kubeEtcd`, `kubeScheduler` gibi bazı izleme özellikleri kapalı — bunlar k3s'de standart yoldan erişilemiyor.

**`addons/external-secrets/`**
Secret yönetim köprüsü. Uygulamalar veritabanı şifresi, API anahtarı gibi hassas bilgilere ihtiyaç duyar. Bu bilgileri doğrudan Kubernetes'e yazmak yerine, bir secret yönetim sisteminde (Vault, AWS SSM, vb.) tutup oradan Kubernetes'e çekmek daha güvenli. External Secrets Operator bu köprüyü kurar: "Vault'taki şu secret'ı al, Kubernetes secret'ı olarak bu namespace'e yaz" diyebiliyorsun. Dev ortamı için henüz bir backend bağlanmamış — ilerleyen aşamada yapılandırılacak.

---

### `policies/` — Güvenlik ve erişim kuralları

**`policies/network-policies/default-policies.yaml`**
Varsayılan olarak Kubernetes'te her pod her pod'la konuşabilir. Bu güvenlik açısından kötü bir varsayılan. Bu dosya "aksi belirtilmedikçe dışarıdan gelen trafik reddedilsin" kuralını koyuyor ve ardından sadece gerekli istisnalar açılıyor: ingress-nginx tüm servislere ulaşabilir, Prometheus tüm pod'lardan metrik toplayabilir gibi.

**`policies/rbac/roles.yaml`**
Kim ne yapabilir? Bu dosya iki rol tanımlıyor: `platform-admin` (her şeye tam erişim — platform ekibi için) ve `developer` (cluster genelinde sadece okuma, kendi namespace'inde yazma). Ayrıca ArgoCD'nin cluster'ı yönetebilmesi için gerekli ServiceAccount ve izinler burada tanımlı.

---

### `bootstrap/` — Sıfırdan kurulum için gereken her şey

**`bootstrap/init.sh`**
Boş bir k3s cluster'ından başlayıp her şeyi ayağa kaldıran script. Sırasıyla şunları yapıyor:

1. `kubectl` ve `helm` gibi araçların kurulu olduğunu kontrol eder
2. Namespace'leri oluşturur
3. ArgoCD'yi Helm ile kurar ve hazır olmasını bekler
4. Eğer repo private ise GitHub token'ını ArgoCD'ye tanıtır
5. RBAC ve network policy'leri uygular
6. `app-of-apps.yaml`'ı cluster'a apply eder — bundan sonra ArgoCD devralır ve geri kalan her şeyi kendi kurar

Bu script bir kez çalıştırılır. Sonrasında her değişiklik bu repo üzerinden GitOps ile yapılır.

**`bootstrap/namespaces.yaml`**
Tüm namespace tanımları tek bir dosyada. Namespace'ler addon'lardan önce var olmak zorunda — o yüzden `init.sh` içinde ilk adım olarak bunlar oluşturuluyor. Her namespace'e `managed-by: bootstrap` ve `environment: dev` etiketleri ekleniyor; bu etiketler ilerleyen aşamalarda filtreleme ve politika uygulamak için işe yarıyor.

**`bootstrap/secrets/README.md`**
Şu an için secret yönetimi seçilmemiş. Bu dosya ileriye dönük bir rehber: SOPS + age ile nasıl şifreli secret saklanır, ya da sadece dev için kubectl ile nasıl elle secret oluşturulur gibi seçenekleri açıklıyor.

---

### `.github/workflows/validate.yaml` — Otomatik kontrol

Her Pull Request açıldığında veya main branch'e push yapıldığında GitHub Actions devreye girer ve üç şeyi kontrol eder: YAML dosyalarının sözdizimi geçerli mi, Kubernetes manifest'leri Kubernetes kurallarına uygun mu, Helm values dosyaları chart'larla uyumlu mu. Bu sayede hatalı bir konfigürasyon cluster'a ulaşmadan yakalanır.

---

### `Makefile` — Sık kullanılan komutların kısayolları

`make status`, `make password`, `make port-forward` gibi komutlarla uzun kubectl komutları kısaltılıyor. Özellikle ArgoCD şifresini almak veya Grafana'ya port-forward açmak gibi sık tekrarlanan işlemler için pratik.

---

### `.gitignore` — Git'e gönderilmeyecek dosyalar

Secret dosyaları, Helm cache klasörleri ve işletim sistemi dosyaları (`.DS_Store` gibi) git'e gönderilmiyor. En kritik kural: `bootstrap/secrets/` altındaki düz metin dosyaları git'e girmez, sadece şifrelenmiş halleri (`.enc.yaml`) girer.

---

## Bileşenler arası ilişki

```
GitHub'da bu repo
       │
       │  ArgoCD sürekli izler, değişiklik görürse uygular
       ▼
   ArgoCD
       │
       ├──► cert-manager       sertifika üretir ve yeniler
       │         │
       │         └──────────►  ingress-nginx'e sertifika sağlar
       │
       ├──► ingress-nginx       dışarıdan gelen trafiği doğru servise yönlendirir
       │
       ├──► kube-prometheus     metrikleri toplar, Grafana ile görselleştirir
       │
       └──► external-secrets   dış secret store'dan Kubernetes'e secret köprüsü kurar
```

---

## Neyin bu repoda olmadığı

Bu repo sadece cluster'ın kendisini ve platform araçlarını yönetiyor. Şunlar burada **yok**:

- Business servislerin deployment'ları → application-repo'da olacak
- Namespace başına uygulama konfigürasyonları → platform-repo'da olacak
- Uygulama kodları → ilgili servis repo'larında

Bu ayrım kasıtlı: cluster altyapısına dokunan şeyler burada, uygulama dünyasına ait şeyler kendi repo'larında. Bir geliştirici kendi servisini deploy etmek için bu repoya hiç girmek zorunda kalmamalı.