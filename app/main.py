from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.routers import admin, chat, email, order, slack

app = FastAPI(title="AWS Messaging Demo")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat.router,  prefix="/api/chat",  tags=["chat"])
app.include_router(slack.router, prefix="/api/slack", tags=["slack"])
app.include_router(email.router, prefix="/api/email", tags=["email"])
app.include_router(order.router, prefix="/api/order", tags=["order"])
app.include_router(admin.router, prefix="/api/admin", tags=["admin"])

app.mount("/", StaticFiles(directory="frontend", html=True), name="static")
