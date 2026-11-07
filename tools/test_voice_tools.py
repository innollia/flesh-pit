"""Checks build_voice_sheet.py and check_voice_files.py on a small made-up game
folder in a temp directory, with plain tones.

Run:  python -X utf8 tools/test_voice_tools.py
"""
import contextlib
import io
import json
import math
import struct
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path

import build_voice_sheet
import check_voice_files
import voice_lines


def tone(path: Path, seconds=1.0, rate=48000, channels=1, amp=0.1):
    n = int(seconds * rate)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(
            struct.pack("<h", int(math.sin(i * 0.05) * amp * 32767)) * channels for i in range(n)
        ))


class VoiceTools(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.game = Path(tmp.name) / "game"
        data = self.game / "main/data"
        data.mkdir(parents=True)
        self.voice = self.game / "audio/voice"
        self.voice.mkdir(parents=True)
        (self.voice / ".gitkeep").touch()
        self.write_lines({"first.heard": "하나", "tank.leave": "둘", "biome.fat_caves.1": "셋"})
        (data / "vent_rules.json").write_text(json.dumps(
            {"사건": {"x": {"설명": "물통에서 멀어질 때", "대사": ["tank.leave"]}}}, ensure_ascii=False), encoding="utf-8")

    def write_lines(self, lines):
        rows = [{"id": k, "section": "1", "ko": v} for k, v in lines.items()]
        (self.game / "main/data/vent_lines.json").write_text(json.dumps({"lines": rows}, ensure_ascii=False), encoding="utf-8")

    def run_check(self, **kw):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_voice_files.check(self.game, **kw)
        return code, out.getvalue()

    def test_nothing_recorded_is_fine_until_strict(self):
        code, out = self.run_check()
        self.assertEqual(code, 0)
        self.assertIn("대사 3줄, 파일 있음 0줄, 없음 3줄", out)
        self.assertEqual(self.run_check(strict=True)[0], 1)

    def test_good_clip(self):
        tone(self.voice / "first.heard.wav")
        code, out = self.run_check()
        self.assertEqual(code, 0)
        self.assertIn("파일 있음 1줄", out)
        self.assertNotIn("샘플레이트", out)

    def test_file_without_a_line(self):
        tone(self.voice / "first.heardd.wav")
        (self.voice / "first.heard.mp3").write_bytes(b"x")
        code, out = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("first.heardd.wav: 대응하는 대사가 없다", out)
        self.assertIn("first.heard.mp3: 대응하는 대사가 없다", out)

    def test_import_side_files_are_not_clips(self):
        (self.voice / "first.heard.wav.import").write_text("x")
        self.assertEqual(self.run_check()[0], 0)

    def test_broken_and_empty_files(self):
        (self.voice / "first.heard.wav").write_bytes(b"not a wav")
        tone(self.voice / "tank.leave.wav", seconds=0.0)
        code, out = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("first.heard.wav: 읽을 수 없다", out)
        self.assertIn("tank.leave.wav: 소리가 없다", out)

    def test_both_formats(self):
        tone(self.voice / "first.heard.wav")
        (self.voice / "first.heard.ogg").write_bytes(b"x")
        code, out = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("둘 다 있다", out)

    def test_format_and_length_notes(self):
        tone(self.voice / "first.heard.wav", rate=44100, channels=2)
        tone(self.voice / "tank.leave.wav", seconds=0.05)
        tone(self.voice / "biome.fat_caves.1.wav", seconds=16.0)
        code, out = self.run_check()
        self.assertEqual(code, 0)
        self.assertIn("샘플레이트 44100", out)
        self.assertIn("2채널", out)
        self.assertIn("너무 짧다", out)
        self.assertIn("너무 길다", out)
        self.assertIn("끊길 수 있다", out)

    def test_loudness_note(self):
        tone(self.voice / "first.heard.wav", seconds=2.0, amp=0.9)
        code, out = self.run_check()
        self.assertIn("LUFS", out)

    def test_changed_wording_is_found(self):
        tone(self.voice / "first.heard.wav")
        self.run_check(stamp_now=True)
        self.assertEqual(json.loads((self.voice / "recorded_lines.json").read_text(encoding="utf-8")), {"first.heard": "하나"})
        self.assertNotIn("문구가 바뀌었다", self.run_check()[1])
        self.write_lines({"first.heard": "하나 고침", "tank.leave": "둘", "biome.fat_caves.1": "셋"})
        code, out = self.run_check()
        self.assertEqual(code, 0)
        self.assertIn("first.heard.wav: 녹음한 뒤 문구가 바뀌었다", out)

    def test_extensible_wav(self):
        path = self.voice / "first.heard.wav"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=f=220:d=1:r=48000",
                        "-ac", "1", "-c:a", "pcm_s24le", str(path)], check=True)
        code, out = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("EXTENSIBLE", out)
        self.assertEqual(self.run_check(fix=True)[0], 0)
        self.assertEqual(self.run_check()[0], 0)
        with wave.open(str(path)) as w:
            self.assertEqual(w.getsampwidth(), 3)

    def test_ogg_header(self):
        path = self.voice / "first.heard.ogg"
        tone(self.voice / "src.wav", seconds=1.5)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(self.voice / "src.wav"), "-c:a", "libvorbis", str(path)], check=True)
        (self.voice / "src.wav").unlink()
        info = check_voice_files.ogg_info(path)
        self.assertEqual((info["rate"], info["channels"]), (48000, 1))
        self.assertAlmostEqual(info["seconds"], 1.5, delta=0.05)

    def test_sheet(self):
        tone(self.voice / "first.heard.wav")
        self.assertEqual(voice_lines.clip_ids(self.game), {"first.heard": "wav"})
        rows = {r["id"]: r for r in build_voice_sheet.rows(self.game)}
        self.assertEqual(rows["first.heard"]["state"], "done")
        self.assertEqual(rows["tank.leave"]["state"], "todo")
        self.assertEqual(rows["tank.leave"]["when"], "물통에서 멀어질 때")
        self.assertEqual(rows["biome.fat_caves.1"]["section"], "처음 다녀온 바이옴: fat_caves")
        self.assertEqual(rows["biome.fat_caves.1"]["mood"], "혼잣말")
        out = self.game / "build/sheet.html"
        self.assertEqual(build_voice_sheet.build(self.game, out), 3)
        page = out.read_text(encoding="utf-8")
        self.assertIn("48 kHz", page)
        self.assertIn(str(self.voice), page)
        self.assertIn('"first.heard"', page)

    def test_sheet_marks_changed_wording(self):
        tone(self.voice / "first.heard.wav")
        self.run_check(stamp_now=True)
        self.write_lines({"first.heard": "고침", "tank.leave": "둘", "biome.fat_caves.1": "셋"})
        rows = {r["id"]: r for r in build_voice_sheet.rows(self.game)}
        self.assertEqual(rows["first.heard"]["state"], "stale")

    def test_real_data_every_line_named_and_conditioned(self):
        game = voice_lines.REPO / "game"
        lines = voice_lines.load_lines(game)
        ids = [line["id"] for line in lines]
        self.assertEqual(len(ids), len(set(ids)), "line ids are unique across the three files")
        for line in lines:
            self.assertRegex(line["id"], r"^[a-z0-9_.]+$", "ids are safe file names")
            self.assertNotEqual(line["mood"], "기타", line["id"])
            self.assertTrue(line["when"], line["id"])


if __name__ == "__main__":
    unittest.main()
