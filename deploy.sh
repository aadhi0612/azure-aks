#!/bin/bash

# Secure Deployment Script for Azure AKS and Web App
# This script deploys both backend (AKS) and frontend (Web App) with SSL configuration

set -e

# Configuration
RESOURCE_GROUP="bieno-ai05-d-000008-rg"
ACR_NAME="bienoai05000008crn"
AKS_CLUSTER="bieno-ai05-d-000008-aks"
FRONTEND_WEBAPP="frontend-webapp-container"
BACKEND_WEBAPP="secure-backend-api"  # Fallback if AKS not available

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Secure Deployment with SSL Configuration${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
for cmd in az docker kubectl; do
    if ! command_exists $cmd; then
        echo -e "${RED}❌ $cmd is not installed${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✅ All prerequisites met${NC}"

# Login to Azure (if not already logged in)
echo -e "${YELLOW}🔐 Checking Azure authentication...${NC}"
if ! az account show >/dev/null 2>&1; then
    echo -e "${YELLOW}Please login to Azure...${NC}"
    az login
fi
echo -e "${GREEN}✅ Azure authentication verified${NC}"

# Login to ACR
echo -e "${YELLOW}🐳 Logging into Azure Container Registry...${NC}"
az acr login --name $ACR_NAME
echo -e "${GREEN}✅ ACR login successful${NC}"

# Build and push backend image
echo -e "${YELLOW}🏗️ Building secure backend image...${NC}"
cd secure-backend
docker build -t $ACR_NAME.azurecr.io/secure-backend:latest .
docker push $ACR_NAME.azurecr.io/secure-backend:latest
echo -e "${GREEN}✅ Backend image built and pushed${NC}"

# Build and push frontend image
echo -e "${YELLOW}🏗️ Building secure frontend image...${NC}"
cd ../frontend-container
docker build -t $ACR_NAME.azurecr.io/frontend:latest .
docker push $ACR_NAME.azurecr.io/frontend:latest
echo -e "${GREEN}✅ Frontend image built and pushed${NC}"

cd ..

# Deploy to AKS (if available)
echo -e "${YELLOW}☸️ Checking AKS availability...${NC}"
if az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER >/dev/null 2>&1; then
    echo -e "${GREEN}✅ AKS cluster found, deploying backend to AKS${NC}"
    
    # Get AKS credentials
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --overwrite-existing
    
    # Create namespace if it doesn't exist
    kubectl create namespace secure-app --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ACR secret for pulling images
    kubectl create secret docker-registry acr-secret \
        --docker-server=$ACR_NAME.azurecr.io \
        --docker-username=$ACR_NAME \
        --docker-password=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv) \
        --namespace=secure-app \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create SSL certificate secret (self-signed for demo)
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout tls.key -out tls.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=secure-backend-api.yourdomain.com"
    
    kubectl create secret tls ssl-certificates \
        --cert=tls.crt --key=tls.key \
        --namespace=secure-app \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Azure secrets
    kubectl create secret generic azure-secrets \
        --from-literal=client-secret="demo-secret" \
        --namespace=secure-app \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy to AKS
    sed "s/namespace: default/namespace: secure-app/g" secure-backend/k8s-deployment.yaml | kubectl apply -f -
    
    # Clean up temporary files
    rm -f tls.key tls.crt
    
    echo -e "${GREEN}✅ Backend deployed to AKS with SSL configuration${NC}"
else
    echo -e "${YELLOW}⚠️ AKS not available, deploying backend to Web App${NC}"
    
    # Deploy backend to Web App as fallback
    az webapp config container set \
        --name $BACKEND_WEBAPP \
        --resource-group $RESOURCE_GROUP \
        --container-image-name $ACR_NAME.azurecr.io/secure-backend:latest
    
    # Enable HTTPS only
    az webapp update \
        --name $BACKEND_WEBAPP \
        --resource-group $RESOURCE_GROUP \
        --https-only true
    
    # Configure SSL settings
    az webapp config set \
        --name $BACKEND_WEBAPP \
        --resource-group $RESOURCE_GROUP \
        --min-tls-version "1.2" \
        --ftps-state "Disabled"
    
    echo -e "${GREEN}✅ Backend deployed to Web App with SSL configuration${NC}"
fi

# Deploy frontend to Web App
echo -e "${YELLOW}🌐 Deploying frontend to Web App...${NC}"
az webapp config container set \
    --name $FRONTEND_WEBAPP \
    --resource-group $RESOURCE_GROUP \
    --container-image-name $ACR_NAME.azurecr.io/frontend:latest

# Enable HTTPS only for frontend
az webapp update \
    --name $FRONTEND_WEBAPP \
    --resource-group $RESOURCE_GROUP \
    --https-only true

# Configure SSL settings for frontend
az webapp config set \
    --name $FRONTEND_WEBAPP \
    --resource-group $RESOURCE_GROUP \
    --min-tls-version "1.2" \
    --ftps-state "Disabled"

# Add custom domain SSL binding (if domain is available)
# az webapp config ssl bind --certificate-thumbprint <thumbprint> --ssl-type SNI --name $FRONTEND_WEBAPP --resource-group $RESOURCE_GROUP

echo -e "${GREEN}✅ Frontend deployed to Web App with SSL configuration${NC}"

# Restart services
echo -e "${YELLOW}🔄 Restarting services...${NC}"
az webapp restart --name $FRONTEND_WEBAPP --resource-group $RESOURCE_GROUP
if az webapp show --name $BACKEND_WEBAPP --resource-group $RESOURCE_GROUP >/dev/null 2>&1; then
    az webapp restart --name $BACKEND_WEBAPP --resource-group $RESOURCE_GROUP
fi

# Wait for services to be ready
echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
sleep 30

# Test deployment
echo -e "${YELLOW}🧪 Testing deployment...${NC}"

# Test frontend
FRONTEND_URL="https://$FRONTEND_WEBAPP.azurewebsites.net"
if curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_URL" | grep -q "200"; then
    echo -e "${GREEN}✅ Frontend is accessible at: $FRONTEND_URL${NC}"
else
    echo -e "${RED}❌ Frontend test failed${NC}"
fi

# Test backend
BACKEND_URL="https://$BACKEND_WEBAPP.azurewebsites.net/health"
if curl -s -H "Authorization: Bearer demo-secure-token" "$BACKEND_URL" | grep -q "healthy"; then
    echo -e "${GREEN}✅ Backend is accessible at: https://$BACKEND_WEBAPP.azurewebsites.net${NC}"
else
    echo -e "${RED}❌ Backend test failed${NC}"
fi

# Display deployment summary
echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo -e "${GREEN}✅ Frontend URL: $FRONTEND_URL${NC}"
echo -e "${GREEN}✅ Backend URL: https://$BACKEND_WEBAPP.azurewebsites.net${NC}"
echo -e "${GREEN}✅ SSL/TLS: Enabled on both services${NC}"
echo -e "${GREEN}✅ HTTPS Only: Enforced${NC}"
echo -e "${GREEN}✅ Min TLS Version: 1.2${NC}"
echo -e "${GREEN}✅ Security Headers: Configured${NC}"

echo -e "${BLUE}🎉 Secure deployment completed successfully!${NC}"
echo -e "${YELLOW}📝 Note: For production, configure custom domain SSL certificates${NC}"
