namespace Gis {
	public Shumate.PathLayer svy_path;
	public Shumate.MarkerLayer svy_markers;
	public Shumate.PathLayer svy_mpath;
	public Shumate.MarkerLayer svy_mpoints;
}

namespace SMenu {
	MWPPoint mk;
}

internal class AsPop : Object {
  internal Gtk.PopoverMenu pop;
  internal Gtk.Button button;

  public AsPop (GLib.MenuModel mmodel, MWPPoint mk, int n) {
    pop = new Gtk.PopoverMenu.from_model(mmodel);
    pop.set_has_arrow(true);
    var plab = new Gtk.Label("Survey #%d".printf(mk.no+1));
    var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL,1);
    box.hexpand = true;
    plab.hexpand = true;
    box.append(plab);
    if(n == -1) {
      pop.set_autohide(false);
      button = new Gtk.Button.from_icon_name("window-close");
      button.halign = Gtk.Align.END;
      box.append(button);
    } else {
      pop.set_autohide(true);
    }
    pop.add_child(box, "label");
	SMenu.mk = mk;
    pop.set_parent(mk);
  }
}

namespace Survey {
	const string POINTCOL="#a0a0a0a0";
	const int POINTSZ=36;

	[GtkTemplate (ui = "/org/stronnag/mwp/survey.ui")]
	public class Dialog : Adw.Window {
		[GtkChild]
		private unowned Gtk.Entry as_angle;
		[GtkChild]
		private unowned Gtk.DropDown as_turn;
		[GtkChild]
		private unowned Gtk.Entry as_rowsep;
		[GtkChild]
		private unowned Gtk.Entry as_altm;
		[GtkChild]
		private unowned Gtk.Switch as_rth;
		[GtkChild]
		private unowned Gtk.Entry as_speed;
		[GtkChild]
		private unowned Gtk.Button as_apply;
		[GtkChild]
		private unowned Gtk.Button as_view;
		[GtkChild]
		private unowned Gtk.Button as_mission;

		private GLib.MenuModel as_menu;
		internal GLib.SimpleActionGroup dg;

		private uint genpts;

		public Dialog () {
			genpts = 0;
			transient_for = Mwp.window;

			as_angle.text="0";
			as_angle.activate.connect(() => {
					generate_path();
				});

			as_rowsep.text = "20";
			as_rowsep.activate.connect(() => {
					generate_path();
				});
			as_turn.notify["selected"].connect(() =>  {
					generate_path();
				});
			as_altm.text = "50";
			as_altm.activate.connect(() => {
					generate_path();
				});
			as_speed.text = "7";


			as_apply.clicked.connect(() => {
					generate_path();
				});

			as_mission.clicked.connect(() => {
					generate_mission();
				});

			as_view.clicked.connect(() => {
					reset_view();
				});
			init();
		}

		private void generate_mission() {
			var rows = generate_path();
			print("Mission Generate %u rows\n", rows.length);
			int n = 0;
			int alt = int.parse(as_altm.text);
			int lspeed = (int)(100*double.parse(as_speed.text));
  			var ms = new Mission();
			MissionItem []mis={};
			foreach (var r in rows){
				n++;
				var mi =  new MissionItem.full(n, Msp.Action.WAYPOINT, r.start.y,
											   r.start.x, alt, lspeed, 0, 0, 0);
				mis += mi;
				n++;
				mi =  new MissionItem.full(n, Msp.Action.WAYPOINT, r.end.y,
											   r.end.x, alt, lspeed, 0, 0, 0);
				mis += mi;
			}
			if(as_rth.active) {
				n++;
				var mi =  new MissionItem.full(n, Msp.Action.RTH, 0, 0, 0, 0, 0, 0, 0);
				mis += mi;
			}
			mis[n-1].flag = 0xa5;
			ms.points = mis;
			ms.npoints = n;
			MissionManager.msx = {ms};
			MissionManager.is_dirty = true;
			MissionManager.mdx = 0;
			MissionManager.setup_mission_from_mm();
			close();
		}

		private void reset_view() {
			var inview = true;
			var mbx = MapUtils.get_bounding_box();
			var pts = Gis.svy_path.get_nodes();
			var npts = pts.length();
			for(var j = 0; j < npts; j++) {
				var mk = (MWPPoint)pts.nth_data(j);
				if(!mbx.covers(mk.latitude, mk.longitude)) {
					inview = false;
					break;
				}
			}
			if(!inview) {
				genpts = 0;
				Gis.svy_mpoints.remove_all();
				Gis.svy_markers.remove_all();
				Gis.svy_mpath.remove_all();
				Gis.svy_path.remove_all();
				make_default_box();
			}
		}

		private AreaCalc.RowPoints [] generate_path() {
			AreaCalc.RowPoints []rows={};
			var npts = Gis.svy_path.get_nodes().length();
			if(npts > 2) {
				AreaCalc.Vec []vec={};
				for(var j = 0; j < npts; j++) {
					var mk = (MWPPoint)Gis.svy_path.get_nodes().nth_data(j);
					AreaCalc.Vec v={0};
					v.y = mk.latitude;
					v.x = mk.longitude;
					vec += v;
				}
				double angle = double.parse(as_angle.text);
				double separation = double.parse(as_rowsep.text);
				uint8 turn = (uint8)as_turn.selected;
				Gis.svy_mpath.remove_all();
				Gis.svy_mpoints.remove_all();
				rows = AreaCalc.generateFlightPath(vec, angle, turn, separation);
				var n = 0;
				var col = "#00ffff60";
				MWPLabel mk = null;
				foreach (var r in rows){
					n++;
					mk = new MWPLabel("%3d".printf(n));
					mk.latitude = r.start.y;
					mk.longitude = r.start.x;
					mk.set_colour(col);
					Gis.svy_mpath.add_node(mk);
					Gis.svy_mpoints.add_marker(mk);
					n++;
					mk = new MWPLabel("%3d".printf(n));
					mk.latitude = r.end.y;
					mk.longitude = r.end.x;
					mk.set_colour(col);
					Gis.svy_mpath.add_node(mk);
					Gis.svy_mpoints.add_marker(mk);
				}
				if(as_rth.active) {
					mk.set_colour("#00aaff60");
				}
				genpts = rows.length;
			} else {
				genpts = 0;
			}
			return rows;
		}

		private MWPPoint SurveyMk(int n, double plat, double plon, int ipt=-1) {
			var mk = new MWPPoint.with_colour(POINTCOL);
			mk.latitude = plat;
			mk.longitude = plon;
			mk.no = n;
			mk.set_size_request(POINTSZ, POINTSZ);
			mk.set_draggable(true);
			mk.popup_request.connect((n, x, y) => {
					var pop = new AsPop(as_menu, mk, n);
					if (n == -1) {
						pop.button.clicked.connect(() => {
								pop.pop.popdown();
							});
					}
					pop.pop.popup();
				});
			Gis.svy_markers.add_marker(mk);
			if(ipt == -1) {
				Gis.svy_path.add_node(mk);
			} else {
				Gis.svy_path.insert_node (mk, (uint)ipt);
			}
			mk.drag_motion.connect((la,lo) => {
					if(genpts != 0) {
						generate_path();
					}
				});
			return mk;
		}

		public uint renumber() {
			var npts = Gis.svy_path.get_nodes().length();
			for(var j = 0; j < npts; j++) {
				var mk = (MWPPoint)Gis.svy_path.get_nodes().nth_data(j);
				mk.no = j;
			}
			return npts;
		}

		public void cleanup() {
			Gis.svy_mpoints.remove_all();
			Gis.svy_markers.remove_all();
			Gis.svy_mpath.remove_all();
			Gis.svy_path.remove_all();
			Gis.map.remove_layer(Gis.svy_mpoints);
			Gis.map.remove_layer(Gis.svy_mpath);
			Gis.map.remove_layer(Gis.svy_markers);
			Gis.map.remove_layer(Gis.svy_path);
		}

		public void init() {
			var sbuilder = new Gtk.Builder.from_resource ("/org/stronnag/mwp/surveymenu.ui");
			as_menu = sbuilder.get_object("as_popup") as GLib.MenuModel;
			dg = new GLib.SimpleActionGroup();
			var aq = new GLib.SimpleAction("asinsert",null);
			aq.activate.connect(() => {
					var npts = Gis.svy_path.get_nodes().length();
					var np = (1+SMenu.mk.no) % npts;
					var popmk = (MWPPoint)Gis.svy_path.get_nodes().nth_data(np);
					var nlat = (SMenu.mk.latitude + popmk.latitude)/2;
					var nlon = (SMenu.mk.longitude + popmk.longitude)/2;
					uint npx = npts - (SMenu.mk.no+1);
					SurveyMk((int)npts, nlat, nlon, (int)npx);
					var nv = renumber();
					if  (nv > 3) {
						MwpMenu.set_menu_state(dg, "asdelete", true);
					}
					if(genpts != 0) {
						generate_path();
					}
				});
			dg.add_action(aq);

			aq = new GLib.SimpleAction("asdelete",null);
			aq.activate.connect(() => {
					Gis.svy_path.remove_node(SMenu.mk);
					Gis.svy_markers.remove_marker(SMenu.mk);
					var nv = renumber();
					if  (nv < 4) {
						MwpMenu.set_menu_state(dg, "asdelete", false);
					}
					if(genpts != 0) {
						generate_path();
					}
				});
			dg.add_action(aq);
			Mwp.window.insert_action_group("survey", dg);

			Gis.svy_path = new Shumate.PathLayer(Gis.map.viewport);
			Gis.svy_mpath = new Shumate.PathLayer(Gis.map.viewport);
			Gis.svy_markers = new Shumate.MarkerLayer(Gis.map.viewport);
			Gis.svy_mpoints = new Shumate.MarkerLayer(Gis.map.viewport);
			Gis.map.add_layer(Gis.svy_markers);

			Gdk.RGBA rgba = {1,0.4f,0,0.5f};
			Gis.svy_path.set_stroke_width(5.0);
			Gis.svy_path.set_stroke_color(rgba);
			Gis.map.add_layer(Gis.svy_path);
			Gis.svy_path.closed = true;

			rgba = {1,0,0,0.7f};
			Gis.svy_mpath.set_stroke_width(2.0);
			Gis.svy_mpath.set_stroke_color(rgba);
			Gis.map.add_layer(Gis.svy_mpath);
			Gis.map.add_layer(Gis.svy_mpoints);

			make_default_box();
		}

		public void make_default_box() {
			var bbox = MapUtils.get_bounding_box();
			var wlon = 0.1*(bbox.maxlon - bbox.minlon);
			var wlat = 0.1*(bbox.maxlat - bbox.minlat);

			var plat = bbox.maxlat - wlat;

			var plon = bbox.minlon + wlon;
			SurveyMk(0, plat, plon);

			plon = bbox.maxlon - wlon;
			SurveyMk(1, plat, plon);

			plat = bbox.minlat + wlat;
			SurveyMk(2, plat, plon);

			plon = bbox.minlon + wlon;
			SurveyMk(3, plat, plon);
		}
	}
}