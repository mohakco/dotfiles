import os

import backoff
import httpx

E = os.environ
USER, PASSWORD = E["ADMIN_USER"], E["ADMIN_PASSWORD"]
KEYS = "/config/homepage-keys"


def log(*args):
    print("[setup]", *args, flush=True)


def csv(name):
    return [v.strip() for v in E.get(name, "").split(",") if v.strip()]


@backoff.on_predicate(backoff.constant, interval=3, max_time=300)
def _up(url):
    try:
        return httpx.get(url, timeout=5).status_code < 500
    except httpx.HTTPError:
        return False


def wait(url):
    if not _up(url):
        raise SystemExit(f"{url} is not reachable")


def _raise(response):
    if response.is_error:
        response.read()
        raise httpx.HTTPStatusError(
            f"{response.request.method} {response.url} -> {response.status_code}: {response.text[:300]}",
            request=response.request,
            response=response,
        )


def client(base_url, **kwargs):
    return httpx.Client(base_url=base_url, timeout=120, event_hooks={"response": [_raise]}, **kwargs)


def fields(schema, **values):
    for field in schema["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    return schema


def save_key(name, key):
    with open(f"{KEYS}/{name}", "w") as f:
        f.write(key)
