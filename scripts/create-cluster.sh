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

echo "Cluster created successfully"
kubectl get nodes
