Aşağıya notlarını **temiz, README formatında ve YAML’larla iç içe** olacak şekilde derledim:

---

# 🔐 Vault + Kubernetes External Secrets Entegrasyonu (README)

Bu doküman, Vault’ta secret yönetimi ve Kubernetes tarafında External Secrets Operator ile bu secret’ların nasıl kullanılacağını anlatır.

---

# 📁 1. Vault Secret Yapısı

Vault içinde secret’lar şu path pattern ile tutulur:

```
<environment>/<service>/<secret>
```

### Örnekler:

```
prod/payment-service/db
dev/order-service/kafka
```

---

# 💾 2. Vault’a Secret Yazma

Secret’lar önce Vault’a kaydedilir:

```bash
vault kv put secret/payment-service/db \
  username=payment_user \
  password=my-secret-password
```

Bu işlem Vault içinde şu yapıyı oluşturur:

```text
secret/payment-service/db
 ├── username
 └── password
```

---

# ☸️ 3. Kubernetes: ExternalSecret Tanımı

Kubernetes tarafında Vault secret’ları **doğrudan kullanılmaz**, sadece referans edilir.

Bunun için `ExternalSecret` kullanılır.

## 📄 ExternalSecret YAML

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-db-secret
  namespace: payment

spec:
  refreshInterval: 1h

  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore

  target:
    name: payment-db-secret

  data:
    - secretKey: username
      remoteRef:
        key: secret/payment-service/db
        property: username

    - secretKey: password
      remoteRef:
        key: secret/payment-service/db
        property: password
```

---

# 🔗 4. Kubernetes Secret Kullanımı (Env Inject)

ExternalSecret tarafından oluşturulan Kubernetes Secret artık uygulama içinde kullanılabilir.

## 📄 Deployment örneği

```yaml
env:
  - name: DB_USERNAME
    valueFrom:
      secretKeyRef:
        name: payment-db-secret
        key: username

  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: payment-db-secret
        key: password
```

---

# 🧠 5. Mantık Akışı

## 🔄 Data Flow

```
Vault
  ↓ (ExternalSecret fetch eder)
ExternalSecret (Kubernetes)
  ↓
Kubernetes Secret
  ↓
Application (env variables)
```

---

# 🎯 6. Özet

* Secret’lar **Vault’ta merkezi olarak tutulur**
* Kubernetes sadece **ExternalSecret ile referans verir**
* Uygulama Vault’u bilmez
* Sadece Kubernetes Secret üzerinden env alır
* Secret rotasyonu `refreshInterval` ile otomatik olur