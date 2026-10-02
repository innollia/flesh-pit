// Run the real Godot suites with failure propagation and isolated save paths.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const suites = process.env.FP_CHECK_SUITES
  ? process.env.FP_CHECK_SUITES.split(',')
  : ['run_tests.gd', 'run_tissue_tools_tests.gd', 'run_save_load.gd',
    'run_oct02_tests.gd', 'run_motion_tests.gd', 'run_watch_door_restore_tests.gd',
    'run_spray_attachment_tests.gd'];
const evidence = path.join(root, '.dryforge/evidence/checks');
fs.mkdirSync(evidence, { recursive: true });
for (const suite of suites) {
  test(suite, () => {
    assert.match(suite, /^run_[a-z0-9_]+\.gd$/);
    const source = fs.readFileSync(path.join(__dirname, suite), 'utf8');
    const savePath = path.join(evidence, suite + '.save').replaceAll('\\', '/');
    const init = source.match(/func _init\([^\n]*:\r?\n([ \t]+)\S/);
    assert.ok(init, 'suite initialization indentation found');
    const indent = init[1];
    const isolation = `\n${indent}root.child_entered_tree.connect(func(n):\n`
      + `${indent}${indent}if n.get_script() != null and n.get_script().resource_path == "res://main/scripts/main.gd":\n`
      + `${indent}${indent}${indent}n.save_path = ${JSON.stringify(savePath)}\n${indent})\n`;
    assert.match(source, /func _init\([^\n]*\):|func _init\([^\n]*-> void:/);
    const isolated = source.replace(/(func _init\([^\n]*:\r?\n)/, '$1' + isolation);
    assert.notEqual(isolated, source, 'save isolation inserted before suite initialization');
    const scriptPath = path.join(evidence, suite);
    fs.writeFileSync(scriptPath, isolated);
    const result = spawnSync('godot_console', ['--headless', '--path', 'game', '--script', scriptPath],
      { cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024 });
    const output = (result.stdout || '') + (result.stderr || '');
    fs.writeFileSync(path.join(evidence, suite + '.log'), output);
    console.log(output.trim());
    assert.ifError(result.error);
    assert.equal(result.status, 0, 'Godot exit status');
    assert.match(output, /\b\d+ passed, 0 failed\b/, 'suite actually evaluated and passed');
    assert.doesNotMatch(output, /SCRIPT ERROR:|SHADER ERROR:|Parse Error:|Failed to load script/);
  });
}
