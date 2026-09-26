#!/usr/bin/env python3
# 网页冒烟测试用的静态服务器：模拟线上 CDN，pck、js、html 用 gzip 压缩传输（浏览器会自动解压）。
# 用法（仓库根目录）：python3 games/emberfall3d/tools/serve_gzip.py . 8765
import gzip, http.server, os, sys
class H(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path): path = os.path.join(path, 'index.html')
        if os.path.isfile(path) and path.endswith(('.pck', '.html', '.js')) and 'gzip' in self.headers.get('Accept-Encoding', ''):
            data = gzip.compress(open(path, 'rb').read())
            self.send_response(200)
            self.send_header('Content-Type', self.guess_type(path))
            self.send_header('Content-Encoding', 'gzip')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            import io; return io.BytesIO(data)
        return super().send_head()
    def log_message(self, *a): pass
os.chdir(sys.argv[1]); http.server.ThreadingHTTPServer(('', int(sys.argv[2])), H).serve_forever()
