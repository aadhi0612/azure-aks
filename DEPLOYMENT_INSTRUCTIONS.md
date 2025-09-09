# 🚀 Azure AKS Private Deployment Instructions

## 🎯 **GOAL**
Deploy secure backend to **private AKS cluster** `bieno-ai05-d-000008-aks-02` with SSL domain access for frontend Web App.

## ✅ **WHAT TO DO**
1. **Deploy Backend** → Private AKS cluster with nginx ingress
2. **Setup SSL Domain** → `secure-backend-api.northeurope.cloudapp.azure.com`
3. **Deploy Frontend** → Web App with backend integration
4. **Test Connection** → Frontend → SSL → Backend

## ❌ **WHAT NOT TO DO**
- ❌ **Don't create new AKS clusters**
- ❌ **Don't create new VMs/jumpboxes**
- ❌ **Don't modify existing cluster configuration**
- ❌ **Redeploy on existing cluster only**

---

## 📋 **Prerequisites on DTL Machine BNLWEDT56807029**

### Install Required Tools:
```powershell
# 1. Install Azure CLI
winget install Microsoft.AzureCLI

# 2. Install Docker Desktop
winget install Docker.DockerDesktop

# 3. Install Git
winget install Git.Git

# 4. Install kubectl and kubelogin
az aks install-cli
```

### Verify Installation:
```powershell
az --version
docker --version
kubectl version --client
git --version
```

---

## 🔄 **Deployment Steps**

### Step 1: Clone Repository
```bash
git clone https://github.com/aadhi0612/azure-aks-private-deployment.git
cd azure-aks-private-deployment
```

### Step 2: Login to Azure
```bash
az login
az account set --subscription 753dbb7c-775c-45b0-b7ee-c3e82245fbf2
```

### Step 3: Connect to Private AKS
```bash
az aks get-credentials --resource-group bieno-ai05-d-000008-rg --name bieno-ai05-d-000008-aks-02 --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
```

### Step 4: Test AKS Connection
```bash
kubectl get nodes
# Should show cluster nodes without errors
```

### Step 5: Deploy Backend to AKS
```bash
chmod +x deploy-backend-aks.sh
./deploy-backend-aks.sh
```

### Step 6: Deploy Frontend to Web App
```bash
chmod +x deploy-frontend-webapp.sh
./deploy-frontend-webapp.sh
```

---

## 🧪 **Testing & Verification**

### Test Backend Health:
```bash
curl https://secure-backend-api.northeurope.cloudapp.azure.com/health
```

### Test Frontend:
```
https://frontend-webapp-container.azurewebsites.net
```

### Test Integration:
1. Open frontend URL
2. Click "Use Demo Mode"
3. Fill form and submit
4. Should get response from AKS backend

---

## 🔧 **Troubleshooting**

### If AKS Connection Fails:
```bash
# Check cluster status
az aks show --resource-group bieno-ai05-d-000008-rg --name bieno-ai05-d-000008-aks-02 --query "powerState"

# Re-authenticate
kubelogin convert-kubeconfig -l azurecli
```

### If Backend Deployment Fails:
```bash
# Check pods
kubectl get pods -n secure-backend

# Check logs
kubectl logs -l app=secure-backend -n secure-backend
```

### If Domain Not Accessible:
```bash
# Check ingress
kubectl get ingress -n secure-backend

# Check external IP
kubectl get svc -n ingress-nginx
```

---

## 📊 **Expected Results**

### ✅ **Success Indicators:**
- Backend pods running in AKS: `kubectl get pods -n secure-backend`
- External IP assigned: `kubectl get svc -n ingress-nginx`
- Domain resolves: `nslookup secure-backend-api.northeurope.cloudapp.azure.com`
- SSL certificate active: `curl -I https://secure-backend-api.northeurope.cloudapp.azure.com`
- Frontend connects to backend successfully

### 🌐 **Final URLs:**
- **Frontend**: `https://frontend-webapp-container.azurewebsites.net`
- **Backend**: `https://secure-backend-api.northeurope.cloudapp.azure.com`

---

## 📞 **Support**

If deployment fails:
1. Check DTL machine has network access to private AKS
2. Verify Azure CLI authentication
3. Check kubectl connection to cluster
4. Review error logs from deployment scripts

**Goal: Backend in private AKS accessible via SSL domain from frontend Web App** 🎯
