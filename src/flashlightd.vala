using Gst;
using GLib;

[DBus (name = "org.droidian.Flashlightd")]
public class FlashlightServer : GLib.Object {

    private const size_t path_sysfs_size = 7;
    private const string[] sysfs_path = {"/sys/class/leds/torch-light/brightness",
                                  "/sys/class/leds/led:flash_torch/brightness",
                                  "/sys/class/leds/flashlight/brightness",
                                  "/sys/class/leds/torch-light0/brightness",
                                  "/sys/class/leds/torch-light1/brightness",
                                  "/sys/class/leds/led:torch_0/brightness",
                                  "/sys/class/leds/led:torch_1/brightness",
                                  "/sys/devices/platform/soc/soc:i2c@1/i2c-23/23-0059/s2mpb02-led/leds/torch-sec1/brightness"};

    private const size_t sysfs_exynos_size = 1;
    private string[] sysfs_exynos = {"/sys/devices/virtual/camera/flash/rear_flash"};

    private const size_t sysfs_switch_size = 2;
    private const string[] sysfs_switch = {"/sys/class/leds/led:switch/brightness",
                                          "/sys/class/leds/led:switch_0/brightness"};

    public const string SYSFS_ENABLE = "255";
    public const string SYSFS_DISABLE = "0";

    public const string EXYNOS_SYSFS_ENABLE = "1";

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
    Gst.StateChangeReturn result;

    private bool is_exynos = false;
    private uint8[] content;
    private string etag_out;
    private string device_model_file = "/proc/device-tree/model";
    private bool exynos_on = false;

    private void set_flashlight(){
        try {
             if (FileUtils.test (device_model_file, FileTest.EXISTS)) {
                 File file = File.new_for_path (device_model_file);

                 file.load_contents (null, out content, out etag_out);

                 var raw_content = (string) content;
                 if (raw_content.contains ("EXYNOS") || raw_content.contains ("exynos")) {
                     is_exynos = true;
                 }
             }
        } catch (Error e) {
            // permission issue?
        }

        if (is_exynos == false) {
             if (Brightness > 0){
                // turn on flashlight
                try {
                    var pipeline = Gst.parse_launch("droidcamsrc video-torch=true mode=2 ! fakesink");
                    var result = pipeline.set_state (State.PLAYING);
                } catch (Error e) {
                    sysfs = true;
                }

                // fallback to sysfs if droidcamsrc isn't available
                if(result == StateChangeReturn.FAILURE || sysfs) {
                    sysfs = true;
                    // on halium 10 we don't have droidcamsrc so gst.parse returns null and fails when turning the torch off
                    if (pipeline == null || (pipeline is Gst.Bin && (pipeline as Gst.Bin).get_children_count() == 0)) {
                        try {
                            pipeline = Gst.parse_launch("fakesink");
                        } catch (Error e) {
                            // it might already be initialized so leave it as is
                        }
                    }

                    foreach (var path in sysfs_path) {
                        var file = File.new_for_path(path);
                        if (file.query_exists()) {
                            try {
                                var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                                out_stream.write_all(SYSFS_ENABLE.data, null);
                                out_stream.close();
                            } catch (Error e) {
                                // some paths might throw an error because of permissions we just want to ignore those
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
                                // some paths might throw an error because of permissions we just want to ignore those
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
                                    // some paths might throw an error because of permissions we just want to ignore those
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
                                    // some paths might throw an error because of permissions we just want to ignore those
                                }
                             }
                        }
                    }
                    pipeline = null;
                }
            }
        // exynos devices cannot use our gst-droid plugin with droidcamsrc sink (at least not on droidian) and they use different values and different paths for flashlight in sysfs.
        // as a result cannot use the fallack sysfs backend or the gstreamer stuff so lets check if device is exynos and act accordingly.
        } else if(is_exynos == true) {
            if (exynos_on == false) {
                foreach (var path in sysfs_exynos) {
                    var file = File.new_for_path(path);
                    if (file.query_exists()) {
                        try {
                             var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                             out_stream.write_all(EXYNOS_SYSFS_ENABLE.data, null);
                             out_stream.close();
                        } catch (Error e) {
                             // some paths might throw an error because of permissions we just want to ignore those
                        }
                        exynos_on = true;
                    }
                }
            } else {
                foreach (var path in sysfs_exynos) {
                    var file = File.new_for_path(path);
                    if (file.query_exists()) {
                        try {
                             var out_stream = file.replace(null, false, FileCreateFlags.NONE, null);
                             out_stream.write_all(SYSFS_DISABLE.data, null);
                             out_stream.close();
                        } catch (Error e) {
                             // some paths might throw an error because of permissions we just want to ignore those
                        }
                        exynos_on = false;
                    }
                }
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
    bool is_exynos = false;
    uint8[] content;
    string etag_out;
    string device_model_file = "/proc/device-tree/model";
    try {
        if (FileUtils.test (device_model_file, FileTest.EXISTS)) {
           File file = File.new_for_path (device_model_file);
           file.load_contents (null, out content, out etag_out);
           var raw_content = (string) content;
           if (raw_content.contains ("EXYNOS")) {
               is_exynos = true;
           }
       }
    } catch (Error e) {
            // permission issue?
    }

    if (is_exynos != true) {
        // Initialize GStreamer
        Gst.init (ref args);
    }

    GLib.Bus.own_name (BusType.SESSION, "org.droidian.Flashlightd", BusNameOwnerFlags.NONE,
                  on_bus_aquired,
                  () => {},
                  () => stderr.printf ("Could not aquire name\n"));

    new MainLoop ().run ();
}
