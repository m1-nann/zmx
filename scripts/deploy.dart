/// deploy.dart — deploy the locally-built zmx binary to MINI, PRO, NHATRANG.
///
/// DEPLOY ONLY — this script never builds. Build first with `make build`
/// (host binary -> zig-out/bin/zmx), then `make deploy`.
///
/// What it does, per host:
///   1. rsync zig-out/bin/zmx  ->  HOST:~/.local/bin/zmx
///      rsync writes a temp file then renames, so the copy is atomic and safe
///      even while a zmx is running from that path (the running daemon keeps
///      the old inode until it exits; new invocations pick up the new binary).
///   2. run `zmx version` on HOST and verify it reports the SAME version as the
///      local binary. `zmx version` embeds the git commit hash (e.g.
///      "0.5.0-fd2ddcc"), so this catches a stale, partial, or wrong copy.
///
/// All three hosts are macOS arm64 (same as the build host), so the single host
/// binary runs everywhere. If that ever changes, build per-arch with
/// `zig build release` and teach this script to pick the matching artifact.
///
/// Usage (run from the repo root):
///   make deploy                       deploy to all hosts
///   dart scripts/deploy.dart          same
///   dart scripts/deploy.dart PRO      deploy to a subset (host names, any case)
///   dart scripts/deploy.dart --help
library;

import 'dart:io';

// ── config ──────────────────────────────────────────────────────────────────
const _allHosts = ['MINI', 'PRO', 'NHATRANG'];
const _localBin = 'zig-out/bin/zmx'; // produced by `make build`
const _remoteBinDir = r'$HOME/.local/bin'; // expanded by the remote shell
const _remoteBin = '.local/bin/zmx'; // rsync dest, relative to remote $HOME
const _remoteZmx = r'$HOME/.local/bin/zmx'; // absolute invoke for version check
// Fail fast on an unreachable host instead of hanging on the default TCP timeout.
const _sshTimeout = 'ConnectTimeout=10';

// ── logging ─────────────────────────────────────────────────────────────────
void info(String s) => stdout.writeln('\x1b[36m▸\x1b[0m $s');
void ok(String s) => stdout.writeln('\x1b[32m✓\x1b[0m $s');
void warn(String s) => stderr.writeln('\x1b[33m!\x1b[0m $s');
void fail(String s) => stderr.writeln('\x1b[31m✗\x1b[0m $s');

class DeployError implements Exception {
  final String message;
  DeployError(this.message);
  @override
  String toString() => message;
}

// Stream a command's output; throw DeployError on non-zero exit.
Future<void> run(String exe, List<String> args) async {
  stdout.writeln('\x1b[90m\$ $exe ${args.join(' ')}\x1b[0m');
  final p = await Process.start(exe, args, mode: ProcessStartMode.inheritStdio);
  final code = await p.exitCode;
  if (code != 0) {
    throw DeployError('command failed (exit $code): $exe ${args.join(' ')}');
  }
}

// Run a command and return its trimmed stdout. Throws DeployError on non-zero
// exit. Interpolation (not `as`) coerces the dynamic stdout/stderr to String.
Future<String> capture(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) {
    throw DeployError('command failed (exit ${r.exitCode}): $exe '
        '${args.join(' ')}\n${'${r.stderr}'.trim()}');
  }
  return '${r.stdout}'.trim();
}

// ── version helpers ─────────────────────────────────────────────────────────
// `zmx version` prints e.g. "zmx\t\t0.5.0-fd2ddcc" on its first line; the last
// whitespace-separated token of that line is the version (semver + commit hash).
String parseZmxVersion(String versionOutput) {
  final firstLine = versionOutput.split('\n').first.trim();
  final parts = firstLine.split(RegExp(r'\s+'));
  return parts.isEmpty ? firstLine : parts.last;
}

// ── steps ───────────────────────────────────────────────────────────────────
// Deploy to one host. Returns true only when the copy landed AND the deployed
// binary reports the expected version.
Future<bool> deployHost(String host, String expected) async {
  info('deploying to $host');
  try {
    // NHATRANG has no ~/.local/bin yet; rsync won't create it for us.
    await run('ssh', ['-o', _sshTimeout, host, 'mkdir -p $_remoteBinDir']);
    await run('rsync', [
      '-az',
      '-e',
      'ssh -o $_sshTimeout',
      _localBin,
      '$host:$_remoteBin',
    ]);

    // Verify: the deployed binary must report exactly what we shipped.
    final remote = parseZmxVersion(
      await capture('ssh', ['-o', _sshTimeout, host, '$_remoteZmx version']),
    );
    if (remote != expected) {
      fail('$host version mismatch: expected "$expected", got "$remote"');
      return false;
    }
    ok('$host -> $remote');
    return true;
  } on DeployError catch (e) {
    fail('$host: ${e.message}');
    return false;
  }
}

void printHelp() {
  stdout.writeln('''
deploy.dart — deploy the locally-built zmx to ${_allHosts.join(', ')} (deploy only, no build)

Usage (run from the repo root):
  make deploy                       deploy to all hosts
  dart scripts/deploy.dart          same
  dart scripts/deploy.dart PRO      deploy to a subset (host names, any case)
  dart scripts/deploy.dart --help   this message

Build first (this script never builds):
  make build                        host binary -> $_localBin

Ships $_localBin to each HOST:~/$_remoteBin, then verifies `zmx version`
(which embeds the git commit hash) matches the local binary.''');
}

// Dart ignores main()'s return value for the process exit code, so set the
// global `exitCode` instead — that's what `make deploy` checks.
Future<void> main(List<String> args) async {
  exitCode = await _deploy(args);
}

Future<int> _deploy(List<String> args) async {
  if (args.contains('--help') || args.contains('-h') || args.contains('help')) {
    printHelp();
    return 0;
  }

  // Positional args (if any) select a subset of hosts, matched case-insensitively.
  final selectors = args.where((a) => !a.startsWith('-')).toList();
  final hosts = <String>[];
  for (final s in selectors) {
    final match = _allHosts.where((h) => h.toLowerCase() == s.toLowerCase());
    if (match.isEmpty) {
      fail('unknown host "$s" (known: ${_allHosts.join(', ')})');
      return 2;
    }
    hosts.add(match.first);
  }
  if (hosts.isEmpty) hosts.addAll(_allHosts);

  // Preflight: the local binary must exist — this script never builds.
  final bin = File(_localBin);
  if (!bin.existsSync()) {
    fail('local binary not found: $_localBin');
    warn('build it first:  make build');
    return 2;
  }

  // Expected version = what the LOCAL binary reports. That is exactly the binary
  // we ship, so each remote must match it.
  final String expected;
  try {
    expected = parseZmxVersion(await capture(bin.absolute.path, ['version']));
  } on DeployError catch (e) {
    fail('could not read local zmx version: ${e.message}');
    return 2;
  }

  // Advisory: warn if the built binary predates the current commit, so a forgotten
  // rebuild doesn't quietly ship an old binary.
  try {
    final headSha = await capture('git', ['rev-parse', '--short', 'HEAD']);
    if (!expected.endsWith(headSha)) {
      warn('local binary is "$expected" but HEAD is "$headSha" — '
          'it may be stale; rebuild with `make build`');
    }
  } on DeployError {
    // not a git checkout, or git unavailable — skip the advisory.
  }

  stdout.writeln(
    '\x1b[1mDeploying zmx $expected -> ${hosts.join(', ')}\x1b[0m\n',
  );

  final started = DateTime.now();
  final failed = <String>[];
  for (final host in hosts) {
    if (!await deployHost(host, expected)) failed.add(host);
  }

  final secs = DateTime.now().difference(started).inSeconds;
  stdout.writeln('');
  if (failed.isEmpty) {
    ok('deployed zmx $expected to all ${hosts.length} host(s) in ${secs}s');
    return 0;
  }
  fail('failed on ${failed.length}/${hosts.length}: ${failed.join(', ')}');
  return 1;
}
