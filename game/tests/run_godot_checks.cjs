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
    'run_spray_attachment_tests.gd', 'run_live_interactions_tests.gd', 'run_saw_grip_tests.gd'];
const evidence = path.join(root, '.dryforge/evidence/checks');
fs.mkdirSync(evidence, { recursive: true });
// Godot's Main::start reads the Windows system CA store when no bundle is
// set; under CPU load that call sometimes never returns (idle hang before
// the first frame, ~3-8% of suite runs). The game uses no TLS, so the project
// points the setting at its own one-certificate file (engineering-notes.md).
test('startup never reads the system certificate store', () => {
  const project = fs.readFileSync(path.join(root, 'game/project.godot'), 'utf8');
  const m = project.match(/^\[network\][^[]*^tls\/certificate_bundle_override="res:\/\/([^"]+)"/m);
  assert.ok(m, 'project.godot sets network/tls/certificate_bundle_override to a res:// file');
  const pem = fs.readFileSync(path.join(root, 'game', m[1]), 'utf8');
  assert.match(pem, /-----BEGIN CERTIFICATE-----[\s\S]+-----END CERTIFICATE-----/);
});
// A check or capture that loads Main reads the player's key settings unless it
// points Main at its own file before add_child, and key tests write there too.
test('checks and captures never reach the player key file', () => {
  const scripts = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(file);
      else if (entry.name.endsWith('.gd')) scripts.push(file);
    }
  };
  walk(path.join(root, 'game/tests'));
  walk(path.join(root, 'game/tools'));
  const offenders = [];
  for (const file of scripts) {
    const name = path.relative(root, file).split(path.sep).join('/');
    const code = fs.readFileSync(file, 'utf8').split('\n')
      .filter((line) => !line.trimStart().startsWith('#')).join('\n');
    if (/user:\/\/keybinds\.json|USER_KEYBINDS_PATH/.test(code)) offenders.push(`${name}: names the player key file`);
    if (/add_child\([^\n]*main\.tscn/.test(code)) offenders.push(`${name}: adds Main without a variable to isolate`);
    const packed = [...code.matchAll(/(\w+)[^\n=]*=\s*\(?(?:pre)?load\("res:\/\/main\/scenes\/main\.tscn"\)/g)].map((m) => m[1]);
    for (const made of code.matchAll(/^[ \t]*(?:var[ \t]+)?(\w+)[^\n=]*=[ \t]*([^\n]*\.instantiate\(\))/gm)) {
      if (!made[2].includes('main.tscn') && !packed.some((p) => made[2].startsWith(`${p}.instantiate`))) continue;
      const rest = code.slice(made.index + made[0].length);
      const isolated = rest.indexOf(`${made[1]}.user_keybinds_path =`);
      const added = rest.indexOf(`add_child(${made[1]}`);
      if (isolated < 0 || (added >= 0 && added < isolated)) offenders.push(`${name}: ${made[1]} has no user_keybinds_path before add_child`);
    }
  }
  assert.deepEqual(offenders, []);
});
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
