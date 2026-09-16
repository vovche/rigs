/* sparkline.vala — GNOME Resources style smooth Bezier wave sparkline for Rigs */

namespace Rigs {

    public class SmoothSparkline : Gtk.DrawingArea {
        private double[] values;
        private int max_samples;
        private int count = 0;
        private double r;
        private double g;
        private double b;

        public SmoothSparkline(double r = 0.208, double g = 0.518, double b = 0.894, int max_samples = 25, int width = 120, int height = 34) {
            this.r = r;
            this.g = g;
            this.b = b;
            this.max_samples = max_samples;
            this.values = new double[max_samples];
            for (int i = 0; i < max_samples; i++) {
                values[i] = 0.0;
            }

            this.set_content_width(width);
            this.set_content_height(height);
            this.add_css_class("sparkline-box");

            this.set_draw_func(on_draw);
        }

        public void add_value(double val) {
            double clamped = val.clamp(0.0, 100.0);
            for (int i = 0; i < max_samples - 1; i++) {
                values[i] = values[i + 1];
            }
            values[max_samples - 1] = clamped;
            if (count < max_samples) count++;
            this.queue_draw();
        }

        private void on_draw(Gtk.DrawingArea area, Cairo.Context cr, int w, int h) {
            if (w <= 0 || h <= 0 || max_samples < 2) return;

            double pad_y = 4.0;
            double draw_h = (double)h - (pad_y * 2.0);

            // Compute points
            double[] xs = new double[max_samples];
            double[] ys = new double[max_samples];

            for (int i = 0; i < max_samples; i++) {
                xs[i] = ((double)i / (double)(max_samples - 1)) * (double)w;
                ys[i] = (double)h - pad_y - ((values[i] / 100.0) * draw_h);
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
            grad.add_color_stop_rgba(0.0, r, g, b, 0.28);
            grad.add_color_stop_rgba(1.0, r, g, b, 0.01);
            cr.set_source(grad);
            cr.fill();
            cr.restore();

            // Stroke line
            cr.set_source_rgba(r, g, b, 0.95);
            cr.set_line_width(2.0);
            cr.set_line_cap(Cairo.LineCap.ROUND);
            cr.set_line_join(Cairo.LineJoin.ROUND);
            cr.stroke();

            cr.restore();
        }
    }
}
