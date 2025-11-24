from fastapi import FastAPI

from ..routes import (
    api_auth,
    api_feed,
    api_me,
    api_orders,
    api_payments,
    api_services,
    api_sfu,
    billing,
)

app = FastAPI(
    title="Aveli MVP API",
    version="0.1.0",
    description=(
        "Minimal FastAPI application that exposes the endpoints required "
        "for the subscription MVP (auth, services, orders, payments, feed, SFU)."
    ),
)

app.include_router(api_auth.router)
app.include_router(billing.router)
app.include_router(api_services.router)
app.include_router(api_orders.router)
app.include_router(api_payments.router)
app.include_router(api_feed.router)
app.include_router(api_sfu.router)
app.include_router(api_me.router)


@app.get("/healthz")
def healthcheck():
    return {"ok": True}
