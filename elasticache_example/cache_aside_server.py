import json
import os
import sqlite3
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from typing import Any, Optional

try:
    import redis
except ImportError:  # pragma: no cover
    redis = None

BASE_DIR = Path(__file__).resolve().parent
FRONTEND_DIR = BASE_DIR / "frontend"
SQLITE_DB_PATH = Path(os.getenv("SQLITE_DB_PATH", str(BASE_DIR / "products.db")))
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "60"))
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))


def get_db_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with get_db_connection() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                price INTEGER NOT NULL,
                stock INTEGER NOT NULL
            )
            """
        )
        count = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
        if count == 0:
            conn.executemany(
                "INSERT INTO products (id, name, price, stock) VALUES (?, ?, ?, ?)",
                [
                    (1, "Keyboard", 59000, 42),
                    (2, "Monitor", 249000, 15),
                    (3, "Mouse", 29000, 77),
                ],
            )


def create_cache_client() -> Any:
    if redis is None:
        return None

    client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        db=REDIS_DB,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    client.ping()
    return client


class ProductService:
    def __init__(self) -> None:
        self.cache = None
        try:
            self.cache = create_cache_client()
            self.cache_mode = "redis"
        except Exception:
            self.cache_mode = "disabled"

    def get_products(self) -> list[dict[str, Any]]:
        with get_db_connection() as conn:
            rows = conn.execute(
                "SELECT id, name, price, stock FROM products ORDER BY id"
            ).fetchall()
        return [dict(row) for row in rows]

    def _cache_key(self, product_id: int) -> str:
        return f"product:{product_id}"

    def get_product(self, product_id: int) -> Optional[dict[str, Any]]:
        if self.cache:
            cached = self.cache.get(self._cache_key(product_id))
            if cached:
                payload = json.loads(cached)
                payload["cache_hit"] = True
                return payload

        with get_db_connection() as conn:
            row = conn.execute(
                "SELECT id, name, price, stock FROM products WHERE id = ?",
                (product_id,),
            ).fetchone()

        if not row:
            return None

        payload = dict(row)
        payload["cache_hit"] = False
        if self.cache:
            self.cache.setex(
                self._cache_key(product_id),
                CACHE_TTL_SECONDS,
                json.dumps(payload, ensure_ascii=False),
            )
        return payload

    def invalidate_cache(self, product_id: int) -> bool:
        if not self.cache:
            return False
        return bool(self.cache.delete(self._cache_key(product_id)))


class RequestHandler(BaseHTTPRequestHandler):
    service = ProductService()

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path, content_type: str) -> None:
        if not path.exists():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        data = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)

        if parsed.path == "/":
            self._send_file(FRONTEND_DIR / "index.html", "text/html; charset=utf-8")
            return

        if parsed.path == "/static/app.js":
            self._send_file(FRONTEND_DIR / "app.js", "application/javascript; charset=utf-8")
            return

        if parsed.path == "/static/styles.css":
            self._send_file(FRONTEND_DIR / "styles.css", "text/css; charset=utf-8")
            return

        if parsed.path == "/api/health":
            self._send_json(
                {
                    "status": "ok",
                    "cache_mode": self.service.cache_mode,
                    "cache_ttl_seconds": CACHE_TTL_SECONDS,
                }
            )
            return

        if parsed.path == "/api/products":
            self._send_json({"items": self.service.get_products()})
            return

        if parsed.path.startswith("/api/products/"):
            product_id = parsed.path.removeprefix("/api/products/")
            if not product_id.isdigit():
                self._send_json(
                    {"error": "product_id must be numeric"},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return

            product = self.service.get_product(int(product_id))
            if not product:
                self._send_json({"error": "product not found"}, status=HTTPStatus.NOT_FOUND)
                return

            self._send_json(product)
            return

        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/api/cache/invalidate":
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        query = parse_qs(parsed.query)
        product_id_str = query.get("id", [""])[0]
        if not product_id_str.isdigit():
            self._send_json(
                {"error": "query parameter 'id' must be a numeric value"},
                status=HTTPStatus.BAD_REQUEST,
            )
            return

        invalidated = self.service.invalidate_cache(int(product_id_str))
        self._send_json({"invalidated": invalidated})


def run() -> None:
    init_db()
    host = os.getenv("SERVER_HOST", "127.0.0.1")
    port = int(os.getenv("SERVER_PORT", "8080"))
    server = ThreadingHTTPServer((host, port), RequestHandler)
    print(f"Server started: http://{host}:{port}")
    print("- GET  /api/health")
    print("- GET  /api/products")
    print("- GET  /api/products/<id>")
    print("- POST /api/cache/invalidate?id=<id>")
    server.serve_forever()


if __name__ == "__main__":
    run()
