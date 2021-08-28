using Gst;

[DBus (name = "org.droidian.Flashlightd")]
public class FlashlightServer : GLib.Object {

    public int Brightness { get; set; }

    private weak DBusConnection conn;
    private Gst.Element pipeline;

    public FlashlightServer (DBusConnection conn) {
        this.conn = conn;
        this.notify.connect (send_property_change);
    }

    public void SetBrightness(uint bvalue) {
        // mimic logind SetBrightness
        Brightness = (int) bvalue;
    }

    private void set_flashlight(){
        if (Brightness > 0){
            // turn on flashlight
            pipeline = Gst.parse_launch("droidcamsrc video-torch=true mode=2 ! fakesink");
            pipeline.set_state (State.PLAYING);
        } else {
            // turn off flashlight and free resources
            pipeline.set_state (State.NULL);
            pipeline = null;
        }
    }

    private void send_property_change (ParamSpec p) {
        var builder = new VariantBuilder (VariantType.ARRAY);
        var invalid_builder = new VariantBuilder (new VariantType ("as"));

        if (p.name == "Brightness") {
            Variant i = Brightness;
            builder.add ("{sv}", "Brightness", i);

            set_flashlight();
        }

        try {
            conn.emit_signal (null,
                              "/org/droidian/Flashlightd",
                              "org.freedesktop.DBus.Properties",
                              "PropertiesChanged",
                              new Variant ("(sa{sv}as)",
                                           "org.droidian.Flashlightd",
                                           builder,
                                           invalid_builder)
                              );
        } catch (Error e) {
            stderr.printf ("%s\n", e.message);
        }
    }
}

[DBus (name = "org.droidian.Flashlightd")]
public errordomain FlashlightError
{
    SOME_ERROR
}

void on_bus_aquired (DBusConnection conn) {
    try {

        conn.register_object ("/org/droidian/Flashlightd",
                              new FlashlightServer (conn));
    } catch (IOError e) {
        stderr.printf ("Could not register service\n");
    }
}

void main (string[] args) {
    // Initialize GStreamer
    Gst.init (ref args);

    GLib.Bus.own_name (BusType.SESSION, "org.droidian.Flashlightd", BusNameOwnerFlags.NONE,
                  on_bus_aquired,
                  () => {},
                  () => stderr.printf ("Could not aquire name\n"));

    new MainLoop ().run ();
}

