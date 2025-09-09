# PowerShell version for Windows DTL machine
# Deploy Backend to Private AKS with Domain and SSL

$ErrorActionPreference = "Stop"

# Configuration
$RESOURCE_GROUP = "bieno-ai05-d-000008-rg"
$ACR_NAME = "bienoai05000008crn"
$AKS_CLUSTER = "bieno-ai05-d-000008-aks-02"
$SUBSCRIPTION_ID = "753dbb7c-775c-45b0-b7ee-c3e82245fbf2"
$BACKEND_DOMAIN = "secure-backend-api.northeurope.cloudapp.azure.com"

Write-Host "🚀 Deploying Backend to Private AKS: $AKS_CLUSTER" -ForegroundColor Green

# Set subscription and connect
Write-Host "📋 Setting subscription..." -ForegroundColor Yellow
az account set --subscription $SUBSCRIPTION_ID

Write-Host "🔑 Getting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --overwrite-existing

Write-Host "🔐 Converting kubeconfig..." -ForegroundColor Yellow
kubelogin convert-kubeconfig -l azurecli

# Test connection
Write-Host "🧪 Testing cluster connection..." -ForegroundColor Yellow
kubectl get nodes

# Login to ACR and build image
Write-Host "🐳 Building and pushing backend image..." -ForegroundColor Yellow
az acr login --name $ACR_NAME
Set-Location secure-backend
docker build -t "$ACR_NAME.azurecr.io/secure-backend:latest" .
docker push "$ACR_NAME.azurecr.io/secure-backend:latest"
Set-Location ..

# Create namespace
Write-Host "📦 Creating namespace..." -ForegroundColor Yellow
kubectl create namespace secure-backend --dry-run=client -o yaml | kubectl apply -f -

# Create ACR secret
Write-Host "🔑 Creating ACR secret..." -ForegroundColor Yellow
$acrPassword = az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv
kubectl create secret docker-registry acr-secret --docker-server="$ACR_NAME.azurecr.io" --docker-username=$ACR_NAME --docker-password=$acrPassword --namespace=secure-backend --dry-run=client -o yaml | kubectl apply -f -

# Install nginx ingress if not exists
Write-Host "🌐 Checking nginx ingress..." -ForegroundColor Yellow
$ingressExists = kubectl get namespace ingress-nginx 2>$null
if (-not $ingressExists) {
    Write-Host "📦 Installing nginx ingress controller..." -ForegroundColor Yellow
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
}

# Deploy backend
Write-Host "🚀 Deploying backend application..." -ForegroundColor Yellow
@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-backend
  namespace: secure-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: secure-backend
  template:
    metadata:
      labels:
        app: secure-backend
    spec:
      containers:
      - name: secure-backend
        image: $ACR_NAME.azurecr.io/secure-backend:latest
        ports:
        - containerPort: 8000
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
      imagePullSecrets:
      - name: acr-secret
---
apiVersion: v1
kind: Service
metadata:
  name: secure-backend-service
  namespace: secure-backend
spec:
  selector:
    app: secure-backend
  ports:
  - port: 80
    targetPort: 8000
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-backend-ingress
  namespace: secure-backend
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://frontend-webapp-container.azurewebsites.net"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
spec:
  rules:
  - host: $BACKEND_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-backend-service
            port:
              number: 80
"@ | kubectl apply -f -

# Wait for deployment
Write-Host "⏳ Waiting for deployment..." -ForegroundColor Yellow
kubectl wait --for=condition=available --timeout=300s deployment/secure-backend -n secure-backend

# Get external IP
Write-Host "🌐 Getting ingress external IP..." -ForegroundColor Yellow
do {
    Write-Host "Waiting for external IP..." -ForegroundColor Yellow
    $EXTERNAL_IP = kubectl get svc ingress-nginx-controller --namespace=ingress-nginx --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}"
    Start-Sleep 10
} while (-not $EXTERNAL_IP)

Write-Host "✅ External IP: $EXTERNAL_IP" -ForegroundColor Green

Write-Host "🎉 Deployment completed!" -ForegroundColor Green
Write-Host "📋 Backend URL: https://$BACKEND_DOMAIN" -ForegroundColor Cyan
Write-Host "🧪 Test: curl https://$BACKEND_DOMAIN/health" -ForegroundColor Cyan
