"""Checks for capture markers, header layout, and the FFmpeg composition path."""

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageChops, ImageStat

ROOT = Path(os.environ.get("ADA_LS_DEMO_TEST_ROOT", Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location("renderer", ROOT / "scripts/render-demo.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


def marker(index, cell=24):
    image = Image.new("L", (240, 8), 24)
    draw = ImageDraw.Draw(image)
    values = [1, 0, 1] + [(index >> bit) & 1 for bit in range(3, -1, -1)]
    for i, value in enumerate(values):
        draw.rectangle((i*cell, 0, (i+1)*cell-1, 7), fill=255 if value else 0)
    return image


class RendererTest(unittest.TestCase):
    def test_markers_survive_compression_and_font_metrics(self):
        for cell in (22, 24, 26):
            for index in range(14):
                data = BytesIO()
                marker(index, cell).save(data, format="JPEG", quality=65)
                self.assertEqual(renderer.decode_marker(Image.open(BytesIO(data.getvalue()))), index)
        self.assertEqual(renderer.decode_marker(Image.new("L", (240, 8), 30)), 0)
        with self.assertRaises(ValueError):
            renderer.decode_marker(marker(15))

    def test_all_text_fits_and_transition_settles(self):
        scenes = renderer.load_scenes(ROOT / "media/demo_scenes.json")
        header = renderer.Header(scenes)
        for index in range(14):
            self.assertEqual(header.frame(index, 0).size, (1280, 198))
            self.assertEqual(header.frame(index, 0.25).tobytes(), header.frame(index, 1).tobytes())
            self.assertNotEqual(header.frame(index, 0).tobytes(), header.frame(index, 1).tobytes())

    def test_read_frame_handles_short_reads_and_truncation(self):
        class ShortReads(BytesIO):
            def read(self, size):
                return super().read(min(size, 2))
        self.assertEqual(renderer.read_frame(ShortReads(b"abcd"), 4), b"abcd")
        self.assertIsNone(renderer.read_frame(BytesIO(), 4))
        with self.assertRaises(RuntimeError):
            renderer.read_frame(BytesIO(b"abc"), 4)

    def test_real_video_sync_and_failure_cleanup(self):
        scenes = renderer.load_scenes(ROOT / "media/demo_scenes.json")
        with tempfile.TemporaryDirectory(prefix="ada-ls-renderer-test-") as tmp:
            tmp = Path(tmp)
            capture, output = tmp/"capture.mp4", tmp/"output.mp4"
            encoder = subprocess.Popen([
                "ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                "-s", "1280x720", "-r", "30", "-i", "pipe:0", "-c:v", "libx264",
                "-threads", "2", "-pix_fmt", "yuv420p", str(capture),
            ], stdin=subprocess.PIPE)
            for index in [0]+list(range(1, 14))+[0]:
                image = Image.new("RGB", (1280, 720), "#1e1e2e")
                ImageDraw.Draw(image).rectangle((200, 300, 600, 320), fill="#89dceb")
                image.paste(marker(index).convert("RGB"), (20, 32))
                for _ in range(9):
                    encoder.stdin.write(image.tobytes())
            encoder.stdin.close()
            self.assertEqual(encoder.wait(), 0)
            renderer.compose(capture, output, scenes)
            info = json.loads(subprocess.check_output([
                "ffprobe", "-v", "error", "-count_frames", "-show_streams", "-of", "json", str(output),
            ]))["streams"][0]
            self.assertEqual((info["width"], info["height"]), (1280, 864))
            self.assertEqual(int(info["nb_read_frames"]), 135)
            self.assertEqual(info["pix_fmt"], "yuv420p")
            # The marker row is cropped; editor content keeps its native geometry.
            data = subprocess.check_output([
                "ffmpeg", "-v", "error", "-ss", "1", "-i", str(output),
                "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "pipe:1",
            ])
            finished = Image.open(BytesIO(data)).convert("RGB")
            self.assertGreater(finished.getpixel((300, 198+300-54))[1], 180)
            bg = Image.new("RGB", (240, 8), "#1e1e2e")
            removed = finished.crop((20, 198, 260, 206))
            self.assertLess(max(ImageStat.Stat(ImageChops.difference(bg, removed)).mean), 5)
            # A video without the numbered sequence must not produce a result.
            subprocess.run([
                "ffmpeg", "-y", "-v", "error", "-i", str(capture), "-t", "0.2",
                "-c", "copy", str(tmp/"incomplete.mp4"),
            ], check=True)
            with self.assertRaises(ValueError):
                renderer.compose(tmp/"incomplete.mp4", tmp/"failed.mp4", scenes)
            self.assertFalse((tmp/"failed.mp4").exists())


if __name__ == "__main__":
    unittest.main()
