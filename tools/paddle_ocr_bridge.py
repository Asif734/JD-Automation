#!/usr/bin/env python3
"""Persistent JSON-lines bridge between JD Automation and PaddleOCR."""

import base64
import json
import os
import sys
from pathlib import Path

import cv2
import numpy as np
from paddleocr import PaddleOCR


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def recognize(ocr, image, full_width, full_height, offset_x=0, offset_y=0, scale=1.0):
    """Run OCR and map every result back to full-window normalized bounds."""
    observations = []
    for result in ocr.predict(image):
        data = result.json.get("res", {})
        polygons = data.get("rec_polys") or data.get("dt_polys") or []
        texts = data.get("rec_texts") or []
        scores = data.get("rec_scores") or []
        for polygon, text, score in zip(polygons, texts, scores):
            points = np.asarray(polygon, dtype=float) / scale
            min_x = float(points[:, 0].min()) + offset_x
            max_x = float(points[:, 0].max()) + offset_x
            min_y = float(points[:, 1].min()) + offset_y
            max_y = float(points[:, 1].max()) + offset_y
            observations.append({
                "text": str(text),
                "confidence": float(score),
                "x": min_x / full_width,
                "y": min_y / full_height,
                "width": (max_x - min_x) / full_width,
                "height": (max_y - min_y) / full_height,
            })
    return observations


def merge_observations(primary, recovered):
    """Merge the enlarged chat pass without emitting the same line twice."""
    merged = list(primary)
    for candidate in recovered:
        candidate_center_y = candidate["y"] + candidate["height"] / 2
        duplicate_index = None
        for index, existing in enumerate(merged):
            existing_center_y = existing["y"] + existing["height"] / 2
            same_line = abs(candidate_center_y - existing_center_y) <= max(
                0.006, candidate["height"] * 0.65, existing["height"] * 0.65
            )
            horizontal_overlap = min(
                candidate["x"] + candidate["width"],
                existing["x"] + existing["width"],
            ) - max(candidate["x"], existing["x"])
            min_width = min(candidate["width"], existing["width"])
            if same_line and min_width > 0 and horizontal_overlap / min_width >= 0.45:
                duplicate_index = index
                break
        if duplicate_index is None:
            merged.append(candidate)
            continue
        existing = merged[duplicate_index]
        # The enlarged pass often recovers punctuation or words that the
        # whole-window pass clipped. Prefer its more complete recognition.
        candidate_length = len("".join(candidate["text"].split()))
        existing_length = len("".join(existing["text"].split()))
        if candidate_length > existing_length or (
            candidate_length == existing_length
            and candidate["confidence"] > existing["confidence"]
        ):
            merged[duplicate_index] = candidate
    return merged


def visual_regions(image):
    """Find substantial rectangular media regions without Apple Vision."""
    height, width = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 60, 160)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=2)
    contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    image_area = float(width * height)
    candidates = []
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        area = float(w * h)
        if w < width * 0.035 or h < height * 0.065:
            continue
        if area < image_area * 0.002 or area > image_area * 0.36:
            continue
        contour_area = abs(cv2.contourArea(contour))
        if area <= 0 or contour_area / area < 0.35:
            continue
        candidates.append({
            "x": x / width,
            "y": y / height,
            "width": w / width,
            "height": h / height,
            "confidence": min(1.0, max(0.35, contour_area / area)),
        })

    def contains(outer, inner):
        tolerance = 0.006
        return (
            outer["x"] <= inner["x"] + tolerance
            and outer["y"] <= inner["y"] + tolerance
            and outer["x"] + outer["width"] >= inner["x"] + inner["width"] - tolerance
            and outer["y"] + outer["height"] >= inner["y"] + inner["height"] - tolerance
        )

    candidates.sort(key=lambda item: item["width"] * item["height"], reverse=True)
    retained = []
    for candidate in candidates:
        if any(contains(existing, candidate) for existing in retained):
            continue
        retained.append(candidate)
        if len(retained) >= 32:
            break
    return retained


def main():
    if getattr(sys, "frozen", False):
        model_root = Path(sys._MEIPASS) / "official_models"
    else:
        cache_root = Path(os.environ.get("PADDLE_PDX_CACHE_HOME", ".paddlex-cache"))
        model_root = cache_root / "official_models"
    ocr = PaddleOCR(
        # Mobile models are required for a continuously running desktop
        # capture loop. The previous v6 medium pair could consume half of the
        # machine's memory and take longer than the app timeout per frame.
        text_detection_model_name="PP-OCRv5_mobile_det",
        text_detection_model_dir=str(model_root / "PP-OCRv5_mobile_det"),
        text_recognition_model_name="PP-OCRv5_mobile_rec",
        text_recognition_model_dir=str(model_root / "PP-OCRv5_mobile_rec"),
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
    )
    emit({"event": "ready", "engine": "paddleocr"})
    for raw_line in sys.stdin:
        try:
            request = json.loads(raw_line)
            request_id = request["id"]
            encoded = request["pngBase64"]
            image_bytes = base64.b64decode(encoded)
            image = cv2.imdecode(np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
            if image is None:
                raise ValueError("PaddleOCR could not decode the supplied PNG")
            height, width = image.shape[:2]

            # OCR only the conversation column. The former whole-window pass
            # was expensive and its result was then duplicated by this crop.
            # This column contains sender labels, transfer notices and every
            # wrapped bubble line needed by the extractor.
            crop_left = int(width * 0.15)
            crop_right = int(width * 0.68)
            crop_top = int(height * 0.14)
            crop_bottom = int(height * 0.84)
            chat_crop = image[crop_top:crop_bottom, crop_left:crop_right]
            observations = []
            if chat_crop.size:
                enlarged = cv2.resize(
                    chat_crop,
                    None,
                    fx=2.0,
                    fy=2.0,
                    interpolation=cv2.INTER_CUBIC,
                )
                observations = recognize(
                    ocr,
                    enlarged,
                    width,
                    height,
                    offset_x=crop_left,
                    offset_y=crop_top,
                    scale=2.0,
                )
            observations.sort(key=lambda item: (round(item["y"], 3), item["x"]))
            emit({
                "id": request_id,
                "observations": observations,
                "visualRegions": visual_regions(image),
            })
        except Exception as error:
            emit({"id": locals().get("request_id"), "error": str(error)})


if __name__ == "__main__":
    main()
