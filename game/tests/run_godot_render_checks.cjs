// Exercise actual Compatibility rendering; propagate every Godot failure.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const suites = [
  ['capture_terrain_surface.gd', /CAPTURE failures=0/],
  ['capture_terrain_pending_overflow.gd', /\b\d+ passed, 0 failed\b/],
  ['capture_terrain_solid_volume.gd', /\b\d+ passed, 0 failed\b/],
  ['capture_terrain_main_solid.gd', /\b\d+ passed, 0 failed\b/],
  ['capture_terrain_main_restore.gd', /\b\d+ passed, 0 failed\b/],
  ['capture_terrain_main_passage.gd', /\b\d+ passed, 0 failed\b/],
];

for (const [suite, success] of suites) {
  test(suite, () => {
    const result = spawnSync('godot_console', [
      '--path', 'game', '--resolution', '640x360', '--fixed-fps', '60',
      '--script', 'res://tests/' + suite,
    ], { cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024 });
    const output = (result.stdout || '') + (result.stderr || '');
    console.log(output.trim());
    assert.ifError(result.error);
    assert.equal(result.status, 0, 'Godot exit status');
    assert.match(output, success, 'actual rendering assertions evaluated');
    assert.doesNotMatch(output, /SCRIPT ERROR:|SHADER ERROR:|Parse Error:|Failed to load script/);
  });
}
