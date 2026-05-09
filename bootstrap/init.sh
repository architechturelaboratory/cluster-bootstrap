#!/usr/bin/env bash
# ============================================================
#  cluster-bootstrap / bootstrap / init.sh
#  k3s single-cluster dev bootstrap script
#
#  Kullanım:
#    export GITHUB_REPO="https://github.com/YOUR_ORG/cluster-bootstrap.git"
#    export GITHUB_TOKEN="ghp_xxxx"   # private repo ise
#    bash bootstrap/init.sh
# ============================================================
set -euo pipefail

ARGOCD_VERSION="2.10.7"
ARGOCD_NAMESPACE="argocd"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/architechturelaboratory/cluster-bootstrap.git}"

# Renk kodları
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fatal()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Ön kontroller ────────────────────────────────────────────
check_prerequisites() {
  info "Ön koşullar kontrol ediliyor..."
  for cmd in kubectl helm; do
    command -v "$cmd" &>/dev/null || fatal "$cmd bulunamadı. Lütfen kur."
  done

  kubectl cluster-info &>/dev/null || fatal "Cluster'a erişilemiyor. kubeconfig'i kontrol et."
  info "Cluster erişimi OK."
}

# ── Namespace'leri oluştur ───────────────────────────────────
apply_namespaces() {
  info "Namespace'ler oluşturuluyor..."
  kubectl apply -f bootstrap/namespaces.yaml
}

# ── ArgoCD kur ──────────────────────────────────────────────
install_argocd() {
  info "ArgoCD ${ARGOCD_VERSION} kuruluyor..."
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update

  helm upgrade --install argocd argo/argo-cd \
    --namespace "$ARGOCD_NAMESPACE" \
    --version "$ARGOCD_VERSION" \
    --values argocd/install/values.yaml \
    --wait \
    --timeout 5m

  info "ArgoCD kuruldu. Hazır olana kadar bekleniyor..."
  kubectl rollout status deployment/argocd-server \
    -n "$ARGOCD_NAMESPACE" --timeout=180s
}

# ── Repo credentials (private repo ise) ─────────────────────
apply_repo_credentials() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    info "GitHub repo credentials uygulanıyor..."
    kubectl create secret generic argocd-repo-creds \
      --namespace "$ARGOCD_NAMESPACE" \
      --from-literal=type=git \
      --from-literal=url="$GITHUB_REPO" \
      --from-literal=password="$GITHUB_TOKEN" \
      --from-literal=username=git \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    warn "GITHUB_TOKEN tanımlı değil — public repo varsayılıyor."
  fi
}

# ── RBAC ve politikalar ──────────────────────────────────────
apply_policies() {
  info "RBAC ve politikalar uygulanıyor..."
  kubectl apply -f policies/rbac/roles.yaml
  kubectl apply -f policies/network-policies/default-policies.yaml
}

# ── AppProject ve App of Apps ────────────────────────────────
apply_argocd_resources() {
  info "ArgoCD AppProject uygulanıyor..."
  kubectl apply -f argocd/projects/platform.yaml

  info "App of Apps uygulanıyor..."
  # repo URL'ini güncelle
  sed "s|https://github.com/architechturelaboratory/cluster-bootstrap.git|${GITHUB_REPO}|g" \
    argocd/app-of-apps.yaml | kubectl apply -f -
}

# ── ArgoCD admin şifresini göster ───────────────────────────
show_argocd_password() {
  local pass
  pass=$(kubectl -n "$ARGOCD_NAMESPACE" \
    get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
  echo ""
  info "============================================================"
  info "Bootstrap tamamlandı!"
  info "ArgoCD admin şifresi: ${pass}"
  info "ArgoCD UI: https://argocd.dev.local"
  warn "Hosts dosyasına ekle: $(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}') argocd.dev.local grafana.dev.local"
  info "ArgoCD şimdi geri kalanını otomatik senkronize edecek."
  info "============================================================"
}

# ── Ana akış ─────────────────────────────────────────────────
main() {
  check_prerequisites
  apply_namespaces
  install_argocd
  apply_repo_credentials
  apply_policies
  apply_argocd_resources
  show_argocd_password
}

main "$@"
