#!/usr/bin/env python3
"""Local Ollama chat bridge for the Aetheric Shell AI panel.

Request (stdin, one JSON object):
    {"model": str, "messages": [{"role": "user"|"assistant"|"system", "content": str}],
     "num_ctx": int (optional, default 8192),
     "temperature": float (optional, default 0.7, clamped to 0..2)}

Response (stdout, NDJSON, one event per line, flushed per event):
    {"type": "chunk", "content": str}
    {"type": "done", "prompt_tokens": int, "output_tokens": int,
     "total_ns": int, "eval_ns": int, "load_ns": int, "prompt_ns": int}
    {"type": "error", "message": str}
    {"type": "offline", "message": str}       # server unreachable

"--list-models" instead prints:
    {"type": "models", "models": [{"name": str, "size": int, "modified": str}]}
    or {"type": "offline", ...}

The endpoint is fixed to the loopback interface. Prompts are never logged or
persisted by this bridge; stdout is the only channel back to the shell.
Exit code 0 on success, 1 on failure (after the error event is emitted).
"""

import json
import sys
import urllib.error
import urllib.request

HOST = "http://127.0.0.1:11434"
LIST_TIMEOUT = 5
CHAT_TIMEOUT = 300
DEFAULT_NUM_CTX = 8192
DEFAULT_TEMPERATURE = 0.7


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def fail(message):
    emit({"type": "error", "message": message})
    return 1


def offline(exc):
    reason = getattr(exc, "reason", exc)
    emit({"type": "offline", "message": "Ollama unreachable at %s: %s" % (HOST, reason)})
    return 1


def request(path, payload=None, timeout=LIST_TIMEOUT):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"} if body is not None else {}
    req = urllib.request.Request(HOST + path, data=body, headers=headers)
    return urllib.request.urlopen(req, timeout=timeout)


def list_models():
    try:
        with request("/api/tags") as resp:
            raw = json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        return fail("Ollama HTTP %s while listing models" % exc.code)
    except urllib.error.URLError as exc:
        return offline(exc)
    except Exception as exc:  # noqa: BLE001 - process boundary
        return fail("model listing failed: %s" % exc)
    models = [
        {
            "name": entry.get("name", ""),
            "size": int(entry.get("size") or 0),
            "modified": entry.get("modified_at", ""),
        }
        for entry in raw.get("models", [])
    ]
    emit({"type": "models", "models": models})
    return 0


def chat():
    # One JSON object per line: the caller keeps stdin open for the lifetime
    # of the process, so read a line instead of waiting for EOF.
    try:
        payload = json.loads(sys.stdin.readline())
    except Exception:  # noqa: BLE001 - process boundary
        return fail("invalid request payload")
    model = str(payload.get("model") or "").strip()
    messages = payload.get("messages")
    if not model or not isinstance(messages, list) or not messages:
        return fail("missing model or messages")
    try:
        num_ctx = int(payload.get("num_ctx") or DEFAULT_NUM_CTX)
    except (TypeError, ValueError):
        num_ctx = DEFAULT_NUM_CTX
    try:
        temperature = float(payload.get("temperature"))
        if not 0.0 <= temperature <= 2.0:
            temperature = DEFAULT_TEMPERATURE
    except (TypeError, ValueError):
        temperature = DEFAULT_TEMPERATURE

    body = {
        "model": model,
        "messages": messages,
        "stream": True,
        "options": {"num_ctx": num_ctx, "temperature": temperature},
    }
    try:
        resp = request("/api/chat", body, timeout=CHAT_TIMEOUT)
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = json.loads(exc.read().decode("utf-8", "replace")).get("error", "")
        except Exception:  # noqa: BLE001 - best-effort detail
            pass
        return fail(detail or ("Ollama HTTP %s" % exc.code))
    except urllib.error.URLError as exc:
        return offline(exc)
    except Exception as exc:  # noqa: BLE001 - process boundary
        return fail("chat request failed: %s" % exc)

    seen_content = False
    try:
        for raw_line in resp:
            line = raw_line.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except Exception:  # noqa: BLE001 - skip malformed keepalives
                continue
            if event.get("error"):
                return fail(str(event["error"]))
            piece = (event.get("message") or {}).get("content") or ""
            if piece:
                seen_content = True
                emit({"type": "chunk", "content": piece})
            if event.get("done"):
                emit(
                    {
                        "type": "done",
                        "prompt_tokens": int(event.get("prompt_eval_count") or 0),
                        "output_tokens": int(event.get("eval_count") or 0),
                        "total_ns": int(event.get("total_duration") or 0),
                        "eval_ns": int(event.get("eval_duration") or 0),
                        "load_ns": int(event.get("load_duration") or 0),
                        "prompt_ns": int(event.get("prompt_eval_duration") or 0),
                    }
                )
                return 0
    except Exception as exc:  # noqa: BLE001 - stream boundary
        return fail("stream interrupted: %s" % exc)
    finally:
        try:
            resp.close()
        except Exception:  # noqa: BLE001 - close best effort
            pass

    if seen_content:
        emit(
            {
                "type": "done",
                "prompt_tokens": 0,
                "output_tokens": 0,
                "total_ns": 0,
                "eval_ns": 0,
                "load_ns": 0,
                "prompt_ns": 0,
            }
        )
        return 0
    return fail("empty response from Ollama")


def main():
    if "--list-models" in sys.argv[1:]:
        return list_models()
    return chat()


if __name__ == "__main__":
    sys.exit(main())
