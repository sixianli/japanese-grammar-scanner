"""弯曲书页文字带（TextBand.swift 的 Python 版本，用于在 OCR 评测导出上离线试验和对比）。

用法：python3 tools/text_band.py <ocr-out 目录> <输出目录>   （输出目录可直接交给 scan_ux_eval.py）
"""
import json, sys, glob, math, os
import numpy as np
from PIL import Image
from shapely.geometry import Polygon, Point
sys.path.insert(0, "tools")
from scan_ux_eval import quad_of, edge_height

def wlen(s):
    return sum(0.5 if ord(c) < 0x100 or 0xFF61 <= ord(c) <= 0xFF9F else 1 for c in s)  # 和 ScanAnalyzer.weightedLength 一致

def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

def bilinear(gray, xs, ys):
    H, W = gray.shape
    xs = np.clip(xs, 0, W - 1.001); ys = np.clip(ys, 0, H - 1.001)
    x0 = xs.astype(int); y0 = ys.astype(int); fx = xs - x0; fy = ys - y0
    return (gray[y0, x0] * (1 - fx) * (1 - fy) + gray[y0, x0 + 1] * fx * (1 - fy) +
            gray[y0 + 1, x0] * (1 - fx) * fy + gray[y0 + 1, x0 + 1] * fx * fy)

PUNCT = set("、。，．・「」『』（）()〔〕［］【】…‥：；！？!?,.　 ")
def char_weight(c):
    o = ord(c)
    if c in PUNCT: return 0.1
    if c in "ーっゃゅょぁぃぅぇぉッャュョァィゥェォ": return 0.35
    if 0x3040 <= o <= 0x309F: return 0.55
    if 0x30A0 <= o <= 0x30FF: return 0.5
    if 0x4E00 <= o <= 0x9FFF or c == "々": return 1.0
    return 0.45

def expected_profile(text, N):
    ws = [0.5 if (ord(c) < 0x100 or 0xFF61 <= ord(c) <= 0xFF9F) else 1.0 for c in text]
    tot = sum(ws) or 1
    edges = np.cumsum([0] + ws) / tot
    out = np.zeros(N)
    for j in range(N):
        t = (j + .5) / N
        i = min(len(text) - 1, max(0, int(np.searchsorted(edges, t, side="right") - 1)))
        out[j] = char_weight(text[i])
    return out

ALIGN = os.environ.get("ALIGN", "1") == "1"
ALIGN_MARGIN = float(os.environ.get("ALIGN_MARGIN", "0.15"))

def line_band(gray, q, text):
    """返回 (h 像素字高, 列中心 t 数组, 每列文字带中心 f∈[0,1]) 或 None（不需要收紧）"""
    TL, TR, BR, BL = q
    L = math.dist(lerp(TL, BL, .5), lerp(TR, BR, .5))
    Hq = (math.dist(TL, BL) + math.dist(TR, BR)) / 2
    n = wlen(text)
    if n < 2 or L <= 0: return None
    h = L / n
    if Hq < 1.45 * h or L < Hq * 1.5: return None  # 已经贴字，或者是竖排 / 很短
    N = max(4, int(round(L / h)))
    M = max(8, int(round(Hq)))
    ts = (np.arange(N) + .5) / N
    ss = (np.arange(M) + .5) / M
    # 每列在 t 方向取 5 个采样点
    sub = (np.arange(5) - 2) / 5 / N
    ink = np.zeros((N, M))
    for j, t in enumerate(ts):
        tt = np.clip(t + sub, 0, 1)
        top = np.array([lerp(TL, TR, x) for x in tt]); bot = np.array([lerp(BL, BR, x) for x in tt])
        px = top[:, 0][:, None] + (bot[:, 0] - top[:, 0])[:, None] * ss[None, :]
        py = top[:, 1][:, None] + (bot[:, 1] - top[:, 1])[:, None] * ss[None, :]
        ink[j] = bilinear(gray, px.ravel(), py.ravel()).reshape(5, M).mean(0)
    bg = np.percentile(ink, 90)
    dark = np.clip(bg - ink, 0, None)
    hr = max(2, int(round(h * M / Hq)))  # 字高对应的行数
    if hr >= M: return None
    cs = np.concatenate([np.zeros((N, 1)), np.cumsum(dark, 1)], 1)
    win = cs[:, hr:] - cs[:, :-hr]  # (N, M-hr+1)
    K = win.shape[1]
    def best_path(w):
        d = max(1, int(math.ceil(DFRAC * hr)))
        unit = float(np.median(np.clip(w, 0, None).max(axis=1))) / hr if LAM > 0 else 0.0
        score = w[0].copy(); back = np.zeros((N, K), int)
        for j in range(1, N):
            new = np.full(K, -1e18); arg = np.zeros(K, int)
            for k in range(K):
                lo, hi = max(0, k - d), min(K, k + d + 1)
                cand = score[lo:hi] - LAM * unit * np.abs(np.arange(lo, hi) - k)
                i = int(np.argmax(cand)); new[k] = cand[i] + w[j, k]; arg[k] = lo + i
            score = new; back[j] = arg
        k = int(np.argmax(score)); pth = [k]
        for j in range(N - 1, 0, -1):
            k = back[j, k]; pth.append(k)
        return pth[::-1]
    path = best_path(win)
    if ALIGN:
        # 用这一行的文字内容核对：标点几乎没有墨迹、汉字墨迹多。行四边形里夹着别的行时，
        # 选「墨迹起伏和文字最吻合」的那条路径（换行必须明显更吻合才换）
        expect = expected_profile(text, N)
        def fit(pth):
            prof = np.array([win[j, pth[j]] for j in range(N)])
            if prof.std() < 1e-6 or expect.std() < 1e-6: return -1.0
            return float(np.corrcoef(prof, expect)[0, 1])
        best, best_fit = path, fit(path)
        w2 = win.copy()
        for _ in range(2):
            for j in range(N):
                lo, hi = max(0, path[j] - hr), min(K, path[j] + hr + 1)
                w2[j, lo:hi] = -1e9
            if (w2.max(axis=1) < -1e8).any(): break
            alt = best_path(w2)
            if any(w2[j, alt[j]] < -1e8 for j in range(N)): break
            fa = fit(alt)
            if fa > best_fit + ALIGN_MARGIN: best, best_fit = alt, fa
            path = alt
        path = best
    path = np.array(path, float)
    raw = (path + hr / 2) / M
    f = raw
    # 平滑
    if N >= 3:
        f = np.convolve(np.pad(f, 1, mode="edge"), [1/3, 1/3, 1/3], "valid")
    return h, ts, f, Hq, raw

JUMP = float(os.environ.get("JUMP", "0.5"))
DFRAC = float(os.environ.get("DFRAC", "0.25"))
LAM = float(os.environ.get("LAM", "1"))

def refit(box_pts, q, band):
    h, ts, f, Hq, raw = band
    TL, TR, BR, BL = q
    m0, m1 = lerp(TL, BL, .5), lerp(TR, BR, .5)
    dx, dy = m1[0] - m0[0], m1[1] - m0[1]; l2 = dx * dx + dy * dy
    def param(p): return min(max(((p[0] - m0[0]) * dx + (p[1] - m0[1]) * dy) / l2, 0), 1)
    t0 = param(lerp(box_pts[0], box_pts[3], .5)); t1 = param(lerp(box_pts[1], box_pts[2], .5))
    if t1 <= t0: return box_pts
    # 局部可信度：框所在的几列里，路径如果陡然跳动（单列移动超过 JUMP 个字高），多半跳到了别的行，保持原框
    N = len(ts)
    j0 = max(0, int(t0 * N) - 1); j1 = min(N - 1, int(math.ceil(t1 * N)) + 1)
    steps = np.abs(np.diff(raw[j0:j1 + 1])) * Hq / h if j1 > j0 else np.array([0])
    if steps.size and steps.max() > JUMP: return box_pts
    half = 0.62 * h / Hq
    out = []
    for t, side in ((t0, -1), (t1, -1), (t1, 1), (t0, 1)):
        c = float(np.interp(t, ts, f))
        T = lerp(TL, TR, t); B = lerp(BL, BR, t)
        out.append(lerp(T, B, c + side * half))
    return out

def process(path, samples):
    r = json.load(open(path)); d = r["base"]; W, H = r["width"], r["height"]
    gray = np.asarray(Image.open(os.path.join(samples, r["file"])).convert("L"), float)
    if gray.shape != (H, W): return r, d, None
    lines = []
    for ln in d["lines"]:
        qq = ln.get("quad")
        if not qq: continue
        q = [(qq[i] * W, qq[i + 1] * H) for i in range(0, 8, 2)]
        p = Polygon(q); p = p if p.is_valid else p.buffer(0)
        lines.append((q, p, ln["text"]))
    bands = {}
    work = gray.copy()
    bgv = float(np.percentile(gray, 90))
    def ratio(i):
        q, lp, t = lines[i]
        L = math.dist(lerp(q[0], q[3], .5), lerp(q[1], q[2], .5)); Hq = (math.dist(q[0], q[3]) + math.dist(q[1], q[2])) / 2
        return Hq / max(L / max(wlen(t), 1), 1)
    from PIL import ImageDraw
    for i in sorted(range(len(lines)), key=ratio):
        bd = line_band(work, lines[i][0], lines[i][2])
        bands[i] = bd
        q = lines[i][0]
        if bd is None:
            poly = q
        else:
            h, ts, f, Hq, raw = bd
            half = 0.55 * h / Hq
            topp = [lerp(lerp(q[0], q[1], t), lerp(q[3], q[2], t), c - half) for t, c in zip([0] + list(ts) + [1], [f[0]] + list(f) + [f[-1]])]
            botp = [lerp(lerp(q[0], q[1], t), lerp(q[3], q[2], t), c + half) for t, c in zip([0] + list(ts) + [1], [f[0]] + list(f) + [f[-1]])]
            poly = topp + botp[::-1]
        m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in poly], fill=255)
        work[np.asarray(m) > 0] = bgv
    newboxes = []
    for b in d["boxes"]:
        pts = quad_of(b, W, H)
        c = Polygon(pts).centroid
        segs = [x.replace("\n", "") for x in next((cc["segments"] for cc in d["clusters"] if cc["id"] == b["cluster"]), [])]
        def has_text(t):
            return any(sg and (sg in t or any(sg[k:k + 2] in t for k in range(max(1, len(sg) - 1)))) for sg in segs)
        cands = [(0 if has_text(t) else 1, lp.distance(c), lp.area, i) for i, (q, lp, t) in enumerate(lines) if lp.buffer(2).contains(c)]
        if not cands: newboxes.append(b); continue
        i = min(cands)[3]
        bd = bands[i]
        if bd is None: newboxes.append(b); continue
        np_ = refit(pts, lines[i][0], bd)
        nb = dict(b); nb["quad"] = [v for x, y in np_ for v in (x / W, y / H)]
        newboxes.append(nb)
    return r, d, newboxes

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for f in sorted(glob.glob(src + "/*.json")):
        r, d, nb = process(f, "tests/ocr/samples")
        if nb is not None: d["boxes"] = nb
        json.dump(r, open(os.path.join(dst, os.path.basename(f)), "w"), ensure_ascii=False)
