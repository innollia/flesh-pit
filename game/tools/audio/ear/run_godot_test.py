# -*- coding: utf-8 -*-
import subprocess, os

GODOT = r"C:\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not os.path.exists(GODOT):
    GODOT = os.path.expanduser("~") + r"\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SCRIPT = r"res://tests/run_audio_tests.gd"

args = [GODOT, "--headless", "--path", PROJECT, "--script", SCRIPT]
BASE = HERE
log = open(os.path.join(BASE, "godot_audio_test.log"), "wb")
err = open(os.path.join(BASE, "godot_audio_test_err.log"), "wb")
p = subprocess.Popen(args, stdout=log, stderr=err, cwd=PROJECT)
print("PID", p.pid)
