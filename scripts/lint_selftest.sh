#!/usr/bin/env bash
# lint_selftest.sh — proves every lint rule still fires. Injects one violation per rule
# into a scratch copy of the tree and expects each rule ID in lint.sh output.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
T=$(mktemp -d "${TMPDIR:-/tmp}/rigs-lint-selftest-XXXXXX")
trap 'rm -rf "$T"' EXIT
cp -r "$ROOT/src" "$ROOT/tests" "$ROOT/po" "$ROOT/meson.build" "$ROOT/scripts" "$T/"
cat >> "$T/src/window.vala" <<'X'
// lint self-test injections
Process.spawn_command_line_sync("ls");
process.communicate_utf8(null, null, out a, out b);
host.run({ "socat", "-", path });
var x = { "/bin/bash", "-c", "echo " + path };
var w = this.active_window as Window;
toast.timeout = 0;
vm.startup_failed.connect(() => {});
foreach (var t in a.split(" ")[1:]) {}
string[] parts = cmdline.split("\0");
uint64 d = a - b;
string v = "1.2.3";
public interface Foo : Object { public virtual void bar() {} }
X
printf 'public static void test_orphan() {}\n' >> "$T/tests/test_models.vala"
touch "$T/src/orphan.vala" "$T/tests/test_orphan.vala"
printf 'string s = _("x");\n' > "$T/src/orphan.vala"
out=$(bash "$T/scripts/lint.sh" "$T" 2>&1)
missing=0
for rule in SPAWN-01 SPAWN-02 SPAWN-03 SHELL-01 APP-01 UI-01 MODEL-01 VALA-01 VALA-02 VALA-03 VALA-04 VERSION-01 BUILD-01 BUILD-02 BUILD-03 I18N-01; do
    grep -q "\[$rule\]" <<<"$out" || { echo "lint rule $rule no longer fires"; missing=1; }
done
bash "$ROOT/scripts/lint.sh" "$ROOT" >/dev/null || { echo "the real tree must lint clean"; missing=1; }
[[ $missing -eq 0 ]] && echo "lint self-test: OK"
exit $missing
