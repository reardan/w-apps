#!/usr/bin/env python3
"""Reference screenshots matching the native mobile acceptance sequence.

Requires pinned Playwright 1.58 and Chromium used by workflow_reference.py.
Uses only browser input and viewport changes; original app and bridge stay intact.
"""
import json
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright
from workflow_server import make_server

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'win/bin/modern-browser/mobile-reference'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    server = make_server()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True, args=['--no-sandbox',
                '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
            page = browser.new_page(viewport={'width': 390, 'height': 720})
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.goto(f'http://127.0.0.1:{server.server_port}/w/tools/web/index.html?module=/w/bin/graphics_ui_mobile.wasm')
            page.wait_for_function("document.getElementById('log').textContent.includes('_start returned (exit 0)')")
            canvas = page.locator('canvas')
            box = canvas.bounding_box()
            page.mouse.click(box['x'] + 30, box['y'] + 150)
            page.wait_for_function("document.activeElement.id === 'text-input'")
            page.keyboard.insert_text('Nativeé🙂')
            page.keyboard.press('Backspace')
            page.wait_for_timeout(200)
            canvas.screenshot(path=str(OUTPUT / 'edited.png'))
            page.set_viewport_size({'width': 360, 'height': 360})
            page.wait_for_timeout(200)
            canvas.screenshot(path=str(OUTPUT / 'narrow.png'))
            box = canvas.bounding_box()
            page.mouse.move(box['x'] + 88, box['y'] + 162)
            page.mouse.wheel(0, 160)
            page.wait_for_timeout(200)
            canvas.screenshot(path=str(OUTPUT / 'scrolled.png'))
            assert not errors, errors
            report = {'status': 'PASS', 'scope': 'reference screenshots, not native acceptance',
                      'browser': browser.version, 'page_errors': errors}
            (OUTPUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print(json.dumps(report))


if __name__ == '__main__':
    main()
