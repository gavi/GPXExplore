#!/usr/bin/env python3
"""Builds the GPXExplore.butterkit package from the captured screenshots.

    python3 AppStore/make-butterkit.py [--shots AppStore/screenshots] [--out "<iCloud ButterKit dir>"] [--lang de]

Reads AppStore/screenshots/{iphone-6.9,ipad-13,mac}/<scene>.png (written by AppStore/shots.sh)
and writes a ButterKit document with one artboard per scene for each size class. Re-running
replaces the package, so edit the SCENES table below rather than the artboards in ButterKit if
you want the changes to survive a recapture. Quit ButterKit before running: it caches the
document and assets while the package is open.

Publishing the boards from ButterKit and uploading them to App Store Connect is Gavi's step.
"""

import argparse
import json
import os
import shutil
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SHOTS = os.path.join(HERE, "screenshots")
DEFAULT_OUT = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/ButterKit")

# (screenshot basename, caption). The first entry becomes the hero artboard with a title and
# subtitle instead of a caption. The App Store takes at most 10 per size.
SCENES = [
    ("01-hero", None),
    ("02-heart-rate", "Heart rate, power, cadence, speed"),
    ("03-satellite", "See the climb before you ride it"),
    ("06-speed", "Moving time, pace and splits"),
    ("04-tracks", "Every track, segment and waypoint"),
    ("05-gradient", "Colour by grade or by elevation"),
]

HERO_TITLE = "GPX Explore"
HERO_SUBTITLE = "Open a GPX file. See the whole ride."

# Captions per language for --lang; the captures come from `UI_LANG=<lang> shots.sh` into
# screenshots/<lang>/ and the package is written as GPXExplore-<lang>.butterkit, one per
# language, so ButterKit publishes each set for its App Store localisation.
CAPTIONS = {
    "de": {
        "subtitle": "GPX-Datei öffnen. Die ganze Tour sehen.",
        "02-heart-rate": "Herzfrequenz, Leistung, Trittfrequenz, Tempo",
        "03-satellite": "Sieh den Anstieg, bevor du ihn fährst",
        "06-speed": "Bewegungszeit, Tempo und Splits",
        "04-tracks": "Jeder Track, jedes Segment, jeder Wegpunkt",
        "05-gradient": "Farbe nach Steigung oder nach Höhe",
    },
    "fr": {
        "subtitle": "Ouvrez un GPX. Voyez toute la sortie.",
        "02-heart-rate": "Cardio, puissance, cadence, vitesse",
        "03-satellite": "Voyez la pente avant de la rouler",
        "06-speed": "Temps en mouvement, allure, intermédiaires",
        "04-tracks": "Chaque trace, segment et point d'intérêt",
        "05-gradient": "Couleur selon la pente ou l'altitude",
    },
    "es": {
        "subtitle": "Abre un GPX. Mira la salida entera.",
        "02-heart-rate": "Pulso, potencia, cadencia, velocidad",
        "03-satellite": "Mira la subida antes de hacerla",
        "06-speed": "Tiempo en movimiento, ritmo y parciales",
        "04-tracks": "Cada track, segmento y waypoint",
        "05-gradient": "Color por pendiente o por altitud",
    },
    "ja": {
        "subtitle": "GPXを開く。走った全部が見える。",
        "02-heart-rate": "心拍・パワー・ケイデンス・速度",
        "03-satellite": "走る前に登りが見える",
        "06-speed": "移動時間・ペース・スプリット",
        "04-tracks": "トラック、セグメント、ウェイポイント",
        "05-gradient": "勾配または標高で色分け",
    },
}

BACKGROUND = {"image": {"fill": "fill", "ref": {"name": "preset-bg-5", "type": "bundle"}}}

# Geometry copied from ButterKit-authored documents (WorkoutGPX for the phone and tablet
# boards, GeoMeasure for the Mac board): artboard size, camera and column spacing per preset.
PRESETS = {
    "iphone": {
        "folder": "iphone-6.9",
        "sizePresetID": "app_store_iphone",
        "size": [1.6125, 3.495],
        "y": 0.0,
        "spacing": 1.7328,
        "model": {"assetName": "iPhone17ProMax", "instanceLabel": "iPhone16",
                  "rotationEuler": [0, 0, 0], "scale": [1, 1, 1], "positionOffset": [0, 0, 0]},
        "hero_model": {"assetName": "iPhone17ProMax", "instanceLabel": "iPhone16",
                       "rotationEuler": [0, 0, 0], "scale": [1, 1, 1], "positionOffset": [0, 0, 0]},
        "caption": {"sizePt": 40, "paddingTop": 93.38908032319392, "paddingSides": 0.0,
                    "fontFamily": "System Default", "role": "Text1"},
        "hero_title": {"sizePt": 44, "paddingTop": 89.5, "paddingSides": 0.0,
                       "fontFamily": "Avenir Next", "role": "Title"},
        "hero_subtitle": {"sizePt": 30, "paddingTop": 94.5, "paddingSides": 0.0,
                          "fontFamily": "System Default", "role": "SubTitle"},
    },
    "ipad": {
        "folder": "ipad-13",
        "sizePresetID": "app_store_ipad",
        "size": [2.56, 3.415],
        "y": -4.495,
        "spacing": 2.68,
        "model": {"assetName": "iPadPro129", "instanceLabel": "iPad Pro 12.9″",
                  "rotationEuler": [0, -0.2617994, 0], "scale": [1.1, 1.1, 1.1],
                  "positionOffset": [0, -0.0074857413, 0]},
        "hero_model": {"assetName": "iPadPro129", "instanceLabel": "iPad Pro 12.9″",
                       "rotationEuler": [0, -0.2617994, 0], "scale": [1.1, 1.1, 1.1],
                       "positionOffset": [0, -0.0074857413, 0]},
        "caption": {"sizePt": 44, "paddingTop": 4.421637357414459, "paddingSides": 6,
                    "fontFamily": "Avenir Next", "role": "Title"},
        "hero_title": {"sizePt": 52, "paddingTop": 3.2, "paddingSides": 6,
                       "fontFamily": "Avenir Next", "role": "Title"},
        "hero_subtitle": {"sizePt": 32, "paddingTop": 8.6, "paddingSides": 6,
                          "fontFamily": "System Default", "role": "SubTitle"},
    },
    "mac": {
        "folder": "mac",
        "sizePresetID": "app_store_mac",
        "size": [3.6, 2.25],
        "y": -8.91,
        "spacing": 3.8,
        # The flat screen your iSeismometer and Seismica boards use, nudged up so the text
        # sits under it (paddingTop is a percentage of the board height: ~88 is the bottom)
        "model": {"assetName": "Generic", "instanceLabel": "Generic",
                  "rotationEuler": [0, 0, 0], "scale": [0.78, 0.78, 0.78],
                  "positionOffset": [0, 0.008, 0], "deviceStyle": "uiOnly"},
        "hero_model": {"assetName": "Generic", "instanceLabel": "Generic",
                       "rotationEuler": [0, 0, 0], "scale": [0.78, 0.78, 0.78],
                       "positionOffset": [0, 0.008, 0], "deviceStyle": "uiOnly"},
        "caption": {"sizePt": 44, "paddingTop": 89, "paddingSides": 7,
                    "fontFamily": "Avenir Next", "role": "Title"},
        "hero_title": {"sizePt": 44, "paddingTop": 86, "paddingSides": 7,
                       "fontFamily": "Avenir Next", "role": "Title"},
        "hero_subtitle": {"sizePt": 30, "paddingTop": 92.5, "paddingSides": 0,
                          "fontFamily": "System Default", "role": "SubTitle"},
    },
}


def new_id():
    return str(uuid.uuid4()).upper()


def text_block(string, index, spec, weight, color):
    return {
        "id": new_id(),
        "index": index,
        "string": string,
        "role": spec["role"],
        "fontFamily": spec["fontFamily"],
        "sizePt": spec["sizePt"],
        "weight": weight,
        "colorHex": color,
        "alignment": "center",
        "horizontalAlignment": spec.get("horizontalAlignment", "center"),
        "paddingTop": spec["paddingTop"],
        "paddingSides": spec["paddingSides"],
        "isItalic": False,
        "isUnderlined": False,
    }


def model_block(spec, asset_filename):
    model_id = new_id()
    return {
        "id": model_id,
        "sourceModelID": model_id,
        "assetName": spec["assetName"],
        "instanceLabel": spec["instanceLabel"],
        "deviceStyle": spec.get("deviceStyle", "realistic"),
        "clayColorHex": "#CCCCCCFF",
        "rotationEuler": spec["rotationEuler"],
        "scale": spec["scale"],
        "positionOffset": spec["positionOffset"],
        "uiOnlyOverlayCornerRadiusFactor": 0,
        "screenImageFilename": asset_filename,
    }


def build(shots_dir, out_dir, lang=None):
    captions = CAPTIONS.get(lang, {}) if lang else {}
    if lang:
        shots_dir = os.path.join(shots_dir, lang)
    package = os.path.join(out_dir, f"GPXExplore-{lang}.butterkit" if lang else "GPXExplore.butterkit")
    assets = os.path.join(package, "Assets")
    if os.path.exists(package):
        shutil.rmtree(package)
    os.makedirs(assets)

    artboards = []
    sequence = 0
    for preset_name, preset in PRESETS.items():
        count = len(SCENES)
        for index, (shot, caption) in enumerate(SCENES):
            source = os.path.join(shots_dir, preset["folder"], f"{shot}.png")
            if not os.path.exists(source):
                sys.exit(f"missing screenshot: {source}")
            asset_filename = f"{new_id()}.png"
            shutil.copyfile(source, os.path.join(assets, asset_filename))

            is_hero = caption is None
            if is_hero:
                texts = [
                    text_block(HERO_TITLE, 0, preset["hero_title"], "heavy", "#F5FCFFFF"),
                    text_block(captions.get("subtitle", HERO_SUBTITLE), 1, preset["hero_subtitle"], "regular", "#C9D3DCFF"),
                ]
            else:
                texts = [text_block(captions.get(shot, caption), 0, preset["caption"], "heavy", "#FFFFFFFF")]

            x = (index - (count - 1) / 2) * preset["spacing"]
            sequence += 1
            artboards.append({
                "id": new_id(),
                "name": f"{preset_name} hero" if is_hero else f"{preset_name} {shot}",
                "sequenceIndex": sequence,
                "sizePresetID": preset["sizePresetID"],
                "size": preset["size"],
                "position": [round(x, 4), preset["y"], 0],
                "cameraProjection": "perspective",
                "perspectiveFOVDeg": 35,
                "orthoHeight": 0.18917927,
                "background": BACKGROUND,
                "models": [model_block(preset["hero_model"] if is_hero else preset["model"], asset_filename)],
                "textBlocks": texts,
                "imageBlocks": [],
            })

    document = {"schemaVersion": 1, "baseLanguageCode": lang or "en", "artboards": artboards}
    with open(os.path.join(package, "Document.json"), "w") as handle:
        json.dump(document, handle, indent=2)
    print(f"wrote {package}: {len(artboards)} artboards, {len(os.listdir(assets))} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", default=DEFAULT_SHOTS)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--lang", help="de, fr, es or ja: captures from screenshots/<lang>/, captions in that language, package GPXExplore-<lang>.butterkit")
    args = parser.parse_args()
    build(args.shots, args.out, args.lang)
