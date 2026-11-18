"""解码 DST 的 KTEX(BC3/DXT5) 贴图为 PNG，用于从原版图集裁取图标。"""
import struct
import sys
from PIL import Image


def decode_dxt5(data, width, height):
    """返回 RGBA bytes。"""
    out = bytearray(width * height * 4)
    bw = width // 4
    bh = height // 4
    pos = 0
    for by in range(bh):
        for bx in range(bw):
            a0, a1 = data[pos], data[pos + 1]
            abits = int.from_bytes(data[pos + 2:pos + 8], "little")
            pal_a = [a0, a1] + [0] * 6
            if a0 > a1:
                for i in range(2, 8):
                    pal_a[i] = ((7 - i) * a0 + (i - 1) * a1) // 7
            else:
                for i in range(2, 6):
                    pal_a[i] = ((5 - i) * a0 + (i - 1) * a1) // 5
                pal_a[6], pal_a[7] = 0, 255
            pos += 8

            c0, c1 = struct.unpack_from("<HH", data, pos)
            cbits = struct.unpack_from("<I", data, pos + 4)[0]
            pos += 8

            def rgb(c):
                r = (c >> 11) & 0x1F
                g = (c >> 5) & 0x3F
                b = c & 0x1F
                return (
                    (r << 3) | (r >> 2),
                    (g << 2) | (g >> 4),
                    (b << 3) | (b >> 2),
                )

            p0, p1 = rgb(c0), rgb(c1)
            pal_c = [p0, p1]
            if c0 > c1:
                pal_c.append(tuple((2 * p0[i] + p1[i]) // 3 for i in range(3)))
                pal_c.append(tuple((p0[i] + 2 * p1[i]) // 3 for i in range(3)))
            else:
                pal_c.append(tuple((p0[i] + p1[i]) // 2 for i in range(3)))
                pal_c.append((0, 0, 0))

            base = (by * 4 * width + bx * 4) * 4
            for py in range(4):
                for px in range(4):
                    idx = py * 4 + px
                    ai = (abits >> (3 * idx)) & 0x7
                    ci = (cbits >> (2 * idx)) & 0x3
                    r, g, b = pal_c[ci]
                    a = pal_a[ai]
                    o = base + (py * width + px) * 4
                    out[o:o + 4] = bytes((r, g, b, a))
    return bytes(out)


def _mip_chain_bytes(width, height):
    """BC3(1 字节/像素) 全 mip 链的字节数，每个 mip 按 16 字节对齐。"""
    total = 0
    w, h = width, height
    while True:
        size = max(1, w) * max(1, h)
        total += (size + 15) // 16 * 16
        if w == 1 and h == 1:
            break
        w, h = max(1, w // 2), max(1, h // 2)
    return total


def ktex_to_image(path):
    with open(path, "rb") as f:
        raw = f.read()
    assert raw[:4] == b"KTEX", "not a KTEX file"

    # 头部长度随 mip 数变化（游戏大图集 128，mod 小图标 78），用文件长度反推更稳
    width, height = struct.unpack_from("<HH", raw, 8)
    if width == 0 or height == 0 or width > 8192:
        raise RuntimeError("unexpected dimensions %dx%d" % (width, height))

    header = len(raw) - _mip_chain_bytes(width, height)
    if not (64 <= header <= 512):
        raise RuntimeError("无法识别的 KTEX 头部长度: %d" % header)

    data = raw[header:]
    return Image.frombytes("RGBA", (width, height), decode_dxt5(data, width, height))


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    img = ktex_to_image(src)
    img.save(dst)
    print("saved", dst, img.size, img.mode)
