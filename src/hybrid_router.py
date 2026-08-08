
from __future__ import annotations

import json
import os
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from starlette.background import BackgroundTask


OPENAI_CODEX_BASE = os.getenv("OPENAI_CODEX_BASE", "https://chatgpt.com/backend-api/codex")
DEEPSEEK_PROXY_BASE = os.getenv("DEEPSEEK_PROXY_BASE", "http://127.0.0.1:4141")

HOP_BY_HOP_HEADERS = {
    "connection", "content-length", "host", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade",
}
DECODED_RESPONSE_HEADERS = {"content-encoding"}
DEEPSEEK_SENSITIVE_HEADERS = {
    "authorization", "chatgpt-account-id", "cookie", "openai-organization", "openai-project",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(timeout=None, follow_redirects=False)
    yield
    await app.state.client.aclose()


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/health/liveliness")
async def health() -> dict[str, str]:
    return {"status": "ok"}


def model_from_body(body: bytes) -> str:
    if not body:
        return ""
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return ""
    model = payload.get("model") if isinstance(payload, dict) else None
    return model if isinstance(model, str) else ""


def forward_headers(headers, deepseek: bool) -> dict[str, str]:
    result: dict[str, str] = {}
    for name, value in headers.items():
        lower_name = name.lower()
        if lower_name in HOP_BY_HOP_HEADERS:
            continue
        if deepseek and lower_name in DEEPSEEK_SENSITIVE_HEADERS:
            continue
        result[name] = value
    return result


def response_headers(response: httpx.Response) -> dict[str, str]:
    return {
        name: value
        for name, value in response.headers.items()
        if name.lower() not in HOP_BY_HOP_HEADERS
        and name.lower() not in DECODED_RESPONSE_HEADERS
    }


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
async def route_request(path: str, request: Request):
    body = await request.body()
    model = model_from_body(body)
    use_deepseek = model.startswith("deepseek-")

    if use_deepseek:
        target_path = path
        target_base = DEEPSEEK_PROXY_BASE
    else:
        target_path = path[3:] if path.startswith("v1/") else path
        target_base = OPENAI_CODEX_BASE

    target_url = f"{target_base}/{target_path}"
    if request.url.query:
        target_url = f"{target_url}?{request.url.query}"

    upstream_request = request.app.state.client.build_request(
        request.method,
        target_url,
        headers=forward_headers(request.headers, use_deepseek),
        content=body,
    )
    try:
        upstream = await request.app.state.client.send(upstream_request, stream=True)
    except httpx.HTTPError:
        return JSONResponse(
            status_code=502,
            content={"error": {"message": "The local hybrid router could not reach the upstream provider."}},
        )

    return StreamingResponse(
        upstream.aiter_bytes(),
        status_code=upstream.status_code,
        headers=response_headers(upstream),
        background=BackgroundTask(upstream.aclose),
    )


