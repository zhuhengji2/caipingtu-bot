# -*- coding: utf-8 -*-
"""8线程断点续传下载器"""
import os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

URL = "https://hf-mirror.com/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "lama_fp32.onnx")
TOTAL = 208044816
PARTS = 8


def part_path(i):
    return OUT + f".part{i}"


def expected(i):
    per = TOTAL // PARTS
    s = i * per
    e = TOTAL - 1 if i == PARTS - 1 else (i + 1) * per - 1
    return s, e, e - s + 1


def download_part(i):
    s, e, size = expected(i)
    for attempt in range(200):
        cur = os.path.getsize(part_path(i)) if os.path.exists(part_path(i)) else 0
        if cur >= size:
            return True
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={s + cur}-{e}"})
            with urllib.request.urlopen(req, timeout=60) as r, open(part_path(i), "ab") as f:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    f.write(chunk)
        except Exception as ex:
            print(f"part{i} retry@{os.path.getsize(part_path(i)) if os.path.exists(part_path(i)) else 0}: {ex}", flush=True)
            time.sleep(2)
    return os.path.getsize(part_path(i)) >= size


def main():
    # 校验已有分片
    with ThreadPoolExecutor(PARTS) as ex:
        results = list(ex.map(download_part, range(PARTS)))
    if not all(results):
        print("FAILED", results)
        sys.exit(1)
    with open(OUT, "wb") as out:
        for i in range(PARTS):
            with open(part_path(i), "rb") as f:
                while True:
                    chunk = f.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)
    assert os.path.getsize(OUT) == TOTAL, os.path.getsize(OUT)
    for i in range(PARTS):
        os.remove(part_path(i))
    print("DONE", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
