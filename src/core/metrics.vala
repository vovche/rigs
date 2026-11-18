/* metrics.vala — Pure, unit-tested arithmetic for telemetry.
 * Kernel counters are uint64 and not always monotonic (e.g. iowait):
 * never subtract them directly, always go through these helpers. */
namespace Rigs {
    public class Metrics : Object {
        // a - b for counters, clamped at 0 instead of wrapping around.
        public static uint64 saturating_delta(uint64 previous, uint64 current) {
            return current > previous ? current - previous : 0;
        }

        // 100 * Δpart / Δtotal, clamped to [0, 100]; 0 when there is no progress.
        public static double delta_percent(uint64 prev_part, uint64 part, uint64 prev_total, uint64 total) {
            uint64 dt = saturating_delta(prev_total, total);
            if (dt == 0) return 0.0;
            double pct = 100.0 * saturating_delta(prev_part, part) / dt;
            return pct.clamp(0.0, 100.0);
        }

        // Host busy share from /proc/stat aggregates (idle includes iowait).
        public static double busy_percent(uint64 prev_idle, uint64 prev_total, uint64 idle, uint64 total) {
            uint64 dt = saturating_delta(prev_total, total);
            if (dt == 0) return 0.0;
            uint64 di = uint64.min(saturating_delta(prev_idle, idle), dt);
            return (100.0 * (dt - di) / dt).clamp(0.0, 100.0);
        }

        // Podman/Docker report CPU per core ("250.3%"): convert to a share of the whole host
        // so every driver uses the same scale as the host overview. Returns 0 for garbage.
        public static double container_cpu_share(string raw, uint cpu_count = 0) {
            double value;
            if (!double.try_parse(raw.replace("%", "").strip(), out value) || value.is_nan() || value < 0)
                return 0.0;
            uint cpus = cpu_count > 0 ? cpu_count : get_num_processors();
            return (value / cpus).clamp(0.0, 100.0);
        }

        // QEMU-style sizes: "4096", "4G", "4GiB", "512M", "2T". Unknown input → 0.
        public static double parse_mem_to_mb(string raw) {
            string s = raw.strip().up();
            string[,] units = {
                { "TIB", "1048576" }, { "TB", "1048576" }, { "T", "1048576" },
                { "GIB", "1024" }, { "GB", "1024" }, { "G", "1024" },
                { "MIB", "1" }, { "MB", "1" }, { "M", "1" },
                { "KIB", "0.0009765625" }, { "KB", "0.0009765625" }, { "K", "0.0009765625" }
            };
            double factor = 1.0;
            for (int i = 0; i < units.length[0]; i++) {
                if (s.has_suffix(units[i, 0])) {
                    s = s.substring(0, s.length - units[i, 0].length).strip();
                    factor = double.parse(units[i, 1]);
                    break;
                }
            }
            double value = 0.0;
            if (s.length == 0 || !double.try_parse(s, out value) || value < 0) return 0.0;
            return value * factor;
        }
    }
}
