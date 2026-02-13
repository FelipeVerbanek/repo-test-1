#!/bin/bash
set -e

echo "==> Criando rede Docker compartilhada..."
docker network create kind-network --subnet=10.89.0.0/16 2>/dev/null || echo "Rede já existe"

echo "==> Criando cluster ArgoCD Hub..."
kind create cluster --name argocd-hub --config clusters/argocd-hub.yaml
docker network connect kind-network argocd-hub-control-plane 2>/dev/null || true

echo "==> Criando dev..."
kind create cluster --name dev --config clusters/dev.yaml
docker network connect kind-network dev-control-plane 2>/dev/null || true

echo "==> Criando prod..."
kind create cluster --name prod --config clusters/prod.yaml
docker network connect kind-network prod-control-plane 2>/dev/null || true

echo "==> Instalando ArgoCD no cluster hub..."
kubectl config use-context kind-argocd-hub
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd

echo "==> Aguardando ArgoCD ficar pronto..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "==> Obtendo senha inicial do ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

echo "==> Configurando acesso ao ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 5

echo "==> Fazendo login no ArgoCD CLI..."
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo "==> Atualizando kubeconfig dos clusters gerenciados..."
CLUSTER1_IP=$(docker inspect dev-control-plane -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect kind-network -f '{{.Id}}')'"}}{{.IPAddress}}{{end}}{{end}}')
CLUSTER2_IP=$(docker inspect prod-control-plane -f '{{range .NetworkSettings.Networks}}{{if eq .NetworkID "'$(docker network inspect kind-network -f '{{.Id}}')'"}}{{.IPAddress}}{{end}}{{end}}')

kubectl config set-cluster kind-dev --server=https://${CLUSTER1_IP}:6443
kubectl config set-cluster kind-prod --server=https://${CLUSTER2_IP}:6443

echo "==> Registrando clusters no ArgoCD..."
argocd cluster add kind-dev --name dev --yes
argocd cluster add kind-prod --name prod --yes

echo "==> Listando clusters registrados..."
argocd cluster list

echo ""
echo "==================================="
echo "Setup completo!"
echo "==================================="
echo "ArgoCD UI: https://localhost:8443"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "Clusters disponíveis:"
echo "  - kind-argocd-hub (hub com ArgoCD)"
echo "  - kind-dev (gerenciado)"
echo "  - kind-prod (gerenciado)"
echo ""
echo "IPs dos clusters:"
docker network inspect kind-network -f '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' | grep kind
