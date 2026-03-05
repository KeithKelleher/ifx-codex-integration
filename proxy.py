import os
import logging
import json
from urllib.parse import urlencode
from typing import Any, Optional

import httpx
from fastapi import FastAPI, Request, Response

logging.basicConfig(
    filename="proxy.log",
    level=logging.INFO,
    format="%(asctime)s %(message)s",
)

app = FastAPI()

AZURE_BASE_URL = os.environ.get("AZURE_BASE_URL", "https://ncatsaopenai.openai.azure.com").rstrip("/")
AZURE_API_VERSION = os.environ.get("AZURE_API_VERSION", "2025-04-01-preview")
PROXY_TIMEOUT_SECONDS = float(os.environ.get("PROXY_TIMEOUT_SECONDS", "60"))

# For now we just reuse the same token environment variable you already export
def get_bearer_token() -> str:
    token = os.environ.get("AZURE_OPENAI_API_KEY")
    if not token:
        raise RuntimeError("AZURE_OPENAI_API_KEY not set")
    return token


def parse_json_body(body_bytes: bytes) -> Optional[dict[str, Any]]:
    body_str = body_bytes.decode("utf-8", errors="replace")
    try:
        return json.loads(body_str)
    except json.JSONDecodeError:
        return None
    except Exception:
        logging.exception("Failed to parse request body as JSON")
        return None


def remove_ncats_unsupported_tools(body_json: dict[str, Any]) -> dict[str, Any]:
    tools = body_json.get("tools")
    if not isinstance(tools, list):
        return body_json

    filtered_tools = [
        tool
        for tool in tools
        if not (
            tool.get("type") == "web_search"
            or tool.get("name") == "web_search_preview"
        )
    ]
    body_json["tools"] = filtered_tools
    return body_json


def sanitize_request_body(body_bytes: bytes) -> bytes:
    body_json = parse_json_body(body_bytes)
    if body_json is None:
        return body_bytes
    sanitized_json = remove_ncats_unsupported_tools(body_json)
    return json.dumps(sanitized_json).encode("utf-8")


def build_target_url(path: str, request: Request) -> str:
    target_url = f"{AZURE_BASE_URL}/{path}"
    query_items = list(request.query_params.multi_items())
    if not any(key == "api-version" for key, _ in query_items):
        query_items.append(("api-version", AZURE_API_VERSION))
    if query_items:
        return f"{target_url}?{urlencode(query_items, doseq=True)}"
    return target_url


def build_upstream_headers(request: Request) -> dict[str, str]:
    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("api-key", None)
    headers.pop("content-length", None)
    headers["Authorization"] = f"Bearer {get_bearer_token()}"
    return headers


def build_downstream_headers(upstream_headers: httpx.Headers) -> dict[str, str]:
    response_headers = dict(upstream_headers)
    response_headers.pop("content-length", None)
    response_headers.pop("transfer-encoding", None)
    return response_headers


async def forward_request(
    method: str,
    target_url: str,
    headers: dict[str, str],
    body: bytes,
) -> httpx.Response:
    async with httpx.AsyncClient(timeout=PROXY_TIMEOUT_SECONDS) as client:
        return await client.request(
            method=method,
            url=target_url,
            headers=headers,
            content=body,
        )


def build_upstream_error_response(exc: Exception) -> Response:
    return Response(
        content=json.dumps({"error": "upstream_request_failed", "detail": str(exc)}),
        status_code=502,
        media_type="application/json",
    )


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    try:
        body = sanitize_request_body(await request.body())
        target_url = build_target_url(path, request)
        headers = build_upstream_headers(request)
        azure_response = await forward_request(
            method=request.method,
            target_url=target_url,
            headers=headers,
            body=body,
        )
    except httpx.HTTPError as exc:
        logging.exception("Upstream Azure request failed")
        return build_upstream_error_response(exc)
    except Exception:
        logging.exception("Unhandled proxy error")
        raise

    response_headers = build_downstream_headers(azure_response.headers)
    return Response(
        content=azure_response.content,
        status_code=azure_response.status_code,
        headers=response_headers,
    )
