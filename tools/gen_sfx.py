#!/usr/bin/env python3
"""Generates the placeholder sound effects into assets/audio/. Pure stdlib; rerun to tweak."""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(7)


def save(name, samples, gain=0.6):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * gain * 32767)) for s in samples))


def env(i, n, attack=0.01, power=2.0):
    t = i / n
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - t) ** power


def tone(f0, f1, dur, shape="sine", power=2.0):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        phase += 2 * math.pi * f / SR
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        elif shape == "saw":
            v = ((phase / (2 * math.pi)) % 1.0) * 2 - 1
        else:  # triangle
            v = 2 * abs(((phase / (2 * math.pi)) % 1.0) * 2 - 1) - 1
        out.append(v * env(i, n, power=power))
    return out


def noise(dur, cut0, cut1, power=2.0, attack=0.01):
    n = int(SR * dur)
    out, lp = [], 0.0
    for i in range(n):
        k = cut0 + (cut1 - cut0) * i / n
        lp += k * (random.uniform(-1, 1) - lp)
        out.append(lp * env(i, n, attack, power))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0.0 for t in tracks) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


save("slash", mix(noise(0.14, 0.6, 0.15, 2.0, 0.02), tone(700, 250, 0.12, "saw", 3.0)), 0.5)
save("dash", noise(0.2, 0.08, 0.7, 1.5, 0.35), 0.5)
save("spin", mix(noise(0.4, 0.1, 0.4, 1.0, 0.2), tone(260, 520, 0.4, "triangle", 1.0)), 0.5)
save("slam", mix(tone(140, 35, 0.4, "sine", 2.0), noise(0.25, 0.5, 0.05, 3.0, 0.0)), 0.8)
save("enemy_hit", tone(260, 140, 0.07, "square", 2.0), 0.35)
save("enemy_death", mix(tone(420, 90, 0.18, "saw", 2.0), noise(0.15, 0.4, 0.1, 2.0)), 0.5)
save("xp_pickup", tone(900, 1500, 0.08, "sine", 1.5), 0.35)
save("level_up", seq(*[tone(f, f, 0.09, "triangle", 1.2) for f in (523, 659, 784, 1047)]), 0.6)
save("player_hurt", tone(220, 90, 0.2, "saw", 1.5), 0.6)
save("player_death", mix(tone(300, 40, 0.7, "saw", 1.5), noise(0.5, 0.3, 0.03, 1.5)), 0.7)
save("no_mana", seq(tone(150, 150, 0.05, "square", 1.0), [0.0] * int(SR * 0.03), tone(110, 110, 0.07, "square", 1.0)), 0.4)
save("menu_click", tone(700, 600, 0.04, "sine", 1.5), 0.4)
save("dasher_charge", mix(tone(90, 260, 1.0, "saw", 0.5), noise(1.0, 0.05, 0.3, 0.6, 0.3)), 0.45)
save("dasher_dash", mix(noise(0.35, 0.7, 0.05, 1.2, 0.05), tone(180, 60, 0.3, "saw", 1.5)), 0.7)
save("ranged_windup", tone(300, 700, 0.4, "triangle", 0.4), 0.35)
save("ranged_shot", mix(tone(900, 200, 0.12, "square", 2.5), noise(0.08, 0.7, 0.2, 2.0)), 0.45)
save("projectile_hit", mix(tone(180, 60, 0.12, "sine", 2.0), noise(0.08, 0.4, 0.1, 3.0)), 0.55)
save("bolt_fire", mix(tone(700, 1500, 0.09, "sine", 2.0), noise(0.05, 0.8, 0.3, 2.0)), 0.4)
save("bolt_hit", mix(tone(520, 220, 0.07, "square", 2.5), noise(0.04, 0.6, 0.2, 2.0)), 0.4)
save("phase", mix(tone(220, 520, 0.35, "sine", 0.6), tone(330, 780, 0.35, "triangle", 0.8), noise(0.3, 0.1, 0.5, 1.0, 0.3)), 0.45)
save("lightning", seq(noise(0.04, 0.9, 0.6, 1.0, 0.0), [0.0] * int(SR * 0.015), noise(0.05, 0.9, 0.4, 1.5, 0.0), [0.0] * int(SR * 0.01), mix(noise(0.12, 0.8, 0.2, 2.0, 0.0), tone(1800, 600, 0.12, "saw", 2.0))), 0.55)
save("meteor_fall", mix(tone(1400, 140, 0.7, "sine", 0.8), noise(0.7, 0.05, 0.4, 0.8, 0.2)), 0.4)
save("meteor_impact", mix(tone(110, 28, 0.6, "sine", 1.6), noise(0.45, 0.6, 0.04, 2.5, 0.0)), 0.9)
save("focus_on", seq(tone(880, 880, 0.07, "triangle", 1.0), tone(1320, 1320, 0.12, "triangle", 1.6)), 0.4)
save("hub_focus", tone(1100, 1000, 0.03, "sine", 1.5), 0.25)
save("hub_choose", seq(tone(660, 660, 0.08, "triangle", 1.2), tone(990, 990, 0.18, "triangle", 1.6)), 0.5)
save("door_open", mix(tone(90, 180, 0.5, "saw", 0.7), noise(0.5, 0.05, 0.25, 0.8, 0.3)), 0.45)
save("door_enter", mix(tone(500, 120, 0.3, "sine", 1.2), noise(0.25, 0.4, 0.05, 1.5, 0.05)), 0.5)
print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))
