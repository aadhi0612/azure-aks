#!/bin/bash

# Deploy Frontend to Web App
set -e

RESOURCE_GROUP="bieno-ai05-d-000008-rg"
ACR_NAME="bienoai05000008crn"
FRONTEND_WEBAPP="frontend-webapp-container"

echo "🌐 Deploying Frontend to Web App: $FRONTEND_WEBAPP"

# Login to ACR and build frontend
az acr login --name $ACR_NAME
cd frontend-container
docker build -t $ACR_NAME.azurecr.io/frontend:latest .
docker push $ACR_NAME.azurecr.io/frontend:latest
cd ..

# Deploy to Web App
az webapp config container set \
    --name $FRONTEND_WEBAPP \
    --resource-group $RESOURCE_GROUP \
    --container-image-name $ACR_NAME.azurecr.io/frontend:latest

# Enable HTTPS only
az webapp update \
    --name $FRONTEND_WEBAPP \
    --resource-group $RESOURCE_GROUP \
    --https-only true

# Restart Web App
az webapp restart --name $FRONTEND_WEBAPP --resource-group $RESOURCE_GROUP

echo "✅ Frontend deployed: https://$FRONTEND_WEBAPP.azurewebsites.net"
