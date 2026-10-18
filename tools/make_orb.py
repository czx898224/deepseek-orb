# -*- coding: utf-8 -*-
"""生成通体蓝色的悬浮球 PNG（透明背景、抗锯齿、柔和投影）。"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 320                      # 画布
BALL_D = 232                 # 球直径占画布比例 -> 运行时按该比例反推窗口尺寸
C = S / 2.0
R = BALL_D / 2.0

yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
dx, dy = xx - C, yy - C
dist = np.sqrt(dx * dx + dy * dy)

# ---------- 球体主体：径向渐变 ----------
# 光源偏左上
lx, ly = C - R * 0.36, C - R * 0.40
ld = np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2)
t = np.clip(ld / (R * 1.62), 0, 1) ** 0.9

c_hi = np.array([0x9A, 0xC8, 0xFF], dtype=np.float32)   # 高光蓝
c_mid = np.array([0x3D, 0x84, 0xF6], dtype=np.float32)  # 主蓝
c_low = np.array([0x1A, 0x46, 0xC8], dtype=np.float32)  # 暗部蓝

ramp = np.zeros((S, S, 3), dtype=np.float32)
m1 = t < 0.45
ramp[m1] = (c_hi + (c_mid - c_hi) * (t[m1] / 0.45)[:, None])
m2 = ~m1
ramp[m2] = (c_mid + (c_low - c_mid) * ((t[m2] - 0.45) / 0.55)[:, None])

# ---------- 边缘暗角（让球有体积感） ----------
edge = np.clip((dist - R * 0.72) / (R * 0.28), 0, 1)
shade = (1.0 - 0.30 * edge ** 1.7)[:, :, None]
ramp = ramp * shade

# ---------- 右下环境反光 ----------
rim = np.clip(1 - np.abs(dist - R * 0.96) / (R * 0.10), 0, 1)
lowlight = rim * np.clip((dy / R) - 0.15, 0, 1) / 0.85
ramp += np.array([0x5A, 0x9E, 0xFF], dtype=np.float32) * (0.55 * lowlight)[:, :, None]

rgb = np.clip(ramp, 0, 255)

# ---------- 球体 alpha（1px 抗锯齿） ----------
aa = np.clip((R - dist) / 1.0 + 0.5, 0, 1)
alpha = (aa * 255).astype(np.uint8)

ball = np.dstack([rgb, alpha]).astype(np.uint8)
ball_img = Image.fromarray(ball, "RGBA")

# ---------- 镜面高光 ----------
hi = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(hi)
hw, hh = R * 0.46, R * 0.34
hx, hy = C - R * 0.30, C - R * 0.40
d.ellipse([hx - hw, hy - hh, hx + hw, hy + hh], fill=170)
hi = hi.filter(ImageFilter.GaussianBlur(R * 0.14))
white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
white.putalpha(hi.point(lambda v: int(v * 0.78)))
ball_img = Image.alpha_composite(ball_img, white)

# ---------- 顶部细边高光（勾一圈亮边） ----------
ring = Image.new("L", (S, S), 0)
d2 = ImageDraw.Draw(ring)
d2.ellipse([C - R + 1.5, C - R + 1.5, C + R - 1.5, C + R - 1.5], outline=200, width=2)
ring = ring.filter(ImageFilter.GaussianBlur(1.6))
ring = np.asarray(ring).astype(np.float32)
fall = np.clip((-dy / R) * 1.2 + 0.25, 0, 1)          # 只留上半圈
ring = (ring * fall * 0.55).astype(np.uint8)
ring_img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
ring_img.putalpha(Image.fromarray(ring, "L"))
ball_img = Image.alpha_composite(ball_img, ring_img)

# ---------- 投影 ----------
sh = Image.new("L", (S, S), 0)
d3 = ImageDraw.Draw(sh)
pad = R * 0.06
d3.ellipse([C - R + pad, C - R + pad + R * 0.10,
            C + R - pad, C + R - pad + R * 0.10], fill=95)
sh = sh.filter(ImageFilter.GaussianBlur(R * 0.13))
shadow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 255))
# 深蓝黑投影，略微偏冷
shadow_layer = Image.new("RGBA", (S, S), (12, 26, 60, 255))
shadow_layer.putalpha(sh)

out = Image.alpha_composite(shadow_layer, ball_img)

dst = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
os.makedirs(dst, exist_ok=True)
p = os.path.join(dst, "orb.png")
out.save(p, "PNG")
print("saved", p, out.size)
print("ball fraction of canvas: %.4f" % (BALL_D / float(S)))
