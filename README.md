# cluster-bootstrap

k3s single-cluster GitOps bootstrap repo. ArgoCD App of Apps pattern ile tüm platform addon'larını yönetir.

## Hızlı Başlangıç

### 1. Ön koşullar

```bash
# k3s kur (Traefik'i devre dışı bırak — ingress-nginx kullanıyoruz)
curl -sfL https://get.k3s.io | sh -s - --disable=traefik

# kubeconfig ayarla
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# ya da:
mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Gerekli araçlar
# helm   → https://helm.sh/docs/intro/install/
# kubectl → k3s ile birlikte gelir (k3s kubectl)
```

### 2. Repo'yu klonla ve yapılandır

```bash
git clone https://github.com/YOUR_ORG/cluster-bootstrap.git
cd cluster-bootstrap

# Repo URL'ini güncelle (tüm dosyalarda)
grep -rl "YOUR_ORG" . | xargs sed -i 's|YOUR_ORG|gerçek-org-adın|g'
```

### 3. Bootstrap çalıştır

```bash
# Public repo için:
bash bootstrap/init.sh

# Private repo için:
export GITHUB_REPO="https://github.com/your-org/cluster-bootstrap.git"
export GITHUB_TOKEN="ghp_xxxx"
bash bootstrap/init.sh
```

Bootstrap tamamlandıktan sonra ArgoCD geri kalanını otomatik olarak senkronize eder (~5-10 dk).

### 4. Hosts dosyasını güncelle

```bash
# LoadBalancer IP'sini bul
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "$INGRESS_IP argocd.dev.local grafana.dev.local" | sudo tee -a /etc/hosts
```

## Yapı

```
cluster-bootstrap/
├── argocd/
│   ├── install/values.yaml       # ArgoCD Helm values (k3s için optimize)
│   ├── app-of-apps.yaml          # Root Application — addons/'ı izler
│   └── projects/platform.yaml   # AppProject RBAC tanımı
│
├── addons/                       # Her addon: Application.yaml + values.yaml
│   ├── cert-manager/
│   ├── ingress-nginx/
│   ├── kube-prometheus-stack/
│   └── external-secrets/
│
├── policies/
│   ├── network-policies/         # Default-deny + izin politikaları
│   └── rbac/                     # ClusterRole tanımları
│
├── bootstrap/
│   ├── init.sh                   # Tek seferlik kurulum scripti
│   ├── namespaces.yaml           # Tüm namespace tanımları
│   └── secrets/README.md         # Secret yönetimi rehberi
│
├── .github/workflows/validate.yaml
├── Makefile
└── .gitignore
```

## Kullanışlı Komutlar

```bash
make status        # Tüm app'ların durumu
make password      # ArgoCD admin şifresi
make port-forward  # ArgoCD UI → localhost:8080
make grafana       # Grafana → localhost:3000
make sync          # Manuel senkronizasyon
make diff          # Bekleyen değişiklikleri göster
make lint          # YAML validasyonu
```

## Yeni Addon Eklemek

1. `addons/<addon-adı>/` klasörü oluştur
2. `Application.yaml` ekle (var olanları kopyala, düzenle)
3. `values.yaml` ekle
4. Git'e push et → ArgoCD otomatik algılar

## Erişim Adresleri

| Servis   | URL                        | Kullanıcı | Şifre              |
|----------|----------------------------|-----------|--------------------|
| ArgoCD   | https://argocd.dev.local   | admin     | `make password`    |
| Grafana  | https://grafana.dev.local  | admin     | dev-admin-123      |

> **Not:** Grafana şifresini `addons/kube-prometheus-stack/values.yaml` içinden değiştir.

## Secret Yönetimi

Şu an için secret yönetimi seçilmemiştir. Seçenekler için `bootstrap/secrets/README.md` dosyasına bak.

## k3s Özel Notlar

- Traefik `--disable=traefik` ile devre dışı bırakılmalı (ingress-nginx ile çakışır)
- Storage class olarak `local-path` kullanılıyor (k3s default)
- `kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy` monitoring'de kapalı (k3s farklı çalışır)
