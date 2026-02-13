#!/bin/bash
set -e

echo "==> Deletando clusters..."
kind delete cluster --name argocd-hub 2>/dev/null || true
kind delete cluster --name dev 2>/dev/null || true
kind delete cluster --name prod 2>/dev/null || true

echo "==> Removendo rede Docker..."
docker network rm kind-network 2>/dev/null || true

echo "==> Limpeza completa!"
