#!/usr/bin/env python3
"""Reference-browser oracle for the M3 fixture (requires Playwright 1.58).

Run using an environment containing playwright and its Chromium installation.
This verifies the application scenario; it does not establish Win compatibility.
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
    url = f'http://127.0.0.1:{server.server_port}/win/fixtures/workflow/index.html'
    report = {'url': url, 'checks': []}
    try:
        with sync_playwright() as p:
            profile = opts.output / 'profile'
            context = p.chromium.launch_persistent_context(str(profile), headless=True, viewport={'width':800,'height':600}, args=['--no-sandbox'])
            report['browser'] = context.browser.version if context.browser else 'Chromium persistent context'
            page = context.pages[0]
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.goto(url)
            page.locator('#name').fill('Ada')
            page.locator('#save').click()
            page.wait_for_function("document.querySelector('#result').textContent === 'Saved: Ada'")
            report['checks'].append('JSON POST success')
            page.locator('#name').fill('error')
            page.locator('#save').click()
            page.wait_for_function("document.querySelector('#result').textContent === 'Failed: HTTP 503'")
            report['checks'].append('HTTP failure')
            page.locator('#name').fill('slow')
            page.locator('#save').click()
            page.locator('#cancel').click()
            page.wait_for_function("document.querySelector('#result').textContent === 'Cancelled'")
            page.wait_for_timeout(2200)
            assert page.locator('#result').inner_text() == 'Cancelled'
            report['checks'].append('Abort without late success')
            page.locator('#settings-route').click()
            page.locator('#theme').select_option('green')
            page.go_back()
            page.wait_for_selector('#name')
            assert '?view=' not in page.url
            page.go_forward()
            assert page.locator('#theme').input_value() == 'green'
            page.screenshot(path=str(opts.output / 'workflow-800x600.png'))
            page.set_viewport_size({'width':360,'height':640})
            page.screenshot(path=str(opts.output / 'workflow-360x640.png'))
            assert page.locator('main').bounding_box()['width'] <= 360
            assert not errors, errors
            report['checks'].extend(['Routing/back/forward', 'Responsive screenshots'])
            context.close()
            context = p.chromium.launch_persistent_context(str(profile), headless=True, args=['--no-sandbox'])
            page = context.pages[0]
            page.goto(url + '?view=settings')
            assert page.locator('#theme').input_value() == 'green'
            report['checks'].append('Persistence across browser restart')
            page.goto(url.replace('127.0.0.1', 'localhost') + '?view=settings')
            assert page.locator('#theme').input_value() == 'blue'
            report['checks'].append('Origin separation')
            context.close()
        report['status'] = 'PASS'
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
        (opts.output / 'workflow.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
