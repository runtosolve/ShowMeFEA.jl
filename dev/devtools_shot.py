# Drive headless Chrome over the DevTools protocol: load a page, wait for the ShowMeFEA page to render, optionally run
# JavaScript, then capture a screenshot.   python3 devtools_shot.py <file path> <out.png> [js] [timeout s]
import asyncio, json, subprocess, sys, re, base64, urllib.request, time, os, tempfile
import websockets
url = 'file://' + sys.argv[1].replace(' ', '%20'); out = sys.argv[2]; js = sys.argv[3] if len(sys.argv) > 3 else ''; tmo = float(sys.argv[4]) if len(sys.argv) > 4 else 150
prof = tempfile.mkdtemp(prefix='smfprof')
chrome = subprocess.Popen(["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "--headless=new", "--disable-gpu", "--use-gl=angle",
    "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox", "--window-size=1500,1100", "--remote-debugging-port=0",
    "--user-data-dir=" + prof, "about:blank"], stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
port = None; t0 = time.time()
while time.time() - t0 < 30:
    line = chrome.stderr.readline()
    m = re.search(r'DevTools listening on ws://127\.0\.0\.1:(\d+)/', line)
    if m: port = m.group(1); break
if port is None: print('no devtools port'); chrome.kill(); sys.exit(1)
req = urllib.request.Request(f'http://127.0.0.1:{port}/json/new?{url}', method='PUT')
target = json.loads(urllib.request.urlopen(req).read())
async def main():
    async with websockets.connect(target['webSocketDebuggerUrl'], max_size=2**28) as ws:
        n = 0
        async def call(method, **params):
            nonlocal n; n += 1
            await ws.send(json.dumps({'id': n, 'method': method, 'params': params}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get('id') == n: return msg.get('result', msg)
        async def ev(expr):
            r = await call('Runtime.evaluate', expression=expr, returnByValue=True, awaitPromise=True)
            return r.get('result', {}).get('value'), r.get('exceptionDetails')
        await call('Page.enable'); await call('Runtime.enable')
        t0 = time.time(); rendered = None
        while time.time() - t0 < tmo:
            rendered, _ = await ev('window.__smf_rendered || 0')
            if rendered: break
            await asyncio.sleep(1)
        print('rendered after', round(time.time() - t0, 1), 's:', rendered)
        if js:
            val, exc = await ev(js); print('js ->', val, '' if exc is None else exc.get('exception', {}).get('description', exc))
            await asyncio.sleep(1.5)
        shot = await call('Page.captureScreenshot', format='png')
        open(out, 'wb').write(base64.b64decode(shot['data'])); print('wrote', out)
try: asyncio.run(main())
finally: chrome.kill()
