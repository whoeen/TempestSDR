"""Cache explicitly selected public primary sources; do not crawl private specs."""
from pathlib import Path
import concurrent.futures
import hashlib
import json
import requests
import fitz

ROOT = Path(__file__).resolve().parent
SOURCES = [
    ('st_dsi_training', 'https://www.st.com/resource/en/product_training/STM32MP1-Peripheral-DSI_HOST_interface_DSIHOST.pdf'),
    ('st_common_mode_filter', 'https://www.st.com/resource/en/datasheet/ecmf02-2amx6.pdf'),
    ('mipi_dsi_cockpit_2021', 'https://www.mipi.org/hubfs/Automotive-Workshop/How-Use-of-DSI-2-and-Video-Compression-Is-Essential-for-Next-Gen-Digital-Cockpits.pdf'),
    ('tek_dphy_tests', 'https://download.tek.com/datasheet/D-PHY-Datasheet_61W614877.pdf'),
]

def collect(item):
    source_id, url = item
    path = ROOT / 'cache' / (source_id + '.pdf')
    try:
        response = requests.get(url, timeout=(15, 75))
        response.raise_for_status()
        if not response.content.startswith(b'%PDF'):
            raise ValueError('Response is not PDF')
        path.write_bytes(response.content)
        return {'source_id': source_id, 'url': url, 'status': 'cached', 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(response.content).hexdigest()}
    except Exception as error:
        return {'source_id': source_id, 'url': url, 'status': 'failed', 'error': str(error)}

def extract():
    logs = []
    for path in sorted((ROOT / 'cache').glob('*.pdf')):
        document = fitz.open(path)
        output = ROOT / 'extracted' / (path.stem + '.pages.jsonl')
        with output.open('w', encoding='utf-8') as stream:
            for index, page in enumerate(document):
                stream.write(json.dumps({'pdf_page': index + 1, 'text': page.get_text()}, ensure_ascii=False) + '\n')
        logs.append({'file': path.name, 'total_pages': len(document), 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest(), 'extraction': str(output.relative_to(ROOT)), 'note': 'Extracted is not equivalent to read.'})
    (ROOT / 'cache_inventory.json').write_text(json.dumps(logs, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(logs, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    for directory in ('cache', 'extracted'):
        (ROOT / directory).mkdir(exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(collect, SOURCES))
    (ROOT / 'download_log.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(results, ensure_ascii=False, indent=2))
    extract()
