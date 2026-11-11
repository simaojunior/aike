"""Bounded local OCR extraction; no document text is logged or persisted."""
import csv
import glob
import io
import json
import os
import statistics
import subprocess
import sys
import warnings
from collections import deque

try:
    from PIL import Image, ImageFilter, ImageOps
except ImportError:
    sys.exit(3)

Image.MAX_IMAGE_PIXELS = 20_000_000
warnings.simplefilter('error', Image.DecompressionBombWarning)

OCR_SIZE = 2400
MAX_UPSCALE = 3
MIN_IMAGE_SIDE = 200
MAX_IMAGES = 3
TIMEOUT = 4
ORIENTATION_SIZE = 1200
ROTATIONS = (0, 90, 180, 270)
DETECTION_SIZE = 320
MIN_LEGIBLE_WORDS = 3
PAPER_COLOR_DISTANCE = 45
DENSE_FRACTION = 0.4
REGION_PADDING = 0.07
MIN_REGION_AREA = 0.05
MIN_DOCUMENT_SIDE = 320


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
    # Do not silently classify the first page of a mixed document bundle.
    if pdf_page_count(source) != 1:
        raise ValueError('unsupported page count')
    text_layer = run(['pdftotext', '-f', '1', '-l', '1', source, '-']).decode('utf-8', errors='replace')
    prefix = os.path.join(directory, 'page')
    run(['pdftoppm', '-f', '1', '-l', '1', '-singlefile', '-scale-to', str(OCR_SIZE), '-png', source, prefix])
    return text_layer, [prefix + '.png', *embedded_images(source, directory)]


def load(path):
    with Image.open(path) as image:
        if image.format not in ('JPEG', 'PNG') or getattr(image, 'n_frames', 1) != 1:
            raise ValueError('unsupported image')
        colored = image.mode not in ('1', 'L', 'LA', 'I', 'I;16')
        return ImageOps.exif_transpose(image).convert('RGB'), colored


def orient(image, directory):
    """Return the upright image and the boxes of its legible words."""
    best = None
    for angle in ROTATIONS:
        rotated = image.rotate(angle, expand=True)
        sample = rotated.convert('L')
        sample.thumbnail((ORIENTATION_SIZE, ORIENTATION_SIZE))
        scale = sample.width / rotated.width
        path = os.path.join(directory, 'orientation.png')
        sample.save(path)
        legible = [tuple(edge / scale for edge in box)
                   for text, conf, box in ocr_words(path, '3') if conf >= 80 and len(text) >= 4]
        if best is None or len(legible) > len(best[1]):
            best = (rotated, legible)
    return best


def document_region(image, legible):
    """Find the document around its legible text so the background does not count as text."""
    if len(legible) < MIN_LEGIBLE_WORDS:
        return None
    sample = image.copy()
    sample.thumbnail((DETECTION_SIZE, DETECTION_SIZE))
    scale = sample.width / image.width
    width, height = sample.size
    pixels = sample.load()
    seed = [round(edge * scale) for edge in (min(b[0] for b in legible), min(b[1] for b in legible),
                                             max(b[2] for b in legible), max(b[3] for b in legible))]
    seed = [max(0, seed[0]), max(0, seed[1]), min(width, seed[2]), min(height, seed[3])]
    inside = [pixels[x, y] for y in range(seed[1], seed[3]) for x in range(seed[0], seed[2])]
    if not inside:
        return None
    paper = [statistics.median(pixel[channel] for pixel in inside) for channel in range(3)]

    mask = Image.new('L', sample.size)
    marks = mask.load()
    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            distance = sum((pixel[c] - paper[c]) ** 2 for c in range(3)) ** 0.5
            marks[x, y] = 255 if distance < PAPER_COLOR_DISTANCE else 0
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    marks = mask.load()

    region = {(x, y) for y in range(seed[1], seed[3]) for x in range(seed[0], seed[2]) if marks[x, y]}
    queue = deque(region)
    while queue:
        x, y = queue.popleft()
        for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= neighbor[0] < width and 0 <= neighbor[1] < height and neighbor not in region and marks[neighbor]:
                region.add(neighbor)
                queue.append(neighbor)

    rows = [0] * height
    for _, y in region:
        rows[y] += 1
    top, bottom = dense_run(rows, seed[1], seed[3])
    columns = [0] * width
    for x, y in region:
        if top <= y < bottom:
            columns[x] += 1
    left, right = dense_run(columns, seed[0], seed[2])

    pad_x, pad_y = (right - left) * REGION_PADDING, (bottom - top) * REGION_PADDING
    box = (max(0, (left - pad_x) / scale), max(0, (top - pad_y) / scale),
           min(image.width, (right + pad_x) / scale), min(image.height, (bottom + pad_y) / scale))
    if (box[2] - box[0]) * (box[3] - box[1]) < MIN_REGION_AREA * image.width * image.height:
        return None
    return box


def dense_run(counts, start, end):
    limit = max(counts) * DENSE_FRACTION
    while start > 0 and counts[start - 1] >= limit:
        start -= 1
    while end < len(counts) and counts[end] >= limit:
        end += 1
    return start, end


def variants(image, colored):
    factor = min(MAX_UPSCALE, OCR_SIZE / max(image.size))
    if factor > 1:
        image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
    image.thumbnail((OCR_SIZE, OCR_SIZE))
    yield image.convert('L')
    if colored:
        yield image.getchannel('B')


def ocr_words(prepared, psm='11'):
    output = run(['tesseract', prepared, 'stdout', '-l', 'por', '--psm', psm, 'tsv'])
    rows = csv.DictReader(io.StringIO(output.decode('utf-8')), delimiter='\t', quoting=csv.QUOTE_NONE)
    return [(row['text'], float(row['conf']),
             (int(row['left']), int(row['top']), int(row['left']) + int(row['width']), int(row['top']) + int(row['height'])))
            for row in rows if row.get('text', '').strip() and float(row['conf']) >= 0]


def prepare_photo(path, directory):
    image, colored = load(path)
    image, legible = orient(image, directory)
    region = document_region(image, legible)
    if region is None:
        return image, colored, ['document_not_detected']
    image = image.crop(region)
    return image, colored, ['low_resolution'] if min(image.size) < MIN_DOCUMENT_SIDE else []


def extract(source, directory):
    with open(source, 'rb') as stream:
        signature = stream.read(8)
    if signature.startswith(b'%PDF-'):
        text_layer, paths = pdf_sources(source, directory)
        images = [(load(path)[0], False) for path in paths]
        issues = []
    else:
        image, colored, issues = prepare_photo(source, directory)
        text_layer, images = '', [(image, colored)]
    words = []
    index = 0
    for image, colored in images:
        for variant in variants(image, colored):
            prepared = os.path.join(directory, f'prepared-{index}.png')
            variant.save(prepared)
            words.extend(ocr_words(prepared))
            index += 1
    confidence = statistics.median(conf for _, conf, _ in words) if words else 0
    return {'text': ' '.join([text_layer, *(text for text, _, _ in words)]), 'confidence': confidence, 'issues': issues}


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
