#!/usr/bin/env python3
# Faux Grafana Cloud : accepte (ou refuse) tout POST. Le code renvoye est lu
# dans /etc/mock-status a chaque requete (204 par defaut, 401 = mauvais
# identifiants).
import http.server


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self.rfile.read(n)
        try:
            code = int(open("/etc/mock-status").read().strip())
        except Exception:
            code = 204
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_GET = do_POST

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", 9999), H).serve_forever()
