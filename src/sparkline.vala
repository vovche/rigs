/* sparkline.vala — GNOME Resources style smooth Bezier wave sparkline for Rigs */

namespace Rigs {

    public class SmoothSparkline : Gtk.DrawingArea {
        private double[] values;
        private int max_samples;
        private int count = 0;
        private double r;
        private double g;
        private double b;
        private bool auto_scale;
        private double min_scale;

        public SmoothSparkline(double r = 0.12, double g = 0.55, double b = 1.0, int max_samples = 25, int width = 120, int height = 34, bool auto_scale = false, double min_scale = 15.0) {
            this.r = r;
            this.g = g;
            this.b = b;
            this.max_samples = max_samples;
            this.auto_scale = auto_scale;
            this.min_scale = min_scale;
            this.values = new double[max_samples];
            for (int i = 0; i < max_samples; i++) {
                values[i] = 0.0;
            }

            this.set_content_width(width);
            this.set_content_height(height);
            this.add_css_class("sparkline-box");
            this.accessible_role = Gtk.AccessibleRole.PRESENTATION;

            this.set_draw_func(on_draw);
        }

        public void add_value(double val) {
            double clamped = auto_scale ? ((val > 0.0) ? val : 0.0) : val.clamp(0.0, 100.0);
            for (int i = 0; i < max_samples - 1; i++) {
                values[i] = values[i + 1];
            }
            values[max_samples - 1] = clamped;
            if (count < max_samples) count++;
            this.queue_draw();
        }

        private void on_draw(Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
            if (w <= 0 || h <= 0 || max_samples < 2) return;

            // 1. Draw rounded background container track
            double corner_r = 6.0;
            cr.save();
            cr.new_sub_path();
            cr.arc(w - corner_r, corner_r, corner_r, -Math.PI / 2.0, 0);
            cr.arc(w - corner_r, h - corner_r, corner_r, 0, Math.PI / 2.0);
            cr.arc(corner_r, h - corner_r, corner_r, Math.PI / 2.0, Math.PI);
            cr.arc(corner_r, corner_r, corner_r, Math.PI, 3.0 * Math.PI / 2.0);
            cr.close_path();

            cr.set_source_rgba(r, g, b, 0.08);
            cr.fill_preserve();

            cr.set_source_rgba(r, g, b, 0.18);
            cr.set_line_width(1.0);
            cr.stroke();
            cr.restore();

            double pad_y = 4.0;
            double draw_h = (double)h - (pad_y * 2.0);

            double scale_max = 100.0;
            if (auto_scale) {
                double peak = 1.0;
                for (int i = 0; i < max_samples; i++) {
                    if (values[i] > peak) peak = values[i];
                }
                double target_scale = peak * 1.25;
                scale_max = (target_scale > min_scale) ? target_scale : min_scale;
            }

            // Clip wave drawing inside rounded area
            cr.save();
            cr.new_sub_path();
            cr.arc(w - corner_r, corner_r, corner_r, -Math.PI / 2.0, 0);
            cr.arc(w - corner_r, h - corner_r, corner_r, 0, Math.PI / 2.0);
            cr.arc(corner_r, h - corner_r, corner_r, Math.PI / 2.0, Math.PI);
            cr.arc(corner_r, corner_r, corner_r, Math.PI, 3.0 * Math.PI / 2.0);
            cr.close_path();
            cr.clip();

            // Compute points
            double[] xs = new double[max_samples];
            double[] ys = new double[max_samples];

            for (int i = 0; i < max_samples; i++) {
                xs[i] = ((double)i / (double)(max_samples - 1)) * (double)w;
                ys[i] = (double)h - pad_y - ((values[i] / scale_max).clamp(0.0, 1.0) * draw_h);
            }

            // Smooth cubic Bezier spline
            cr.save();
            cr.move_to(xs[0], ys[0]);

            for (int i = 0; i < max_samples - 1; i++) {
                double dx = (xs[i + 1] - xs[i]) / 2.0;
                cr.curve_to(xs[i] + dx, ys[i], xs[i + 1] - dx, ys[i + 1], xs[i + 1], ys[i + 1]);
            }

            // Gradient fill under curve
            cr.save();
            cr.line_to(w, h);
            cr.line_to(0, h);
            cr.close_path();

            var grad = new Cairo.Pattern.linear(0, 0, 0, h);
            grad.add_color_stop_rgba(0.0, r, g, b, 0.45);
            grad.add_color_stop_rgba(0.6, r, g, b, 0.18);
            grad.add_color_stop_rgba(1.0, r, g, b, 0.03);
            cr.set_source(grad);
            cr.fill();
            cr.restore();

            // Stroke line
            cr.set_source_rgba(r, g, b, 1.0);
            cr.set_line_width(2.5);
            cr.set_line_cap(Cairo.LineCap.ROUND);
            cr.set_line_join(Cairo.LineJoin.ROUND);
            cr.stroke();

            cr.restore(); // restore spline save
            cr.restore(); // restore clip save
        }
    }
}
