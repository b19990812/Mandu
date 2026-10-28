"""Encode project-generated row-marker fixtures using the installed Pillow tool.

Pillow is a development tool only. No third-party image or decoder code is packaged.
"""
import io
import hashlib
import json
from pathlib import Path
from PIL import Image
from png_image import make_png

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'entry/src/main/resources/rawfile/image-matrix'
Image.MAX_IMAGE_PIXELS = 134217728

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    specifications = [('ordinary', 640, 1024, ('PNG', 'JPEG', 'WEBP')),
                      ('long_1080', 1080, 30000, ('PNG', 'JPEG')),
                      ('long_webp', 1080, 15000, ('WEBP',)),
                      ('long_2160', 2160, 60000, ('PNG', 'JPEG'))]
    for name, width, height, formats in specifications:
        png = make_png(width, height, 0)
        for fmt in formats:
            extension = {'PNG': 'png', 'JPEG': 'jpg', 'WEBP': 'webp'}[fmt]
            filename = name + '.' + extension
            if fmt == 'PNG':
                encoded = png
            else:
                with Image.open(io.BytesIO(png)) as source:
                    buffer = io.BytesIO()
                    source.save(buffer, fmt, quality=90)
                    encoded = buffer.getvalue()
            (OUTPUT / filename).write_bytes(encoded)
            records.append({'file': filename, 'width': width, 'height': height, 'bytes': len(encoded), 'format': fmt, 'sha256': hashlib.sha256(encoded).hexdigest()})
    (OUTPUT / 'index.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(records))

if __name__ == '__main__': main()
