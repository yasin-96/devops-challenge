# Cloud & DevOps Challenge – README

Willkommen im Repository zur Cloud & DevOps Challenge. Dieses Projekt zeigt eine produktionsnahe, aber lokal reproduzierbare Umgebung mit Kubernetes (k3d), NGINX Ingress, cert-manager (TLS), HPA (Autoscaling) und einer GitHub Actions Pipeline (Task 7), die Tasks 1–6 automatisiert ausführt.

Hinweis: Alle Befehle sind für macOS/Linux ausgelegt. Unter Windows bitte PowerShell-Äquivalente verwenden.

---

## Inhalte

- Architekturüberblick
- Voraussetzungen
- Quick Start (lokal mit k3d)
- Deployments: App, Service, HPA, Ingress+TLS
- Test & Demo (TLS, HPA-Scaling, „hello world“ ohne Image-Bau)
- CI/CD mit GitHub Actions (Task 7)
- Troubleshooting
- Repository-Struktur
- Nächste Schritte (EKS)

---

## Architekturüberblick

- Lokaler Kubernetes-Cluster via k3d (k3s)
- Ingress Controller: NGINX (Traefik wird deaktiviert)
- TLS via cert-manager (self-signed) für Host hello.local
- Anwendung: Webserver (nginx oder Node.js), per Service exponiert
- Horizontal Pod Autoscaler (HPA) auf CPU-Basis
- Optional: NetworkPolicies, Monitoring (Prometheus/Grafana – konzeptionell)

Minimaler Datenfluss:
Client → Ingress (TLS) → Service → Pods
HPA skaliert die Pod-Anzahl anhand der CPU-Auslastung.

---

## Voraussetzungen

Bitte lokal installieren:
- Docker
- k3d
- kubectl
- Helm
- curl
---

## Quick Start (lokal mit k3d)

1) Cluster erstellen (Ports 80/443 gemappt, Traefik deaktiviert):
```bash
k3d cluster create devops-challenge \
  --servers 1 \
  --agents 1 \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer \
  --k3s-arg "--disable=traefik@server:*"
```

2) Ingress-NGINX installieren:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s
```

3) cert-manager (inkl. CRDs) installieren:
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
```

4) Manifeste anwenden (Deployment, Service, HPA, Ingress+TLS):
```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/ingress-tls.yaml
kubectl rollout status deploy/hello-nginx -n default --timeout=300s
```

5) Hostname lokal auflösen:
```bash
echo "127.0.0.1 hello.local" | sudo tee -a /etc/hosts
```

6) Test (self-signed → -k):
```bash
curl -I -k https://hello.local
```

---

## Deployments

- Deployment: hello-nginx (z. B. NGINX)
- Service: hello-nginx (Port 80 → targetPort 80 oder 8080)
- HPA: hello-nginx-hpa (CPU-Utilization, Ziel 50%, min 2, max 5)
- Ingress: hello-ingress mit TLS (Secret hello-tls), Host hello.local
- cert-manager:
  - ClusterIssuer (self-signed)
  - Certificate (hello.local) → Secret hello-tls

Achte darauf, dass:
- Labels im Deployment (app: hello-nginx) zum Service-Selector passen.
- Ressourcen-Requests im Deployment gesetzt sind (z. B. cpu: 50m), damit HPA korrekt arbeitet.

---

## Demo & Tests

### „hello world“ ohne Image-Bau (per kubectl exec)
Schnell und flüchtig (bei Pod-Restarts weg). Bei >1 Replica bitte alle Pods aktualisieren.

- Einen Pod überschreiben:
```bash
POD=$(kubectl get pods -l app=hello-nginx -o jsonpath='{.items[0].metadata.name}')
echo 'hello world' | kubectl exec -i "$POD" -- tee /usr/share/nginx/html/index.html >/dev/null
```

- Alle Pods überschreiben:
```bash
for p in $(kubectl get pods -l app=hello-nginx -o name | sed 's|pod/||'); do
  echo 'hello world' | kubectl exec -i "$p" -- tee /usr/share/nginx/html/index.html >/dev/null
done
```

- Test:
```bash
curl -k https://hello.local | head -n1
```

Dauerhaft (empfohlen): index.html via ConfigMap mounten.

### HPA-Scaling demonstrieren
- Last erzeugen (3–5 Minuten, hohe Parallelität):
```bash
kubectl run loadgen --image=fortio/fortio --restart=Never -- \
  load -c 32 -qps 0 -t 5m http://hello-nginx.default.svc.cluster.local/
```

- Beobachten:
```bash
kubectl describe hpa hello-nginx-hpa
kubectl get hpa -w
kubectl get pods -l app=hello-nginx -w
kubectl top pods
```

- Last stoppen (Downscale bis minReplicas=2, mit Verzögerung):
```bash
kubectl delete pod loadgen --ignore-not-found
```

---

## CI/CD – GitHub Actions (Task 7)

Der Workflow „Task 7 Pipeline (Tasks 1–6)“:
- erstellt k3d-Cluster (Ports 80/443, Traefik disabled),
- installiert kubectl & Helm,
- installiert cert-manager + ingress-nginx,
- wendet Manifeste an,
- erzeugt Last und prüft HPA/Ingress (TLS).

Datei: .github/workflows/task7-pipeline.yaml

Wichtige Variablen:
- CLUSTER_NAME=devops-challenge
- INGRESS_HOST=hello.local
- K8S_NAMESPACE=default

Ablauf starten:
- Automatisch bei Push auf main
- oder manuell via Actions → „Run workflow“

Hinweis: Falls du gar kein eigenes Image baust, stelle im Deployment ein Standard-Image ein (z. B. nginx:stable) und lass die Build/Push-Schritte im Workflow unverändert (sie stören nicht) oder entferne sie.

---

## Troubleshooting

- 404 page not found
  - Traefik fängt Traffic ab. Stelle sicher, dass Traefik deaktiviert ist (Cluster mit --disable=traefik erstellt).
  - IngressClass prüfen:
    ```bash
    kubectl get ingressclass
    ```
    Ingress muss `spec.ingressClassName: nginx` haben (ggf. zusätzlich Annotation `kubernetes.io/ingress.class: nginx`).

- Ingress nicht erreichbar / kein TLS
  - Ingress-NGINX installiert und Service exponiert?
    ```bash
    kubectl -n ingress-nginx get pods,svc
    ```
  - cert-manager läuft, CRDs vorhanden?
    ```bash
    kubectl get crd | grep cert-manager
    kubectl -n cert-manager get pods
    ```
  - Certificate/Secret vorhanden?
    ```bash
    kubectl -n default get certificate
    kubectl -n default get secret hello-tls
    kubectl -n default describe certificate hello-cert
    ```

- Service ohne Endpoints
  - Selector ↔ Pod-Labels prüfen:
    ```bash
    kubectl get endpoints hello-nginx
    ```
    Erwartet Pod-IP:80/8080. Sonst Labels angleichen.

- HPA skaliert nicht
  - Requests gesetzt? (Deployment resources.requests.cpu)
  - konstante Last 2–5 Minuten erzeugen
  - metrics-server verfügbar? (k3s: meist integriert)
  - Zielwert anpassen (z. B. averageUtilization 40–50%)

- Hosts-Auflösung
  - hello.local → 127.0.0.1:
    ```bash
    echo "127.0.0.1 hello.local" | sudo tee -a /etc/hosts
    ```

---

## Repository-Struktur (Empfehlung)

```

├── k8s/
│   ├── deployment.yaml       # Deployment (app: hello-nginx)
│   ├── service.yaml          # ClusterIP Service hello-nginx
│   ├── hpa.yaml              # HPA (hello-nginx-hpa)
│   └── ingress-tls.yaml      # ClusterIssuer, Certificate, Ingress (hello.local)
├── scripts/
│   └── create-cluster.sh     # optional: k3d-Cluster-Erstellung
├── .github/
│   └── workflows/
│       └── task7-pipeline.yaml
└── README.md
```

---

## Kontakt

- Maintainer: Yasin Eraslan
