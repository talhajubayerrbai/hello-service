from fastapi import FastAPI

from app.routers import health, api

app = FastAPI(title="hello-service", version="1.0.0")

app.include_router(health.router, prefix='/health', tags=['health'])
app.include_router(api.router,    prefix='/api',    tags=['api'])


@app.get('/')
def root():
    return {"message": "Hello from hello-service!"}
