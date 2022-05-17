using Gtk;

namespace Sticks {

	public class StickWindow : Gtk.Window {
		public bool active;
		public Sticks.Pad lstick;
		public Sticks.Pad rstick;

		public StickWindow(Gtk.Window? pw = null) {
			set_transparent();
			set_default_size (400, 200);
			set_decorated(false);
			set_keep_above(true);
			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
			add (box);
			lstick = new Sticks.Pad (1000, 1500, false);
			box.pack_start(lstick, true, true, 2);
			rstick = new Sticks.Pad (1500,1500, true);
			box.pack_start(rstick, true, true, 2);
			destroy.connect (() => {
					active = false;
					base.hide();
				});
			if (pw != null) {
				set_transient_for (pw);
			}
		}

		public new void show_all() {
			base.show_all();
			active = true;
		}

		private void set_transparent() {
			draw.connect((w, c) => {
					c.set_source_rgba(0, 0, 0, 0);
					c.set_operator(Cairo.Operator.SOURCE);
					c.paint();
					c.set_operator(Cairo.Operator.OVER);
					return false;
				});
			var screen = get_screen();
			var visual = screen.get_rgba_visual();
			if (visual!= null && screen.is_composited())
				set_visual(visual);
			set_app_paintable(true);
		}
	}

	public class Pad : DrawingArea {
        private double _x;
        private double _y;
		private double _hs;
		private double _vs;
		private bool _rside;

        public Pad (int ivs, int ihs, bool rside = false) {
			_vs = ivs;
			_hs = ihs;
			_rside = rside;
        }

		private const int LW=4;
		private const int CRAD=10;
		private const double OFFSET = 0.1;
		private const double SCALE = 0.8;

		private void draw_base(Cairo.Context cr) {
            double x = _x;
            double y = _y;

            cr.set_source_rgba (0.4, 0.4, 0.4, 0.5);
			cr.rectangle(0, 0, x, y);
			cr.fill();

            cr.set_source_rgba (0.1, 0.1, 0.1, 0.5);
			cr.rectangle(x*OFFSET, y*OFFSET, x*SCALE, y*SCALE);
			cr.fill();

			cr.set_line_width(LW);

			cr.move_to(x*0.5, y*OFFSET);
			cr.set_source_rgb (0.6, 0.6, 0.6);
			cr.line_to(x*0.5, y*(OFFSET+SCALE));
			cr.stroke();

			cr.move_to(OFFSET*x, y/2);
			cr.line_to(x*(OFFSET+SCALE), y/2);
			cr.stroke();
		}

        public override bool draw (Cairo.Context cr) {
            _x = get_allocated_width () ;
            _y = get_allocated_height ();
			draw_base(cr);
            draw_dynamic(cr);
            return false;
        }

        private void draw_dynamic (Cairo.Context cr) {
			double sx, sy;
			sx = _hs - 1000;
			sx = _x*OFFSET + SCALE*_x*(sx / 1000.0);
			sy = 2000.0 - _vs;
			sy = OFFSET*_y + SCALE*_y*(sy / 1000.0);

			// draw blob and text
			cr.set_source_rgb (1, 0, 0);
			cr.arc (sx, sy, CRAD, 0, 2 * Math.PI);
			cr.fill();
			cr.stroke();

			cr.set_font_size (0.042 * _x);
			cr.set_source_rgb (1, 1, 1);
			if (_rside == false)
				cr.move_to (0, _y/2);
			else
				cr.move_to (0.9*_x, _y/2);

            cr.show_text ("%4.0f".printf(_hs));
			cr.move_to (_x/2, 0.95*_y);
            cr.show_text ("%4.0f".printf(_vs));
            cr.stroke ();

		}

        public void update(double vs, double hs) {
			_vs = vs;
			_hs = hs;
			queue_draw();
        }

    }
}

#if TEST
// valac -D TEST  --pkg gtk+-3.0 --pkg cairo  sticks.vala
int main (string[] args) {
    Gtk.init (ref args);
    var sw = new Sticks.StickWindow ();
    sw.show_all ();

	new Thread<bool>("stdinread", () => {
			while (!stdin.eof ()) {
				stdout.printf("widget %s\n", sw.active.to_string());
				var s = stdin.read_line();
				if (s != null) {
					var parts = s.split(" ");
					if (parts.length > 1) {
						var ivs = int.parse(parts[0]);
						var ihs = int.parse(parts[1]);
						stdout.printf("LS: vs: %d, hs: %d\n", ivs, ihs);
						Idle.add(() => {
								sw.lstick.update(ivs, ihs);
								return false;
							});
					}
					if (parts.length == 4) {
						var ivs = int.parse(parts[2]);
						var ihs = int.parse(parts[3]);
						stdout.printf("RS: vs: %d, hs: %d\n", ivs, ihs);
						Idle.add(() => {
								sw.rstick.update(ivs, ihs);
								return false;
							});
					}
				}
			}
			return false;
		});
    Gtk.main ();
    return 0;
}
#endif
