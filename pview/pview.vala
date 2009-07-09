/*
 *  A full screen image viewing/slideshow app (jpeg)
 *
 *  Features:
 *    Slideshow on/off (s) & timer adjust (up faster/down slower)
 *    Quickly jump between image subdirectories (PageUp/PageDown)
 *    Sorts files in dir's based on the last numbers found in filename
 *    Touchscreen mode (use -t on commandline)
 *    Easily delete individual files or entire subdir's
 *    Delete mode is not enabled by default (use -d on commandline)
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

class CircularIter<G> : GLib.Object {
    private weak GLib.List<G> pos = null;
    private weak GLib.List<G> _first = null;

    public CircularIter (GLib.List<G> list) {
        this._first = list;
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
        if(pos != null)
            pos = pos.last();
        else if(_first != null)
            pos = _first.last();
        return true;
    }

    public bool delete () {
        if(pos == null)
            return false;
        weak List<G> next = pos.next != null ? pos.next : pos.prev;
        if(pos == _first)
            _first = next;
        pos.delete_link(pos);
        pos = next;
        return true;
    }
}


class Browser : Gtk.Window
{
    int width = 0; // screen.width
    int height = 0; // screen.height
    Gtk.Image image;
    private GLib.List<string> deletelist = new GLib.List<string> ();
    private CircularIter<string> iter;
    int counter = 0; // slideshow: if counter == countermax, show next image
    const int TICK = 250; // how often on_timeout is called
    int countermax = 8; // TICK * countermax is slideshow delay

    static bool slideshow = false; // slideshow mode active
    static bool deleteokay = false; // if enabled, delete files on disk
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
            stdout.printf("show_image() called with null pointer.\n");
            Gtk.main_quit();
        }
        try
        {
            string filename = iter.get();
            Gdk.Pixbuf pixbuf =
                new Pixbuf.from_file_at_size(filename, width, height);
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

    bool prev_path(bool again=true)
    {
        string path = null;
        string filename = iter.get();
        string firstfile = filename; // used to check for loop

        if(filename == null)
          return false;
        path = Path.get_dirname(filename);
        do
        {
            iter.prev();
            if(iter.get() == filename) // only one image in list (or repeated img)
                return false;
            filename = iter.get();
        } while(Path.get_dirname(filename) == path && firstfile != filename);
        if(firstfile == filename) { // only one path, goto start
            iter.first();
            counter = 0;
            show_image();
            return true;
        }
        if(again) {
          prev_path(false);
          iter.next();
          counter = 0;
          show_image();
          return true;
        }
        return false;
    }

    bool next_path()
    {
        string path = null;
        string filename = iter.get();
        string firstfile = filename; // used to check for loop

        if(filename == null)
            return false;
        path = Path.get_dirname(filename);
        do
        {
            iter.next();
            if(iter.get() == filename) // only one image in list (or repeated img)
                return false;
            filename = iter.get();
        } while(Path.get_dirname(filename) == path && firstfile != filename);
        counter = 0;
        show_image();
        return true;
    }

    bool delete_path() {
        string path = null;
        string filename = iter.get();
        string firstfilename = filename;

        if(filename == null)
            return false;
        path = Path.get_dirname(filename);

        if(verbose)
            stdout.printf("Tagged for deletion: %s\n", path);

        // find first image in this path
        do {
            iter.prev();
            filename = iter.get();
        } while(firstfilename != filename && path == Path.get_dirname(filename));

        // we are now at the previous path, go forward one
        iter.next();
        assert (Path.get_dirname(iter.get()) == path);

        filename = iter.get();
        while(filename != null && Path.get_dirname(filename) == path) {
            deletelist.append(filename);
            iter.delete();
            filename = iter.get();
        }

        counter = 0;
        show_image();
        return true;
    }

    // once working, this will tag a file for deletion
    void delete_image() {
        string filename = iter.get();
        if(null == filename)
            return;
        if(verbose)
            stdout.printf("Tagged for deletion: %s\n", filename);
        deletelist.append(filename);
        iter.delete();
        counter = 0;
        show_image();
        return;
    }

    void handle_deletelist() {
        string path = null;
        string lastpath = null;
        foreach(string filename in deletelist) {
            if(deleteokay) {
                FileUtils.unlink(filename);
            } else {
                stdout.printf("rm \"%s\"\n", filename);
            }
            path = Path.get_dirname(filename);
            if(path != lastpath && lastpath != null) {
                FileUtils.remove(lastpath); // try to remove directory, ignore errors
            }
        }
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
                main_iteration(); // will iconify if another event is queued?
                handle_deletelist();
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
            main_iteration();
            handle_deletelist();
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
        else if((e.keyval == 0x64 || e.keyval == 0xffff) // d or delete key
                && (e.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            // control-d
            delete_path();
        }
        else if(e.keyval == 0x64 || e.keyval == 0xffff) { // d or delete key
            delete_image();
        }
        else if(e.str == "/" || e.str == "?") {
            stdout.printf("%s\n", iter.get());
        }
        return true;
    } // on_keypress

    /*
     * Handle walking directories, and matching specific filenames
     */

    public static int get_last_int_in_string(string s)
    {
        int last, first;
        for(last=(int)s.length-1; last >= 0 && !s[last].isdigit(); last -= 1)
            ;
        last += 1;
        if(last <= 0)
            return -1;
        for(first=last-1; first >= 0 && s[first].isdigit(); first -= 1)
            ;
        first += 1;
        return s.substring(first, last-first).to_int();
    }


    public static int ImageSorter (string va, string vb) {
        string a = Path.get_basename(va);
        string b = Path.get_basename(vb);

        int na = get_last_int_in_string(a);
        int nb = get_last_int_in_string(b);
        if(na == -1 || nb == -1) {
            if(a > b) return 1;
            if(a== b) return 0;
            return 0;
        }
        if(na == nb)
            return 0;
        if(na > nb)
            return 1;
        return -1;
    }

    private delegate bool matcher(string s);

    private static void resultwalker(string dir, matcher m, ref GLib.List<string> result) {
        try {
            Dir d = Dir.open(dir);
            string[] dirlist = new string[64];
            int dirlen = 0;
            string s = null;
            var filenames = new GLib.List<string> ();
            while((s = d.read_name()) != null) {
                if(s == ".." || s == ".")
                    continue;
                string fs = Path.build_filename(dir, s);
                if(FileUtils.test(fs, FileTest.IS_DIR)) {
                    if(dirlen >= dirlist.length)
                        dirlist.resize(dirlist.length + 64);
                    dirlist[dirlen] = fs;
                    dirlen++;
                } else if(FileUtils.test(fs, FileTest.IS_REGULAR)) {
                    if(m(fs))
                        filenames.insert_sorted(fs, (GLib.CompareFunc)ImageSorter);
                }
            }
            foreach(string fn in filenames) {
                result.append(fn);
            }
            dirlist.resize(dirlen);
            if(random) {
                for(int i=0; i<dirlen; i++) {
                    string tmp = dirlist[i];
                    int ran = GLib.Random.int_range(0, dirlen);
                    dirlist[i] = dirlist[ran];
                    dirlist[ran] = tmp;
                }
            }
            foreach(string dd in dirlist) {
                resultwalker(dd, m, ref result);
            }
        } catch(GLib.FileError e) { 
        }
    }

    const OptionEntry[] options = {
        { "verbose", 'v', 0, OptionArg.NONE, ref verbose, "Be verbose", null },
        { "delete", 'd', 0, OptionArg.NONE, ref deleteokay, "Enable delete functionality.", null },
        { "slideshow", 's', 0, OptionArg.NONE, ref slideshow, "Start in slideshow mode", null },
#if !MAEMO
        { "touchscreen", 't', 0, OptionArg.NONE, ref touch, "Enable touchscreen/clicking interface", null },
#endif
        { "random", 'r', 0, OptionArg.NONE, ref random, "Randomise the order of sub-directories of images", null },
        { null }
    };

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
  d              delete current image (or print to stdout if -d not given)
  ctrl-d         delete all images in current images path (or print as above)
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

        GLib.List<string> *imgs = (GLib.List<string>)new GLib.List<string> ();

        for(int arg=1; arg<args.length; arg++) {
            if(FileUtils.test(args[arg], FileTest.IS_DIR)) {
                resultwalker(args[arg], (a) =>
                {
                    string tmp = a.down();
                    return tmp.has_suffix(".jpg") || tmp.has_suffix(".jpeg");
                }, ref imgs);
            } else if(FileUtils.test(args[arg], FileTest.IS_REGULAR)) {
                string tmp = args[arg].down();
                if(tmp.has_suffix(".jpg") || tmp.has_suffix(".jpeg"))
                    imgs->append(args[arg]);
            }
        }
        browser.iter = new CircularIter<string>((owned)imgs);
        browser.show_image();
        browser.show_all();
        Gtk.main();
        return 0;
    } // main

} // class Browser
