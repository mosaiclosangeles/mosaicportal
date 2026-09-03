# The portal reads location.pathname, so /facilities has to serve the app the
# way Cloudflare Pages does rather than 404.
import http.server, socketserver, os
class H(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        p = self.path.split('?')[0].lstrip('/')
        if p.endswith('.js') and os.path.exists(p):
            body = open(p, 'rb').read(); ctype = 'application/javascript'
        else:
            body = open('portal.html', 'rb').read(); ctype = 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(('127.0.0.1', 8100), H).serve_forever()
