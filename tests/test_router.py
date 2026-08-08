
from src.hybrid_router import forward_headers, model_from_body


def test_routes_deepseek_by_prefix():
    assert model_from_body(b'{"model":"deepseek-v4-flash"}') == "deepseek-v4-flash"


def test_invalid_body_returns_empty_model():
    assert model_from_body(b"not-json") == ""


def test_deepseek_strips_openai_credentials():
    headers = {
        "Authorization": "Bearer secret",
        "Cookie": "session=secret",
        "ChatGPT-Account-Id": "account",
        "Content-Type": "application/json",
    }
    result = {key.lower(): value for key, value in forward_headers(headers, True).items()}
    assert "authorization" not in result
    assert "cookie" not in result
    assert "chatgpt-account-id" not in result
    assert result["content-type"] == "application/json"


def test_openai_keeps_authorization():
    result = forward_headers({"Authorization": "Bearer token"}, False)
    assert result["Authorization"] == "Bearer token"


