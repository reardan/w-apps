#!/usr/bin/env python3
"""Reference Chromium evidence for the unchanged W graphics and mobile hosts.

Requires Playwright 1.58 and prebuilt graphics_demo/graphics_ui_mobile wasm.
External observations/input only: no host, bridge or wasm source modifications.
"""
import argparse
import json
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright
from workflow_server import make_server

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'win/bin/modern-browser/reference')
    opts = parser.parse_args()
    opts.output.mkdir(parents=True, exist_ok=True)
    server = make_server()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/'
    report = {'scope':'reference engine observations, not Win acceptance', 'hosts':{}}
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
            report['browser'] = browser.version
            page = browser.new_page(viewport={'width':800,'height':600})
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            for milestone, module in [('M1', 'graphics_demo.wasm'), ('M2', 'graphics_ui_mobile.wasm')]:
                page.goto(base + module)
                try:
                    page.wait_for_function("document.getElementById('log').textContent.includes('_start returned (exit 0)')")
                except Exception:
                    report['failure'] = {'milestone':milestone, 'errors':errors, 'log':page.locator('#log').inner_text()}
                    page.screenshot(path=str(opts.output / 'host-reference-failure.png'))
                    raise
                assert not errors, errors
                first = page.locator('canvas').screenshot()
                page.wait_for_timeout(200)
                second = page.locator('canvas').screenshot()
                if milestone == 'M1':
                    assert first != second, 'unchanged graphics host did not animate'
                times = page.evaluate("""() => new Promise(resolve => {
                    const times=[]; function sample(t) { times.push(t); if(times.length===12)resolve(times);else requestAnimationFrame(sample); } requestAnimationFrame(sample);
                })""")
                data = {'title':page.title(), 'frame_samples_ms':times, 'page_errors':list(errors)}
                page.screenshot(path=str(opts.output / f'{milestone}-800x600.png'))
                page.set_viewport_size({'width':360,'height':640})
                page.wait_for_timeout(250)
                size = page.locator('canvas').bounding_box()
                assert size['width'] <= 360 and size['height'] <= 640, size
                data['narrow_canvas'] = size
                if milestone == 'M2':
                    page.mouse.click(size['x'] + 30, size['y'] + 150)
                    page.wait_for_function("document.activeElement.id==='text-input'")
                    page.keyboard.insert_text('Ada')
                    page.wait_for_timeout(200)
                    data['editor_focused'] = True
                    # The hidden editor is a sentinel sink, reset after input;
                    # rendered text belongs to the wasm UI, not its value.
                    data['text_input_sent'] = 'Ada'
                    page.screenshot(path=str(opts.output / 'M2-typed-Ada.png'))
                    page.mouse.wheel(0, 120)
                    page.wait_for_timeout(200)
                page.screenshot(path=str(opts.output / f'{milestone}-360x640.png'))
                assert not errors, errors
                report['hosts'][milestone] = data
                page.goto('about:blank')
                page.set_viewport_size({'width':800,'height':600})
            browser.close()
        report['status'] = 'PASS'
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (opts.output / 'modern-hosts.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
