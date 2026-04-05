from fastapi import FastAPI
from fastmcp import FastMCP


mcp = FastMCP("Aveli Minimal MCP")


@mcp.tool
def health_check() -> str:
    """Minimal health tool for MCP verification."""
    return "ok"


mcp_app = mcp.http_app(path="/")

app = FastAPI(title="Aveli Minimal MCP Backend", lifespan=mcp_app.lifespan)


@app.get("/")
async def root() -> str:
    return "MCP-backend körs"


app.mount("/mcp", mcp_app)
