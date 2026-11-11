"""Bounded local OCR that returns text lines with geometry; no document text is logged or persisted."""
import csv
import glob
import io
import json
import os
import subprocess
import sys
import warnings

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit(3)

Image.MAX_IMAGE_PIXELS = 20_000_000
warnings.simplefilter('error', Image.DecompressionBombWarning)

OCR_SIZE = 2400
TARGET_SIZE = 2000
MAX_UPSCALE = 4
MIN_IMAGE_SIDE = 200
MAX_IMAGES = 3
TIMEOUT = 4


def run(args):
    return subprocess.run(args, check=True, capture_output=True, timeout=TIMEOUT).stdout


def pdf_page_count(source):
    info = run(['pdfinfo', source]).decode('utf-8', errors='replace')
    return next(int(line.split(':', 1)[1]) for line in info.splitlines() if line.startswith('Pages:'))


def embedded_images(source, directory):
    prefix = os.path.join(directory, 'embedded')
    run(['pdfimages', '-f', '1', '-l', '1', '-png', source, prefix])
    candidates = []
    for path in glob.glob(prefix + '-*.png'):
        with Image.open(path) as image:
            if image.mode != '1' and min(image.size) >= MIN_IMAGE_SIDE:
                candidates.append((image.width * image.height, path))
    return [path for _, path in sorted(candidates, reverse=True)[:MAX_IMAGES]]


def pdf_sources(source, directory):
    if pdf_page_count(source) != 1:
        raise ValueError('unsupported page count')
    images = embedded_images(source, directory)
    if images:
        return images
    prefix = os.path.join(directory, 'page')
    run(['pdftoppm', '-f', '1', '-l', '1', '-singlefile', '-scale-to', str(OCR_SIZE), '-png', source, prefix])
    return [prefix + '.png']


def variants(path):
    with Image.open(path) as image:
        if image.format not in ('JPEG', 'PNG') or getattr(image, 'n_frames', 1) != 1:
            raise ValueError('unsupported image')
        colored = image.mode not in ('1', 'L', 'LA', 'I', 'I;16')
        image = ImageOps.exif_transpose(image).convert('RGB')
    factor = min(MAX_UPSCALE, TARGET_SIZE / max(image.size))
    if factor > 1:
        image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
    image.thumbnail((OCR_SIZE, OCR_SIZE))
    yield image.convert('L')
    if colored:
        yield image.getchannel('B')


def ocr_lines(prepared):
    output = run(['tesseract', prepared, 'stdout', '-l', 'por', '--psm', '4', 'tsv'])
    rows = csv.DictReader(io.StringIO(output.decode('utf-8')), delimiter='\t', quoting=csv.QUOTE_NONE)
    lines = {}
    for row in rows:
        if not row.get('text', '').strip() or float(row['conf']) < 0:
            continue
        key = (row['block_num'], row['par_num'], row['line_num'])
        lines.setdefault(key, []).append(row)
    return [line(words) for words in lines.values()]


def line(words):
    left = min(int(word['left']) for word in words)
    top = min(int(word['top']) for word in words)
    right = max(int(word['left']) + int(word['width']) for word in words)
    bottom = max(int(word['top']) + int(word['height']) for word in words)
    return {
        'text': ' '.join(word['text'] for word in words),
        'confidence': round(sum(float(word['conf']) for word in words) / len(words) / 100, 4),
        'bbox': [left, top, right - left, bottom - top],
    }


def extract(source, directory):
    with open(source, 'rb') as stream:
        signature = stream.read(8)
    paths = pdf_sources(source, directory) if signature.startswith(b'%PDF-') else [source]
    lines = []
    index = 0
    for path in paths:
        for image in variants(path):
            prepared = os.path.join(directory, f'prepared-{index}.png')
            image.save(prepared)
            lines.extend({**entry, 'source': index} for entry in ocr_lines(prepared))
            index += 1
    return {'text': lines}


try:
    print(json.dumps(extract(sys.argv[1], sys.argv[2])))
except (ValueError, StopIteration, Image.UnidentifiedImageError, Image.DecompressionBombError, Image.DecompressionBombWarning):
    sys.exit(2)
except FileNotFoundError:
    sys.exit(3)
except subprocess.TimeoutExpired:
    sys.exit(4)
except subprocess.CalledProcessError:
    sys.exit(5)
except (OSError, subprocess.SubprocessError):
    sys.exit(1)
