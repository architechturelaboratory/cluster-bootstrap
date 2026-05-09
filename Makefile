.PHONY: bootstrap sync status password port-forward clean help

ARGOCD_NS := argocd

## bootstrap: Cluster'ı sıfırdan kur (init.sh'i çalıştırır)
bootstrap:
	@bash bootstrap/init.sh

## sync: Tüm ArgoCD app'larını manuel senkronize et
sync:
	@argocd app sync app-of-apps --cascade

## status: Tüm app'ların durumunu göster
status:
	@kubectl get applications -n $(ARGOCD_NS)

## password: ArgoCD admin şifresini göster
password:
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

## port-forward: ArgoCD UI'yı localhost:8080'e aç
port-forward:
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:443

## grafana: Grafana UI'yı localhost:3000'e aç
grafana:
	@kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

## diff: Git'teki değişikliklerin cluster'a etkisini göster
diff:
	@argocd app diff app-of-apps --cascade

## lint: YAML ve manifest validasyonu
lint:
	@yamllint .
	@find . -name "*.yaml" -not -path "./.github/*" -not -path "./bootstrap/secrets/*" \
		| xargs kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.29.0

## clean: Tüm ArgoCD kaynaklarını sil (dikkatli!)
clean:
	@echo "UYARI: Bu işlem tüm ArgoCD app'larını silecek!"
	@read -p "Devam etmek istediğine emin misin? [y/N] " confirm && [ "$$confirm" = "y" ]
	@kubectl delete application app-of-apps -n $(ARGOCD_NS) || true
	@helm uninstall argocd -n $(ARGOCD_NS) || true

help:
	@grep -E '^##' Makefile | sed 's/## //'
