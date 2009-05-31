/*
 * This wraps just enough of libarchive1 to serve our purposes.
 */
using GLib;

namespace Archive {

    [SimpleType]
    [CCode (cheader_filename="archive.h", ref_function="", unref_function="", free_function="archive_read_finish", cname="struct archive", cprefix="archive_read_")]
    public class Read
    {
        [CCode (cname="archive_read_new")]
        public Read();
        public int support_format_all();
        public int support_compression_all();
      
        public int open_filename(string filename, int blocksize=8192);
        public int next_header(Entry* entry);
      
        public ssize_t data(uchar[] buf);
        public int close();
    }

    [SimpleType]
    [CCode (cheader_filename="archive_entry.h", unref_function="", free_function="", cname="struct archive_entry", cprefix="archive_entry_")]
    public class Entry {
        public unowned string pathname();
    }
    
}
