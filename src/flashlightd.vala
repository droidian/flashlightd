using Gst;

[DBus (name = "org.droidian.Flashlightd")]
public class FlashlightServer : GLib.Object {

    private const size_t path_sysfs_size = 7;
    private const string[] sysfs_path = {"/sys/class/leds/torch-light/brightness",
                                  "/sys/class/leds/led:flash_torch/brightness",
                                  "/sys/class/leds/flashlight/brightness",
                                  "/sys/class/leds/torch-light0/brightness",
                                  "/sys/class/leds/torch-light1/brightness",
                                  "/sys/class/leds/led:torch_0/brightness",
                                  "/sys/class/leds/led:torch_1/brightness"};

    private const size_t sysfs_switch_size = 2;
    private const string[] sysfs_switch = {"/sys/class/leds/led:switch/brightness",
                                          "/sys/class/leds/led:switch_0/brightness"};

    public const string SYSFS_ENABLE = "255";
    public const string SYSFS_DISABLE = "0";

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

    private bool sysfs = false;

    private void set_flashlight(){
        if (Brightness > 0){
            // turn on flashlight
            pipeline = Gst.parse_launch("droidcamsrc video-torch=true mode=2 ! fakesink");

            var result = pipeline.set_state (State.PLAYING);

            // fallback to sysfs if droidcamsrc isn't available
            if(result == StateChangeReturn.FAILURE) {
                sysfs = true;
                foreach (var path in sysfs_path) {
                    var file = File.new_for_path(path);
                    if (file.query_exists()) {
                        try {
                            var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                            out_stream.write_all(SYSFS_ENABLE.data, null);
                            out_stream.close();
                        } catch (Error e) {

                        }
                    }
                }
                foreach (var path in sysfs_switch) {
                    var file = File.new_for_path(path);
                    if (file.query_exists()) {
                        try {
                            var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                            out_stream.write_all(SYSFS_ENABLE.data, null);
                            out_stream.close();
                        } catch (Error e) {

                        }
                    }
                }
            }
        } else {
            // turn off flashlight and free resources
            if(pipeline != null) {
                var result = pipeline.set_state (State.NULL);
                if(sysfs == true) {
                    foreach (var path in sysfs_path) {
                        var file = File.new_for_path(path);
                        if (file.query_exists()) {
                            try {
                                var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                                out_stream.write_all(SYSFS_DISABLE.data, null);
                                out_stream.close();
                            } catch (Error e) {

                            }
                        }
                    }
                    foreach (var path in sysfs_switch) {
                        var file = File.new_for_path(path);
                        if (file.query_exists()) {
                            try {
                                var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                                out_stream.write_all(SYSFS_DISABLE.data, null);
                                out_stream.close();
                            } catch (Error e) {

                            }
                        }
                    }
                }
                pipeline = null;
            }
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
