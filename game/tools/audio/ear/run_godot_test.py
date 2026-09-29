# -*- coding: utf-8 -*-
import subprocess, os

GODOT = r"C:\Users\fixme\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
PROJECT = r"C:\Users\fixme\Desktop\flesh-pit-main\game"
SCRIPT = r"res://tests/run_audio_tests.gd"

args = [GODOT, "--headless", "--path", PROJECT, "--script", SCRIPT]
BASE = r"C:\Users\fixme\Desktop\flesh-pit-main\game\tools\audio\ear"
log = open(os.path.join(BASE, "godot_audio_test.log"), "wb")
err = open(os.path.join(BASE, "godot_audio_test_err.log"), "wb")
p = subprocess.Popen(args, stdout=log, stderr=err, cwd=PROJECT)
print("PID", p.pid)
