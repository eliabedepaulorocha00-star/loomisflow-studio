#!/usr/bin/env python3
"""Aplica permissões de câmera/galeria nas pastas android/ e ios/ geradas pelo
`flutter create`. Idempotente: pode rodar várias vezes."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent

# ---------------- Android ----------------
manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    txt = manifest.read_text(encoding="utf-8")
    if "android.permission.CAMERA" not in txt:
        add = (
            '    <uses-permission android:name="android.permission.CAMERA"/>\n'
            '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
        )
        txt = txt.replace("<application", add + "    <application", 1)
        manifest.write_text(txt, encoding="utf-8")
        print("Android: permissão de câmera adicionada")
else:
    print("AVISO: AndroidManifest.xml não encontrado", file=sys.stderr)

# ---------------- iOS ----------------
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    txt = plist.read_text(encoding="utf-8")
    keys = {
        "NSCameraUsageDescription":
            "Usamos a câmera para fotografar referências e projetar a guia sobre o seu caderno.",
        "NSPhotoLibraryUsageDescription":
            "Escolha fotos de retrato para gerar o passo a passo Loomis.",
    }
    block = ""
    for k, v in keys.items():
        if k not in txt:
            block += f"\t<key>{k}</key>\n\t<string>{v}</string>\n"
    if block:
        idx = txt.rfind("</dict>")
        txt = txt[:idx] + block + txt[idx:]
        plist.write_text(txt, encoding="utf-8")
        print("iOS: descrições de uso adicionadas")
else:
    print("AVISO: Info.plist não encontrado", file=sys.stderr)

podfile = root / "ios/Podfile"
if podfile.exists():
    txt = podfile.read_text(encoding="utf-8")
    new = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.5'", txt, count=1, flags=re.M)
    if new != txt:
        podfile.write_text(new, encoding="utf-8")
        print("iOS: plataforma mínima 15.5 (exigida pelo ML Kit)")
