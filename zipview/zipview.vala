/*
 *  A full screen image viewing/slideshow app (jpeg)
 *
 *  Features:
 *    Slideshow on/off (s) & timer adjust (up faster/down slower)
 *    Quickly jump between image subdirectories (PageUp/PageDown)
 *    Sorts files in dir's based on the last numbers found in filename
 *    Touchscreen mode (use -t on commandline)
 */

/*****************************************************************************
The MIT License

Copyright (c) 2009 Robert Thomson, http://xri.net/=rmt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*****************************************************************************/

using GLib.Random;
using GLib;
using Gtk;
using Gdk;
using Archive;

class ZipSource {
    string archive = null;

    public ZipSource(string archive) {
        this.archive = archive;
    }

    public GLib.List<string> filelist() {
        var r = new Archive.Read();
        r.support_format_all();
        r.support_compression_all();
        int res = r.open_filename( archive );
        var imgs = new GLib.List<string> ();
        if( 0 != res ) {
            stderr.printf("Could not open archive.\n");
            return imgs;
        }

        Archive.Entry e = null;
        while( 0 == r.next_header(&e) ) {
            imgs.append(e.pathname());
        }
        return imgs;
    }

    public Gdk.Pixbuf? get_pixbuf(string path) throws GLib.Error
    {
        Archive.Entry e = null;
        var r = new Archive.Read();
        r.support_format_all();
        r.support_compression_all();

        int res = r.open_filename( archive );
        if( 0 != res ) {
            stderr.printf("Could not open archive.\n");
            return null;
        }

        while( 0 == r.next_header(&e) ) {
            if( e.pathname() == path ) {
                var l = new PixbufLoader();
                var buf = new uchar[4096];
                var size = 0L;
                while(true) {
                    size = r.data(buf);
                    if(size == 0L)
                        break;
                    l.write(buf);
                }
                r.close();
                l.close();
                return l.get_pixbuf();
            }
        }
        stderr.printf("Could not find file in archive.  Has the archive changed?\n");
        return null;
    }

    public Gdk.Pixbuf get_pixbuf_at_size(string path, int screen_width, int screen_height)
    throws GLib.Error
    {
        var pb = get_pixbuf(path);
        var img_width = pb.get_width();
        var img_height = pb.get_height();
        float scale_x = screen_width / (float)img_width;
        float scale_y = screen_height / (float)img_height;
        float scale = scale_x < scale_y ? scale_x : scale_y;
        return pb.scale_simple((int)(scale*img_width), (int)(scale*img_height), Gdk.InterpType.HYPER);
    }
}

class CircularIter<G> : GLib.Object {
    private weak GLib.List<G> pos = null;
    private weak GLib.List<G> _first = null;
    private weak GLib.List<G> _last = null;

    public CircularIter (GLib.List<G> list) {
        this._first = list;
        this._last = null;
        this.pos = list;
    }

    public new G get () {
        if(pos != null)
            return pos.data;
        return null;
    }

    public bool next () {
        if(pos != null) {
            pos = pos.next;
            if(pos == null) {
                pos = _first;
            }
        }
        return true;
    }

    public bool prev () {
        if(pos != null) {
            pos = pos.prev;
            if(pos == null)
                pos = _first.last(); // slow op, but doesn't occur too often
        }
        return true;
    }

    public bool first () {
        pos = _first;
        return true;
    }

    public bool last () {
        if(_last != null)
            pos = _last;
        else if(pos != null)
            pos = pos.last();
        else if(_first != null)
            pos = _first.last();
        _last = pos;
        return true;
    }

}


class Browser : Gtk.Window
{
    int width = 0; // screen.width
    int height = 0; // screen.height
    Gtk.Image image;
    private CircularIter<string> iter;
    private ZipSource zipsource;
    int counter = 0; // slideshow: if counter == countermax, show next image
    const int TICK = 250; // how often on_timeout is called
    int countermax = 8; // TICK * countermax is slideshow delay

    static bool slideshow = false; // slideshow mode active
    static bool verbose = false;
#if MAEMO
    static bool touch = true; // touch screen interface
#else
    static bool touch = false; // touch screen interface
#endif
    static bool random = false; // randomise all sub-directories

    Color? get_color (string colstr)
    {
        Color col;
        if(Color.parse(colstr, out col))
            return col;
        return null;
    }


    construct
    {
        var screen = get_screen();
        width = screen.get_width();
        height = screen.get_height();

        var ebox = new Gtk.EventBox();
        image = new Gtk.Image();

        var col_black = get_color("black");
        modify_bg(StateType.NORMAL, col_black);
        ebox.modify_bg(StateType.NORMAL, col_black);
        image.modify_bg(StateType.NORMAL, col_black);

        ebox.add(image);
        add(ebox);
        destroy += Gtk.main_quit;
        title = "PView";
        fullscreen();

        Timeout.add(TICK, on_timeout);
        key_press_event += on_keypress;

        // this should enable basic use on touchscreen devices
        if(touch)
            ebox.button_press_event += on_button_down;

        show_all(); // need to do this here so we can blank the cursor

#if !MAEMO
        // hide cursor
        var pix_data = "#define invisible_cursor_width 1\n#define invisible_cursor_height 1\n#define invisible_cursor_x_hot 0\n#define invisible_cursor_y_hot 0\nstatic unsigned short invisible_cursor_bits[] = {\n0x0000 };";
        var pix = Gdk.Pixmap.create_from_data(get_window(), pix_data, 1, 1, 1, col_black, col_black);
        get_window().set_cursor(new Cursor.from_pixmap(pix, pix, col_black, col_black, 0, 0));
#endif
    } // construct

    void show_image()
    {
        if(iter.get() == null) {
            main_quit();
        }
        try
        {
            string filename = iter.get();
            Gdk.Pixbuf pixbuf =
                zipsource.get_pixbuf_at_size(filename, width, height);
            image.set_from_pixbuf(pixbuf);
        } catch(GLib.Error e) {
        }
    }

    bool next_image()
    {
        iter.next();
        counter = 0;
        show_image();
        return true;
    } // next_image

    bool prev_image()
    {
        iter.prev();
        counter = 0;
        show_image();
        return true;
    }

    bool prev_path()
    {
        for(var i=0; i<10; i++)
            iter.prev();
        show_image();
        return true;
    }

    bool next_path()
    {
        for(var i=0; i<10; i++)
            iter.next();
        show_image();
        return true;
    }

    bool on_timeout()
    {
        if(!slideshow)
            return true;
        counter++;
        if(counter < countermax)
            return true;
        counter = 0;
        return next_image();
    }

    bool on_button_down(EventBox w, Gdk.EventButton e) {
            // p defines the clickable area
            int p = (height / 3);
            if(width < height)
                p = (width / 3);
            if(e.x <= p && e.y <= p) {
                // top left
                iconify();
                main_quit();
            } else if(e.x <= p && e.y >= (height-p)) {
                // bottom left
                slideshow = !slideshow;
            } else if(e.x >= (width-p) && e.y >= (height-p)) {
                // bottom right
                next_path();
            } else if(e.x >= (width-p) && e.y <= p) {
                // top right
                prev_path();
            } else if(e.x <= p) {
                // after elimination, center left
                prev_image();
            } else if(e.x >= (width-p)) {
                // after elimination, center right
                next_image();
            } else if(e.y <= p) {
                // after elimination, middle top
                countermax = countermax > 1 ? countermax - 1 : 1;
            } else if(e.y >= (height-p)) {
                // after elimination, middle bottom
                countermax += 1;
            } else {
                // in the center, not clickable if width == height
                stdout.printf("%s\n", iter.get());
            }
            return true;
    }

    bool on_keypress(Browser b, Gdk.EventKey e)
    {
        if(e.str == "q" || e.str == "Q") {
            iconify();
            Gtk.main_quit();
            return false;
        }
        else if(e.str == " " || e.keyval == 0xff53) { // right arrow
            next_image();
        }
        else if(e.keyval == 0xff56 || e.keyval == 0xffc4) {
            // page down or n810's hw plus key
            next_path();
        }
        else if(e.keyval == 0xff55 || e.keyval == 0xffc5) {
            // page up
            prev_path();
        }
        else if(e.keyval == 0xff51) { // left arrow
            prev_image();
        }
        else if(e.keyval == 0xff52) { // up arrow
            countermax = countermax > 1 ? countermax - 1 : 1;
        }
        else if(e.keyval == 0xff54) { // down arrow
            countermax += 1;
        }
        else if(e.keyval == 0x73) {
            slideshow = !slideshow;
            counter = 0;
        }
        else if(e.keyval == 0xff1b) { // escape key
            slideshow = false;
            iconify();
        }
        else if(e.keyval == 0xffc3) { // minimise/fs button on n810
            slideshow = false;
            iconify();
        }
        else if(e.str == "/" || e.str == "?") {
            stdout.printf("%s\n", iter.get());
        }
        return true;
    } // on_keypress

    const OptionEntry[] options = {
        { "verbose", 'v', 0, OptionArg.NONE, ref verbose, "Be verbose", null },
        { "slideshow", 's', 0, OptionArg.NONE, ref slideshow, "Start in slideshow mode", null },
#if !MAEMO
        { "touchscreen", 't', 0, OptionArg.NONE, ref touch, "Enable touchscreen/clicking interface", null },
#endif
        { "random", 'r', 0, OptionArg.NONE, ref random, "Randomise the order of sub-directories of images", null },
        { null }
    };

    public static string file_chooser() {
        var dialog = new FileChooserDialog("Select archive", null, FileChooserAction.OPEN);
        var filter = new FileFilter();
        filter.add_pattern("*.zip");
        filter.add_pattern("*.tar");
        filter.add_pattern("*.tar.gz");
        dialog.set_filter(filter);
        dialog.local_only = true;
        return dialog.get_filename();
    }

    public static int main(string[] args)
    {

        var context = new OptionContext("<imagedir1> [imagedir2] [...]");
        context.set_summary("Recursively add and display jpeg images from a list of directories.");
        context.set_description("""Keys:
  q              quit
  escape         minimise window
  Left arrow     show previous image
  Right arrow or space     show next image
  Up arrow       speed up the slideshow
  Down arrow     slow down the slideshow
  PageDown       progress to the next directory of images
  PageUp         progress to the start of the previous directory of images
  s              disable/enable the slideshow mode
  / or ?         print the current image's location on standard output""");
        context.add_main_entries(options, null);
        context.add_group(Gtk.get_option_group(true));
        try {
            context.parse(ref args);
        } catch(GLib.OptionError e) {
            stdout.printf("%s\n\n", e.message);
#if !MAEMO
            stdout.printf("%s\n", context.get_help(true, null));
#endif
            return 1;
        }

        Gtk.init(ref args);
        if(args.length == 1) {
#if MAEMO
            stdout.printf("Not enough arguments!\n");
#else
           stdout.printf("%s\n", context.get_help(true, null));
#endif
           return 1;
        }
        var browser = new Browser();
        Gtk.main_iteration(); // show the window

        browser.zipsource = new ZipSource(args[1]);
        var imgs = browser.zipsource.filelist();

        browser.iter = new CircularIter<string>(imgs);
        browser.show_image();
        browser.show_all();
        Gtk.main();
        return 0;
    } // main

} // class Browser
