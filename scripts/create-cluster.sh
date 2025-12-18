#!/usr/bin/env bash
set -e

CLUSTER_NAME=devops-challenge

echo "Creating k3d cluster: $CLUSTER_NAME"

k3d cluster create devops-challenge \
  --servers 1 \
  --agents 1 \
  --k3s-arg "--disable=traefik@server:*" \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

kubectl create namespace ingress-nginx

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

echo "Cluster created successfully"
kubectl get nodes
