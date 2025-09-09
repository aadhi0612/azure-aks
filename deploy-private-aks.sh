#!/bin/bash

# Deploy to Private AKS Cluster with Nginx Ingress
# Run this script from a machine that has access to the private AKS cluster

set -e

# Configuration
RESOURCE_GROUP="bieno-ai05-d-000008-rg"
ACR_NAME="bienoai05000008crn"
AKS_CLUSTER="bieno-ai05-d-000008-aks-02"
SUBSCRIPTION_ID="753dbb7c-775c-45b0-b7ee-c3e82245fbf2"

echo "🚀 Deploying to Private AKS Cluster: $AKS_CLUSTER"

# Set subscription
echo "📋 Setting subscription..."
az account set --subscription $SUBSCRIPTION_ID

# Get AKS credentials
echo "🔑 Getting AKS credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --overwrite-existing

# Use kubelogin for authentication
echo "🔐 Converting kubeconfig for authentication..."
kubelogin convert-kubeconfig -l azurecli

# Test connection
echo "🧪 Testing cluster connection..."
kubectl get nodes

# Login to ACR
echo "🐳 Logging into ACR..."
az acr login --name $ACR_NAME

# Build and push backend image
echo "🏗️ Building backend image..."
cd secure-backend
docker build -t $ACR_NAME.azurecr.io/secure-backend:latest .
docker push $ACR_NAME.azurecr.io/secure-backend:latest
cd ..

# Create ACR secret for pulling images
echo "🔑 Creating ACR secret..."
kubectl create secret docker-registry acr-secret \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$ACR_NAME \
    --docker-password=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv) \
    --namespace=secure-backend \
    --dry-run=client -o yaml | kubectl apply -f -

# Install nginx ingress controller if not exists
echo "🌐 Checking nginx ingress controller..."
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo "📦 Installing nginx ingress controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    # Wait for ingress controller to be ready
    echo "⏳ Waiting for ingress controller..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
else
    echo "✅ Nginx ingress controller already installed"
fi

# Install cert-manager if not exists
echo "🔒 Checking cert-manager..."
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo "📦 Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    echo "⏳ Waiting for cert-manager..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=cert-manager \
        --timeout=300s
else
    echo "✅ Cert-manager already installed"
fi

# Create Let's Encrypt cluster issuer
echo "🔐 Creating Let's Encrypt cluster issuer..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Deploy backend application
echo "🚀 Deploying backend application..."
kubectl apply -f secure-backend/k8s-deployment.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for backend deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/secure-backend -n secure-backend

# Get ingress external IP
echo "🌐 Getting ingress external IP..."
EXTERNAL_IP=""
while [ -z $EXTERNAL_IP ]; do
    echo "Waiting for external IP..."
    EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller --namespace=ingress-nginx --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
    [ -z "$EXTERNAL_IP" ] && sleep 10
done

echo "✅ External IP: $EXTERNAL_IP"

# Get ingress status
echo "📊 Ingress status:"
kubectl get ingress -n secure-backend

# Test backend health
echo "🧪 Testing backend health..."
kubectl port-forward -n secure-backend svc/secure-backend-service 8080:80 &
PF_PID=$!
sleep 5

if curl -f http://localhost:8080/health; then
    echo "✅ Backend health check passed"
else
    echo "❌ Backend health check failed"
fi

kill $PF_PID

echo "🎉 Deployment completed!"
echo "📋 Next steps:"
echo "1. Update DNS to point your domain to: $EXTERNAL_IP"
echo "2. Update frontend to use your backend domain"
echo "3. SSL certificates will be automatically provisioned"
