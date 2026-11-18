#!/usr/bin/env bash
# lint.sh — mechanical guardrails for defect classes found in review.
# Runs as the meson test "lint" (so ./build.sh fails on violations).
# Each rule ID is documented in docs/guardrails.md with the wrong and the right pattern.
# Suppress a single line only with a trailing comment:  // lint-allow: <RULE-ID> <reason>
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2
fail=0

report() { # rule file:line message
    echo "$2: [$1] $3 (see docs/guardrails.md)"
    fail=1
}

# grep_rule RULE 'ERE' "message" [files...] — every match outside allow-comments is a violation.
grep_rule() {
    local rule="$1" pattern="$2" message="$3"; shift 3
    local hit
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        [[ "$hit" == *"lint-allow: $rule"* ]] && continue
        [[ "$rule" == MODEL-01 && "$hit" == *"track("* ]] && continue
        report "$rule" "${hit%%:*}:$(cut -d: -f2 <<<"$hit")" "$message"
    done < <(grep -nHE -- "$pattern" "$@" 2>/dev/null)
}

SRC=$(find src -name '*.vala' | sort)
TESTS=$(find tests -name '*.vala' | sort)

# --- Process execution -------------------------------------------------------
grep_rule SPAWN-01 'Process\.spawn_' \
    "Spawn processes only through HostCommand (sandbox modes, LC_ALL=C, deadlines, no shell parsing)." $SRC
grep_rule SPAWN-02 'communicate_utf8' \
    "communicate_utf8 throws on non-UTF-8 output; use HostCommand.run / bytes_to_text." $SRC
grep_rule SPAWN-03 '"(socat|python3?|perl|nc)"|\b(socat|python3) -' \
    "Do not shell out to helpers for socket I/O; use GIO (see HmpMonitor, GuestMedia)." $SRC

# A shell may only run commands the USER configured verbatim, never strings we assemble.
while IFS= read -r hit; do
    [[ -z "$hit" || "$hit" == *"lint-allow: SHELL-01"* ]] && continue
    if ! grep -qE '"-c", *(cmd|resource\.(start|stop|connect)_cmd) *\}' <<<"$hit"; then
        report SHELL-01 "$(cut -d: -f1,2 <<<"$hit")" \
            "bash -c may only receive a user-configured command variable (cmd, resource.start_cmd, resource.stop_cmd, resource.connect_cmd). Pass data as separate argv elements."
    fi
done < <(grep -nHE '"-c"' $SRC 2>/dev/null)

# --- Silent failures ---------------------------------------------------------
DRIVERS=$(find src/core/drivers -name '*.vala' | sort)
grep_rule SILENT-01 '\bwarning *\(|\bmessage *\(|\bdebug *\(' \
    "Drivers must not log failures where the user cannot see them; return a ResourceIssue (ResourceIssue.from_error, FailureRules.check_command / diagnose)." $DRIVERS
grep_rule SILENT-02 'new Thread *<' \
    "Drivers block and return; threads belong to ResourceActions, which publishes the returned issue." $DRIVERS
grep_rule SILENT-03 '^[[:space:]]*ResourceStore\.save *\(' \
    "ResourceStore.save() returns false when changes did not reach the disk; call it through a helper that tells the user (Window.persist)." $SRC

# --- Layering -----------------------------------------------------------------
CORE=$(find src/core -name '*.vala' | sort)
grep_rule CORE-01 '\b(Gtk|Adw|Gdk)\.' \
    "src/core is GLib-only (tests link it without GTK); move widget code to src/ui and pass data across." $CORE
grep_rule CORE-02 '^core_deps.*(gtk|adw)' \
    "Never add GTK/Libadwaita to core_deps: that would let widget code into the headless layer." src/meson.build

# --- GTK / application -------------------------------------------------------
grep_rule APP-01 'active_window as Window' \
    "active_window is null while any other window has focus; use Application.main_window()." $SRC
grep_rule UI-01 '\.timeout *= *0\b' \
    "A persistent toast blocks the ToastOverlay queue; keep the default timeout." $SRC

# Signals of long-lived models: every connection must be removable (ResourceCard.track / detach).
model_signals=$(grep -oE 'public signal void [a-z_]+' src/core/resource.vala | awk '{print $4}' | paste -sd'|')
if [[ -n "$model_signals" ]]; then
    grep_rule MODEL-01 "\\bresource\\.(${model_signals})\\.connect\\(|\\bresource\\.notify\\[[^]]*\\]\\.connect\\(" \
        "Connections to a Resource outlive the widget; wrap in track(...) and call detach() on removal." $SRC
fi

# --- Vala pitfalls -----------------------------------------------------------
grep_rule VALA-01 '\)\[-?[0-9]*:-?[0-9]*\]' \
    "Slicing a temporary array is a use-after-free in Vala; store the array in a local first." $SRC $TESTS
grep_rule VALA-05 '\?\?[^;]*\.split\([^)]*\)\[' \
    "An element of a temporary split() array inside ?? reads freed memory; split into a local array first." $SRC
grep_rule VALA-02 'split\("\\0"\)' \
    "A Vala string ends at the first NUL; split binary data (cmdline) as uint8[] instead." $SRC
grep_rule VALA-03 'uint64 [a-z_]+ = [^;]*[a-z_)] - ' \
    "Unsigned counter subtraction wraps around; use Metrics.saturating_delta()." $(grep -v 'src/core/metrics.vala' <<<"$SRC")
grep_rule VERSION-01 '"[0-9]+\.[0-9]+\.[0-9]+"' \
    "Do not hardcode the app version; use Config.VERSION (from meson.build)." $SRC

# Interface methods with default bodies are silently "implemented" by unrelated inherited methods.
iface_hits=$(for f in $SRC; do
    awk -v F="$f" '
        /^[[:space:]]*public interface / { in_iface = 1; depth = 0 }
        in_iface {
            if ($0 ~ /public virtual /) printf "%s:%d\n", F, NR
            n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m
            if (depth <= 0 && n + m > 0) in_iface = 0
        }' "$f"
done)
for loc in $iface_hits; do
    report VALA-04 "$loc" "Interface methods must be abstract; a default body hides missing implementations."
done

# --- Build registration (the most common small-model mistake) ----------------
for f in $(find src -name '*.vala' | sed 's|^src/||' | sort); do
    grep -q "'$f'" src/meson.build || report BUILD-01 "src/meson.build:1" "$f is not listed in rigs_sources."
done
for f in $(find tests -name 'test_*.vala' -o -name 'mock_*.vala' | sort); do
    grep -q "'$f'" meson.build || report BUILD-02 "meson.build:1" "$f is not listed in test_sources."
done
for fn in $(grep -hoE 'public static void test_[a-z0-9_]+' tests/test_*.vala | awk '{print $4}' | sort -u); do
    grep -qE "\\.$fn\\)" tests/main.vala || report BUILD-03 "tests/main.vala:1" "$fn is never registered with Test.add_func (it would silently not run)."
done
for f in $(grep -lE '_\("' $SRC); do
    grep -qx "$f" po/POTFILES.in || report I18N-01 "po/POTFILES.in:1" "$f uses _() but is missing from POTFILES.in."
done

if [[ $fail -ne 0 ]]; then
    echo "lint: FAILED — fix the code, or justify a single line with // lint-allow: <RULE> <reason>"
    exit 1
fi
echo "lint: OK"
