"""Original, deterministic RGB PNG fixtures; Python standard library only."""
import struct
import zlib


GLYPHS = (
    ("111", "101", "101", "101", "111"),
    ("010", "110", "010", "010", "111"),
    ("111", "001", "111", "100", "111"),
    ("111", "001", "111", "001", "111"),
    ("101", "101", "111", "001", "001"),
    ("111", "100", "111", "001", "111"),
    ("111", "100", "111", "101", "111"),
    ("111", "001", "010", "010", "010"),
    ("111", "101", "111", "101", "111"),
    ("111", "101", "111", "001", "111"),
)


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def make_png(width: int, height: int, variant: int = 0) -> bytes:
    """Compress one row at a time, with row-number markers every 256 pixels."""
    if not (1 <= width <= 2160 and 1 <= height <= 60000):
        raise ValueError('fixture dimensions out of range')
    compressor = zlib.compressobj(6)
    encoded = []
    for y in range(height):
        stripe = (y // 128 + variant) % 2
        row = bytearray(bytes((235 - stripe * 24, 245 - stripe * 18, 240 - stripe * 8)) * width)
        local_y = y % 256
        if local_y < 6:
            row[:] = bytes((37, 78, 80)) * width
        if 24 <= local_y < 64:
            digit_y = (local_y - 24) // 8
            label = str(y // 256 * 256)
            for position, digit in enumerate(label):
                for column, bit in enumerate(GLYPHS[int(digit)][digit_y]):
                    if bit == '1':
                        start = 24 + position * 32 + column * 8
                        for x in range(start, min(start + 8, width)):
                            row[x * 3:x * 3 + 3] = bytes((25, 45, 47))
        data = compressor.compress(b'\x00' + row)
        if data:
            encoded.append(data)
    encoded.append(compressor.flush())
    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', b''.join(encoded)) + chunk(b'IEND', b'')
