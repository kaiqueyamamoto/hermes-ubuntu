"""Exemplo Playwright (Python): abre uma página e imprime o título.

    python3 /opt/hermes-examples/playwright_exemplo.py [url]
    xvfb-run -a python3 /opt/hermes-examples/playwright_exemplo.py --headed
"""
import sys

from playwright.sync_api import sync_playwright


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    url = args[0] if args else "https://example.com"
    headed = "--headed" in sys.argv
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not headed)
        page = browser.new_page()
        page.goto(url)
        print(page.title())
        browser.close()


if __name__ == "__main__":
    main()
