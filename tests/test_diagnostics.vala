/* test_diagnostics.vala — Unit tests for SystemDiagnostics */

namespace Rigs.Tests {
    public class TestDiagnostics {
        public static void test_diagnostics_report() {
            string report = SystemDiagnostics.get_report();
            assert_true(report.length > 50);
            assert_true("=== Rigs Diagnostics Report ===" in report);
            assert_true("### Application" in report);
            assert_true("Version: 1.0.0" in report);
            assert_true("### Packaging & Distribution" in report);
            assert_true("### Operating System & Kernel" in report);
            assert_true("### Desktop & Windowing" in report);
            assert_true("### Virtualization & Container Tooling" in report);
        }
    }
}
