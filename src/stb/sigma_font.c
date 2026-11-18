// The system's fonts for TEXT on Linux (SYSTEM-FONT), behind src/host_font.zig.
//
// Linux has no drawing of text of its own, and the executables Sigma gives out load
// no shared library, so stb_truetype (in this folder, with its own license) reads the
// font file and draws the glyphs. No font is part of Sigma: the file is looked for by
// the font's name under the folders the system keeps its fonts in, or is the path the
// program gives.
//
// stb_truetype does not check the offsets in a font file. What this file reads itself
// (the collection's header and the name table) is checked against the file's length.

#include <dirent.h>
#include <fcntl.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define STBTT_STATIC
#define STBTT_assert(x) ((void)0)
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

enum { max_line_height = 256, max_box_width = 512, max_depth = 6, max_path = 1024, max_name = 256 };

typedef struct {
    const unsigned char *data;
    size_t length;
} File;

static unsigned be16(const unsigned char *p) { return (unsigned)p[0] << 8 | p[1]; }
static unsigned long be32(const unsigned char *p) {
    return (unsigned long)p[0] << 24 | (unsigned long)p[1] << 16 | (unsigned long)p[2] << 8 | p[3];
}

static int openFile(const char *path, File *file) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    struct stat status;
    if (fstat(fd, &status) != 0 || !S_ISREG(status.st_mode) || status.st_size < 12) {
        close(fd);
        return 0;
    }
    void *data = mmap(NULL, (size_t)status.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (data == MAP_FAILED) return 0;
    file->data = data;
    file->length = (size_t)status.st_size;
    return 1;
}

static void closeFile(File *file) {
    if (file->data) munmap((void *)file->data, file->length);
    file->data = NULL;
    file->length = 0;
}

// The number of fonts in the file (a collection has several), 0 when it is no font.
static unsigned faceCount(const File *file) {
    const unsigned char *d = file->data;
    if (memcmp(d, "ttcf", 4) == 0) {
        unsigned long count = be32(d + 8);
        if (count > 4096 || 12 + 4 * count > file->length) return 0;
        return (unsigned)count;
    }
    if (memcmp(d, "\0\1\0\0", 4) == 0 || memcmp(d, "OTTO", 4) == 0 || memcmp(d, "true", 4) == 0) return 1;
    return 0;
}

static unsigned long faceOffset(const File *file, unsigned index) {
    if (memcmp(file->data, "ttcf", 4) != 0) return 0;
    return be32(file->data + 12 + 4 * (size_t)index);
}

// The name table of the font that starts at `start`: false when the file has none
// inside its length.
static int nameTable(const File *file, unsigned long start, unsigned long *offset, unsigned long *length) {
    if (start > file->length || file->length - start < 12) return 0;
    const unsigned char *d = file->data + start;
    unsigned tables = be16(d + 4);
    if (12 + 16 * (size_t)tables > file->length - start) return 0;
    for (unsigned i = 0; i < tables; i += 1) {
        const unsigned char *entry = d + 12 + 16 * (size_t)i;
        if (memcmp(entry, "name", 4) != 0) continue;
        *offset = be32(entry + 8);
        *length = be32(entry + 12);
        return *offset <= file->length && *length <= file->length - *offset && *length >= 6;
    }
    return 0;
}

// A name of the table as UTF-8: the Unicode and Windows names are UTF-16, big end
// first; the old Macintosh names are taken only when they are ASCII.
static size_t nameText(unsigned platform, const unsigned char *text, unsigned length, char *out, size_t room) {
    size_t n = 0;
    if (platform == 1) {
        if (length > room) return 0;
        for (unsigned i = 0; i < length; i += 1) {
            if (text[i] >= 0x80) return 0;
            out[n++] = (char)text[i];
        }
        return n;
    }
    if (platform != 0 && platform != 3) return 0;
    for (unsigned i = 0; i + 1 < length; i += 2) {
        unsigned long code = be16(text + i);
        if (code >= 0xD800 && code < 0xDC00 && i + 3 < length) {
            unsigned low = be16(text + i + 2);
            if (low >= 0xDC00 && low < 0xE000) {
                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                i += 2;
            }
        }
        if (n + 4 > room) return 0;
        if (code < 0x80) {
            out[n++] = (char)code;
        } else if (code < 0x800) {
            out[n++] = (char)(0xC0 | code >> 6);
            out[n++] = (char)(0x80 | (code & 0x3F));
        } else if (code < 0x10000) {
            out[n++] = (char)(0xE0 | code >> 12);
            out[n++] = (char)(0x80 | (code >> 6 & 0x3F));
            out[n++] = (char)(0x80 | (code & 0x3F));
        } else {
            out[n++] = (char)(0xF0 | code >> 18);
            out[n++] = (char)(0x80 | (code >> 12 & 0x3F));
            out[n++] = (char)(0x80 | (code >> 6 & 0x3F));
            out[n++] = (char)(0x80 | (code & 0x3F));
        }
    }
    return n;
}

// The same text, the ASCII letters without regard to their case.
static int sameText(const char *a, size_t a_length, const char *b, size_t b_length) {
    if (a_length != b_length) return 0;
    for (size_t i = 0; i < a_length; i += 1) {
        unsigned char x = (unsigned char)a[i], y = (unsigned char)b[i];
        if (x >= 'A' && x <= 'Z') x += 'a' - 'A';
        if (y >= 'A' && y <= 'Z') y += 'a' - 'A';
        if (x != y) return 0;
    }
    return 1;
}

// How well the font is the one the name asks for: 3 when the name is its full or
// PostScript name, 2 when it is its family and the font is the regular one, 1 when it
// is its family, 0 when it is none of the font's names (in any language).
static int faceScore(const File *file, unsigned long start, const char *name, size_t name_length) {
    unsigned long offset, length;
    if (!nameTable(file, start, &offset, &length)) return 0;
    const unsigned char *table = file->data + offset;
    unsigned count = be16(table + 2);
    unsigned long strings = be16(table + 4);
    if (6 + 12 * (unsigned long)count > length || strings > length) return 0;
    int family = 0, exact = 0, regular = 0;
    char text[max_name];
    for (unsigned i = 0; i < count; i += 1) {
        const unsigned char *record = table + 6 + 12 * (size_t)i;
        unsigned id = be16(record + 6);
        if (id != 1 && id != 2 && id != 4 && id != 6 && id != 16) continue;
        unsigned text_length = be16(record + 8);
        unsigned long text_offset = strings + be16(record + 10);
        if (text_offset > length || text_length > length - text_offset) continue;
        size_t n = nameText(be16(record), table + text_offset, text_length, text, sizeof text);
        if (n == 0) continue;
        if (id == 2) {
            // DejaVu calls its regular font Book, the URW fonts Roman.
            if (sameText(text, n, "Regular", 7) || sameText(text, n, "Book", 4) || sameText(text, n, "Roman", 5) ||
                sameText(text, n, "Normal", 6)) regular = 1;
        } else if (sameText(text, n, name, name_length)) {
            if (id == 4 || id == 6) exact = 1; else family = 1;
        }
    }
    if (exact) return 3;
    if (family) return regular ? 2 : 1;
    return 0;
}

typedef struct {
    const char *name;
    size_t name_length;
    int score;
    char path[max_path];
    unsigned long start;
} Search;

static int fontFileName(const char *name) {
    size_t n = strlen(name);
    if (n < 5 || name[n - 4] != '.') return 0;
    return sameText(name + n - 3, 3, "ttf", 3) || sameText(name + n - 3, 3, "otf", 3) ||
        sameText(name + n - 3, 3, "ttc", 3) || sameText(name + n - 3, 3, "otc", 3);
}

static void searchFile(Search *search, const char *path) {
    File file = {0};
    if (!openFile(path, &file)) return;
    unsigned faces = faceCount(&file);
    for (unsigned i = 0; i < faces; i += 1) {
        unsigned long start = faceOffset(&file, i);
        int score = faceScore(&file, start, search->name, search->name_length);
        // Of the fonts that fit as well, the one whose path comes first is taken, so
        // that the choice does not depend on the order the folder gives its files in.
        if (score > search->score || (score != 0 && score == search->score && strcmp(path, search->path) < 0)) {
            search->score = score;
            search->start = start;
            strcpy(search->path, path);
        }
    }
    closeFile(&file);
}

static void searchFolder(Search *search, const char *folder, int depth) {
    DIR *dir = opendir(folder);
    if (!dir) return;
    struct dirent *entry;
    char path[max_path];
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        size_t n = strlen(folder), m = strlen(entry->d_name);
        if (n + 1 + m + 1 > sizeof path) continue;
        memcpy(path, folder, n);
        path[n] = '/';
        memcpy(path + n + 1, entry->d_name, m + 1);
        struct stat status;
        if (stat(path, &status) != 0) continue;
        if (S_ISDIR(status.st_mode)) {
            if (depth < max_depth) searchFolder(search, path, depth + 1);
        } else if (S_ISREG(status.st_mode) && fontFileName(entry->d_name)) {
            searchFile(search, path);
        }
    }
    closedir(dir);
}

static void searchUnder(Search *search, const char *base, const char *rest) {
    char path[max_path];
    size_t n = strlen(base), m = strlen(rest);
    if (n == 0 || n + m + 1 > sizeof path) return;
    memcpy(path, base, n);
    memcpy(path + n, rest, m + 1);
    searchFolder(search, path, 0);
}

// The font TEXT draws with now.
static File current;
static stbtt_fontinfo font;
static int chosen;
static float scale;
static int baseline;
static unsigned line_height;

// The name the last search was for and what it found, so that the same font in another
// height is not looked for again.
static char found_name[max_name];
static size_t found_name_length;
static char found_path[max_path];
static unsigned long found_start;

// 1: the font is chosen. 0: the system has no font of the name (or the file at the
// path is no font). The font chosen before stays when the result is 0.
int sigma_font_select(const char *name, size_t name_length, unsigned height) {
    if (name_length == 0 || name_length >= max_name || height == 0) return 0;
    char path[max_path];
    unsigned long start = 0;
    if (memchr(name, '/', name_length) != NULL) {
        // A path: the first font of the file.
        if (name_length >= sizeof path || memchr(name, 0, name_length) != NULL) return 0;
        memcpy(path, name, name_length);
        path[name_length] = 0;
    } else if (found_name_length == name_length && memcmp(found_name, name, name_length) == 0) {
        strcpy(path, found_path);
        start = found_start;
    } else {
        Search search = { .name = name, .name_length = name_length };
        searchFolder(&search, "/usr/share/fonts", 0);
        searchFolder(&search, "/usr/local/share/fonts", 0);
        const char *home = getenv("HOME");
        const char *data = getenv("XDG_DATA_HOME");
        if (data && data[0]) searchUnder(&search, data, "/fonts");
        else if (home) searchUnder(&search, home, "/.local/share/fonts");
        if (home) searchUnder(&search, home, "/.fonts");
        if (search.score == 0) return 0;
        strcpy(path, search.path);
        start = search.start;
        memcpy(found_name, name, name_length);
        found_name_length = name_length;
        strcpy(found_path, path);
        found_start = start;
    }
    File file = {0};
    if (!openFile(path, &file)) return 0;
    stbtt_fontinfo info;
    if (faceCount(&file) == 0 || (start == 0 && memcmp(file.data, "ttcf", 4) == 0 && (start = faceOffset(&file, 0)) == 0) ||
        start >= file.length || !stbtt_InitFont(&info, file.data, (int)start)) {
        closeFile(&file);
        return 0;
    }
    int ascent, descent, gap;
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &gap);
    if (ascent - descent <= 0) {
        closeFile(&file);
        return 0;
    }
    // Some CFF faces (URW C059, for example) put Latin accents above their
    // hhea ascent. Using hhea alone silently clips those outlines. Measure a
    // small, stable Latin reference set, rather than the face-wide bbox whose
    // exceptional glyphs can make ordinary Latin/CJK text much too small.
    int measured_ascent = ascent, measured_descent = descent;
    for (unsigned code = 0xC0; code <= 0xFF; code += 1) {
        int index = stbtt_FindGlyphIndex(&info, (int)code);
        int x0, y0, x1, y1;
        if (index && stbtt_GetGlyphBox(&info, index, &x0, &y0, &x1, &y1)) {
            if (y1 > measured_ascent) measured_ascent = y1;
            if (y0 < measured_descent) measured_descent = y0;
        }
    }
    // Do not let an anomalous reference outline dominate the size of a face.
    if ((long)measured_ascent - measured_descent <= ((long)ascent - descent) * 3 / 2) {
        ascent = measured_ascent;
        descent = measured_descent;
    }
    closeFile(&current);
    current = file;
    font = info;
    chosen = 1;
    line_height = height < max_line_height ? height : max_line_height;
    // The corrected reference ascent and descent together take `height` pixels.
    scale = (float)line_height / (float)(ascent - descent);
    baseline = (int)lroundf((float)ascent * scale);
    return 1;
}

// Draws one character: its coverage in `alpha`, row after row of out[2] bytes.
// out: the advance, the box's left edge from the pen, its width, its height.
// 0 when no font is chosen, the font has no glyph for the character, or the buffer
// is too small.
int sigma_font_glyph(unsigned code, unsigned char *alpha, size_t alpha_length, unsigned max_width, int out[4]) {
    if (!chosen) return 0;
    int glyph = stbtt_FindGlyphIndex(&font, (int)code);
    if (glyph == 0) return 0;
    int advance_units, bearing;
    stbtt_GetGlyphHMetrics(&font, glyph, &advance_units, &bearing);
    float advance = (float)advance_units * scale;
    // Room on both sides for strokes past the advance (italics, accents).
    unsigned height = line_height;
    unsigned margin = height / 2;
    unsigned width = (unsigned)(advance > 0 ? ceilf(advance) : 0) + 2 * margin;
    if (width > max_width) width = max_width;
    if (width > max_box_width) width = max_box_width;
    if (alpha_length < (size_t)width * height) return 0;
    memset(alpha, 0, (size_t)width * height);
    int x0, y0, x1, y1;
    stbtt_GetGlyphBitmapBox(&font, glyph, scale, scale, &x0, &y0, &x1, &y1);
    int glyph_width = x1 - x0, glyph_height = y1 - y0;
    if (glyph_width > 0 && glyph_height > 0 && glyph_width <= 4096 && glyph_height <= 4096) {
        unsigned char *drawn = calloc((size_t)glyph_width, (size_t)glyph_height);
        if (!drawn) return 0;
        stbtt_MakeGlyphBitmap(&font, drawn, glyph_width, glyph_height, glyph_width, scale, scale, glyph);
        for (int row = 0; row < glyph_height; row += 1) {
            int y = baseline + y0 + row;
            if (y < 0 || y >= (int)height) continue;
            for (int column = 0; column < glyph_width; column += 1) {
                int x = (int)margin + x0 + column;
                if (x < 0 || x >= (int)width) continue;
                alpha[(size_t)y * width + (size_t)x] = drawn[(size_t)row * (size_t)glyph_width + (size_t)column];
            }
        }
        free(drawn);
    }
    out[0] = (int)lroundf(advance);
    out[1] = -(int)margin;
    out[2] = (int)width;
    out[3] = (int)height;
    return 1;
}
