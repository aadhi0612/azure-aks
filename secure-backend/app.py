from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Secure Backend API", version="1.0.0")

# CORS for frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://frontend-webapp-container.azurewebsites.net",
        "https://*.azurewebsites.net"
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

security = HTTPBearer()

class UserData(BaseModel):
    firstName: str
    lastName: str
    textData: str

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    if token == "demo-secure-token":
        return {"authenticated": True, "user": "demo-user"}
    raise HTTPException(status_code=401, detail="Invalid token")

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "secure-backend-aks"
    }

@app.post("/process")
async def process_data(data: UserData, auth=Depends(verify_token)):
    return {
        "message": f"Hello {data.firstName} {data.lastName}. Received: {data.textData}",
        "authentication_analysis": {
            "timestamp": datetime.now().isoformat(),
            "authenticated": True,
            "service": "Private AKS Backend"
        },
        "processing_details": {
            "data_length": len(data.textData),
            "processed_at": datetime.now().isoformat()
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
