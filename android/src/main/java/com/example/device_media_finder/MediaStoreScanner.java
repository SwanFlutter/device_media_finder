package com.example.device_media_finder;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Environment;
import android.provider.MediaStore;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

class MediaStoreScanner {

    enum Type { IMAGE, VIDEO, AUDIO, DOCUMENT, ARCHIVE, ANY }

    private final Context context;
    private final Uri filesUri;

    MediaStoreScanner(Context context) {
        this.context = context;
        this.filesUri = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                ? MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
                : MediaStore.Files.getContentUri("external");
    }

    private String[] projection() {
        List<String> base = new ArrayList<>(Arrays.asList(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.MIME_TYPE,
                MediaStore.Files.FileColumns.MEDIA_TYPE,
                MediaStore.Files.FileColumns.DATA));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            base.add(MediaStore.Files.FileColumns.WIDTH);
            base.add(MediaStore.Files.FileColumns.HEIGHT);
            base.add(MediaStore.Files.FileColumns.DURATION);
        }
        return base.toArray(new String[0]);
    }

    /** Selection clause + bound arguments. */
    private static final class Selection {
        final String where;
        final String[] args;
        Selection(String where, String[] args) {
            this.where = where;
            this.args = args;
        }
    }

    private static final class DirEntry {
        final File dir;
        final int depth;
        DirEntry(File dir, int depth) {
            this.dir = dir;
            this.depth = depth;
        }
    }

    // ─── Public API ───────────────────────────────────────────────────────

    /** Real SQL-level pagination — nothing beyond the page is loaded into memory. */
    List<Map<String, Object>> queryPage(Type type, List<String> extensions,
                                         int offset, int limit, CancellationSignal signal) {
        if (needsFsScan(type, extensions)) {
            // MediaStore does not index archives / custom formats on many OEM
            // devices, so merge a file-system scan with whatever the DB returns.
            List<Map<String, Object>> merged = mergedRows(type, extensions, signal);
            if (offset >= merged.size()) return new ArrayList<>();
            return new ArrayList<>(merged.subList(offset, Math.min(offset + limit, merged.size())));
        }

        Selection sel = buildSelection(type, extensions);
        String sort = MediaStore.Files.FileColumns.DATE_MODIFIED + " DESC";
        Cursor c = runQuery(sel.where, sel.args, sort, limit, offset, signal);
        if (c == null) return new ArrayList<>();
        try {
            return cursorToRows(c);
        } finally {
            c.close();
        }
    }

    int count(Type type, List<String> extensions, CancellationSignal signal) {
        if (needsFsScan(type, extensions)) {
            return mergedRows(type, extensions, signal).size();
        }
        Selection sel = buildSelection(type, extensions);
        Cursor c = context.getContentResolver().query(
                filesUri,
                new String[]{MediaStore.Files.FileColumns._ID},
                sel.where, sel.args, null, signal);
        if (c == null) return 0;
        try {
            return c.getCount();
        } finally {
            c.close();
        }
    }

    // ─── Query execution ──────────────────────────────────────────────────

    private Cursor runQuery(String selection, String[] args, String sort,
                            int limit, int offset, CancellationSignal signal) {
        ContentResolver cr = context.getContentResolver();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Bundle bundle = new Bundle();
            bundle.putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection);
            bundle.putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args);
            bundle.putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, sort);
            bundle.putInt(ContentResolver.QUERY_ARG_LIMIT, limit);
            bundle.putInt(ContentResolver.QUERY_ARG_OFFSET, offset);
            return cr.query(filesUri, projection(), bundle, signal);
        }
        return cr.query(filesUri, projection(), selection, args,
                sort + " LIMIT " + limit + " OFFSET " + offset, signal);
    }

    // ─── Selection builder ────────────────────────────────────────────────

    private Selection buildSelection(Type type, List<String> extensions) {
        final String colType = MediaStore.Files.FileColumns.MEDIA_TYPE;
        final String colMime = MediaStore.Files.FileColumns.MIME_TYPE;
        final String colName = MediaStore.Files.FileColumns.DISPLAY_NAME;
        final String imageT = String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE);
        final String videoT = String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO);
        final String audioT = String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO);
        StringBuilder where = new StringBuilder();
        List<String> args = new ArrayList<>();

        switch (type) {
            case IMAGE:
                where.append(colType).append(" = ?");
                args.add(imageT);
                break;
            case VIDEO:
                where.append(colType).append(" = ?");
                args.add(videoT);
                break;
            case AUDIO:
                where.append(colType).append(" = ?");
                args.add(audioT);
                break;
            case DOCUMENT: {
                List<String> callerExts = distinctExts(extensions, 300);
                if (callerExts.isEmpty()) {
                    // Built-in MIME whitelist + name-LIKE fallback (MediaStore
                    // often stores NULL mime for zips/archives) and block media rows.
                    where.append("(").append(colMime).append(" IN (")
                            .append(placeholders(DOCUMENT_MIMES.size())).append(")");
                    args.addAll(DOCUMENT_MIMES);
                    for (String ext : DOCUMENT_FALLBACK_EXTS) {
                        where.append(" OR ").append(colName).append(" LIKE ?");
                        args.add("%." + ext);
                    }
                    where.append(")");
                } else {
                    buildExtensionFilter(callerExts, colMime, colName, where, args);
                }
                where.append(" AND ").append(colType).append(" NOT IN (?,?,?)");
                args.add(imageT);
                args.add(videoT);
                args.add(audioT);
                break;
            }
            case ARCHIVE: {
                Set<String> targets = extensions.isEmpty()
                        ? ARCHIVE_EXTS
                        : new LinkedHashSet<>(normalizedExts(extensions));
                List<String> likeParts = new ArrayList<>();
                List<String> msArgs = new ArrayList<>();
                LinkedHashSet<String> mimeSet = new LinkedHashSet<>();
                MimeTypeMap mimeMap = MimeTypeMap.getSingleton();
                for (String ext : targets) {
                    likeParts.add(colName + " LIKE ?");
                    msArgs.add("%." + ext);
                    String mt = mimeMap.getMimeTypeFromExtension(ext);
                    if (mt != null) mimeSet.add(mt);
                }
                if (!mimeSet.isEmpty()) {
                    likeParts.add(colMime + " IN (" + placeholders(mimeSet.size()) + ")");
                    msArgs.addAll(mimeSet);
                }
                where.append("(").append(join(likeParts, " OR ")).append(")");
                args.addAll(msArgs);
                break;
            }
            case ANY:
            default: {
                List<String> callerExts = distinctExts(extensions, 300);
                if (callerExts.isEmpty()) {
                    where.append("1=1");
                } else {
                    buildExtensionFilter(callerExts, colMime, colName, where, args);
                }
                break;
            }
        }

        // Exclude zero-byte files and directory entries.
        where.append(" AND ").append(MediaStore.Files.FileColumns.SIZE).append(" > 0");
        return new Selection(where.toString(), args.toArray(new String[0]));
    }

    /**
     * Builds MIME IN (…) or DISPLAY_NAME LIKE '%.ext' clauses. Extensions in
     * {@link #ALWAYS_LIKE_EXTS} (source code, configs, …) or those without a
     * system MIME mapping are always matched via LIKE, to avoid the MIME
     * database mapping them to unexpected types on some devices. Extensions that
     * do have a MIME mapping get BOTH a {@code mime IN (...)} term and a
     * {@code name LIKE '%.ext'} term, because MediaStore frequently stores a
     * NULL or vendor-specific MIME which would otherwise hide the file.
     */
    private void buildExtensionFilter(List<String> exts, String mimeCol, String nameCol,
                                      StringBuilder where, List<String> args) {
        MimeTypeMap mimeMap = MimeTypeMap.getSingleton();
        List<String> parts = new ArrayList<>();

        Set<String> likeExts = new HashSet<>();
        for (String ext : exts) {
            if (ALWAYS_LIKE_EXTS.contains(ext) || mimeMap.getMimeTypeFromExtension(ext) == null) {
                likeExts.add(ext);
            }
        }
        List<String> mimes = new ArrayList<>();
        LinkedHashSet<String> mimeSeen = new LinkedHashSet<>();
        for (String ext : exts) {
            if (likeExts.contains(ext)) continue;
            String mt = mimeMap.getMimeTypeFromExtension(ext);
            if (mt != null && mimeSeen.add(mt)) mimes.add(mt);
        }
        if (!mimes.isEmpty()) {
            parts.add(mimeCol + " IN (" + placeholders(mimes.size()) + ")");
            args.addAll(mimes);
        }
        // Always match by extension name too so files with a missing/wrong MIME
        // (common for zip/rar/7z and any custom format) still show up.
        for (String ext : exts) {
            parts.add(nameCol + " LIKE ?");
            args.add("%." + ext);
        }
        if (!parts.isEmpty()) {
            where.append("(").append(join(parts, " OR ")).append(")");
        } else {
            where.append("1=1");
        }
    }

    // ─── File-system fallback ─────────────────────────────────────────────

    /**
     * MediaStore only indexes files in well-known locations on many OEM ROMs
     * (and prunes archives / custom formats entirely on some Android 13+
     * devices), so a Documents / custom-extension query can silently miss files
     * that exist on disk. For those cases we merge a bounded file-system walk.
     */
    private boolean needsFsScan(Type type, List<String> extensions) {
        switch (type) {
            case DOCUMENT:
            case ARCHIVE:
                return true;
            case ANY:
                return !normalizedExts(extensions).isEmpty();
            default:
                return false;
        }
    }

    private List<Map<String, Object>> mergedRows(Type type, List<String> extensions,
                                                 CancellationSignal signal) {
        Selection sel = buildSelection(type, extensions);
        List<Map<String, Object>> rows = new ArrayList<>();

        // If the MediaStore half fails on an OEM ROM, still return the FS scan.
        try {
            Cursor c = runQuery(sel.where, sel.args,
                    MediaStore.Files.FileColumns.DATE_MODIFIED + " DESC",
                    Integer.MAX_VALUE, 0, signal);
            if (c != null) {
                try {
                    rows.addAll(cursorToRows(c));
                } finally {
                    c.close();
                }
            }
        } catch (Throwable ignored) {
        }

        List<String> exts = normalizedExts(extensions);
        Set<String> fsExts;
        if (!exts.isEmpty()) {
            fsExts = new LinkedHashSet<>(exts);
        } else if (type == Type.DOCUMENT) {
            fsExts = new LinkedHashSet<>(DOCUMENT_FALLBACK_EXTS);
        } else if (type == Type.ARCHIVE) {
            fsExts = ARCHIVE_EXTS;
        } else {
            fsExts = new HashSet<>();
        }

        if (!fsExts.isEmpty()) {
            // A file may be indexed by MediaStore *and* found by the walk.
            // Register every MediaStore row under both its real path and its
            // name|size key so the FS pass never adds a duplicate.
            HashSet<String> seen = new HashSet<>(rows.size() * 2 + 256);
            for (Map<String, Object> row : rows) {
                Object p = row.get("path");
                if (p instanceof String) seen.add((String) p);
                seen.add(row.get("name") + "|" + row.get("size"));
            }
            for (File f : fsCandidates(fsExts, type == Type.DOCUMENT)) {
                String name = f.getName();
                if (seen.contains(name)) continue;
                if (!seen.add(f.getAbsolutePath())) continue;
                seen.add(name + "|" + f.length());
                String ext = extLower(name);
                String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
                long negId = -((long) System.identityHashCode(f) & 0x7FFFFFFFL);
                rows.add(mediaRow(
                        negId,
                        Uri.fromFile(f).toString(),
                        name,
                        f.length(),
                        f.lastModified(),
                        mime,
                        MediaStore.Files.FileColumns.MEDIA_TYPE_NONE,
                        f.getAbsolutePath(),
                        0, 0, 0L));
            }
            rows.sort((a, b) -> Long.compare(
                    ((Number) b.get("dateModified")).longValue(),
                    ((Number) a.get("dateModified")).longValue()));
        }
        return rows;
    }

    /**
     * Depth-bounded walk over every accessible external-storage volume. Skips
     * dot-dirs, private Android/{data,obb} trees and caps total files so a
     * pathological SD-card can never lock the query.
     */
    private List<File> fsCandidates(Set<String> exts, boolean excludeMedia) {
        List<File> out = new ArrayList<>();
        LinkedHashSet<String> roots = new LinkedHashSet<>();
        try {
            File ext = Environment.getExternalStorageDirectory();
            if (ext != null) roots.add(ext.getAbsolutePath());
        } catch (Throwable ignored) {
        }
        try {
            for (File d : context.getExternalFilesDirs(null)) {
                if (d == null) continue;
                String ap = d.getAbsolutePath();
                int i = ap.lastIndexOf("/Android/");
                roots.add(i >= 0 ? ap.substring(0, i) : ap);
            }
        } catch (Throwable ignored) {
        }

        MimeTypeMap mimeMap = MimeTypeMap.getSingleton();
        ArrayDeque<DirEntry> stack = new ArrayDeque<>();
        for (String r : roots) stack.add(new DirEntry(new File(r), 0));
        int budget = 60_000;
        while (!stack.isEmpty() && out.size() < 5_000) {
            DirEntry entry = stack.removeLast();
            File dir = entry.dir;
            int depth = entry.depth;
            if (depth > MAX_FS_DEPTH) continue;
            File[] children;
            try {
                children = dir.listFiles();
            } catch (Throwable t) {
                children = null;
            }
            if (children == null) continue;
            for (File c : children) {
                if (--budget <= 0) return out;
                if (c.isDirectory()) {
                    String n = c.getName();
                    if (n.startsWith(".")
                            || (depth == 0 && n.equals("Android"))
                            || (n.equals("data") && dir.getName().equals("Android"))
                            || (n.equals("obb") && dir.getName().equals("Android"))) {
                        continue;
                    }
                    stack.add(new DirEntry(c, depth + 1));
                } else {
                    String ext = extLower(c.getName());
                    if (!exts.contains(ext)) continue;
                    if (c.length() <= 0L) continue;
                    if (excludeMedia) {
                        String mime = mimeMap.getMimeTypeFromExtension(ext);
                        if (mime != null && (mime.startsWith("image/")
                                || mime.startsWith("video/") || mime.startsWith("audio/"))) {
                            continue;
                        }
                    }
                    out.add(c);
                }
            }
        }
        return out;
    }

    // ─── Cursor mapping ───────────────────────────────────────────────────

    private List<Map<String, Object>> cursorToRows(Cursor c) {
        List<Map<String, Object>> out = new ArrayList<>(c.getCount());
        int idIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID);
        int nameIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME);
        int sizeIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE);
        int dateIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED);
        int mimeIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE);
        int mediaIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE);
        int dataIdx = c.getColumnIndex(MediaStore.Files.FileColumns.DATA);
        int wIdx = c.getColumnIndex("width");
        int hIdx = c.getColumnIndex("height");
        int dIdx = c.getColumnIndex("duration");

        while (c.moveToNext()) {
            long id = c.getLong(idIdx);
            int mediaType = c.getInt(mediaIdx);
            String uri = buildMediaUri(id, mediaType);

            // Prefer MediaStore DISPLAY_NAME; fall back to the URI's last path
            // segment so the UI never shows a blank filename.
            String rawName = getStringOrNull(c, nameIdx);
            String name;
            if (rawName != null && !rawName.trim().isEmpty()) {
                name = rawName;
            } else {
                String seg = uri.substring(uri.lastIndexOf('/') + 1);
                String decoded = Uri.decode(seg);
                name = (decoded != null && !decoded.trim().isEmpty()) ? decoded : "";
            }

            out.add(mediaRow(
                    id, uri, name,
                    c.getLong(sizeIdx),
                    c.getLong(dateIdx) * 1000L,
                    getStringOrNull(c, mimeIdx),
                    mediaType,
                    dataIdx >= 0 ? getStringOrNull(c, dataIdx) : null,
                    wIdx >= 0 ? c.getInt(wIdx) : 0,
                    hIdx >= 0 ? c.getInt(hIdx) : 0,
                    dIdx >= 0 ? c.getLong(dIdx) : 0L));
        }
        return out;
    }

    private String buildMediaUri(long id, int mediaType) {
        Uri base;
        switch (mediaType) {
            case MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE:
                base = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                        ? MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                        : MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
                break;
            case MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO:
                base = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                        ? MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                        : MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
                break;
            case MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO:
                base = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                        ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                        : MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
                break;
            default:
                base = filesUri;
        }
        return Uri.withAppendedPath(base, String.valueOf(id)).toString();
    }

    private static Map<String, Object> mediaRow(long id, String uri, String name, long size,
                                                 long dateModified, String mimeType, int mediaType,
                                                 String path, int width, int height, long duration) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("uri", uri);
        m.put("name", name);
        m.put("size", size);
        m.put("dateModified", dateModified);
        m.put("mimeType", mimeType);
        m.put("mediaType", mediaType);
        m.put("path", path);
        m.put("width", width);
        m.put("height", height);
        m.put("duration", duration);
        return m;
    }

    // ─── Small utilities ──────────────────────────────────────────────────

    private static String getStringOrNull(Cursor c, int i) {
        return c.isNull(i) ? null : c.getString(i);
    }

    private static String extLower(String name) {
        int idx = name.lastIndexOf('.');
        return idx < 0 ? "" : name.substring(idx + 1).toLowerCase();
    }

    private static List<String> distinctExts(List<String> extensions, int max) {
        LinkedHashSet<String> set = new LinkedHashSet<>();
        for (String e : extensions) {
            String v = e.toLowerCase();
            if (v.startsWith(".")) v = v.substring(1);
            set.add(v);
            if (set.size() >= max) break;
        }
        return new ArrayList<>(set);
    }

    private static List<String> normalizedExts(List<String> extensions) {
        LinkedHashSet<String> set = new LinkedHashSet<>();
        for (String e : extensions) {
            String v = e.toLowerCase();
            if (v.startsWith(".")) v = v.substring(1);
            if (!v.isEmpty()) set.add(v);
        }
        return new ArrayList<>(set);
    }

    private static String placeholders(int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            if (i > 0) sb.append(",");
            sb.append("?");
        }
        return sb.toString();
    }

    private static String join(List<String> parts, String sep) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) sb.append(sep);
            sb.append(parts.get(i));
        }
        return sb.toString();
    }

    // ─── Constants ────────────────────────────────────────────────────────

    /** Maximum directory depth for the file-system fallback scan. */
    private static final int MAX_FS_DEPTH = 5;

    /**
     * MIME whitelist for {@link Type#DOCUMENT} when no caller extensions are
     * given. Deliberately omits image/video/audio MIME types so screenshots and
     * media files never bleed into the Documents tab.
     */
    private static final List<String> DOCUMENT_MIMES = Arrays.asList(
            "application/pdf", "application/msword",
            "application/vnd.ms-excel", "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.template",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.template",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/vnd.openxmlformats-officedocument.presentationml.slideshow",
            "application/vnd.openxmlformats-officedocument.presentationml.template",
            "application/vnd.oasis.opendocument.text",
            "application/vnd.oasis.opendocument.spreadsheet",
            "application/vnd.oasis.opendocument.presentation",
            "text/plain", "text/html", "text/csv", "text/xml", "application/xml",
            "application/json", "application/rtf", "text/rtf", "text/markdown",
            "application/epub+zip", "application/x-mobipocket-ebook",
            "application/x-fictionbook+xml",
            "application/zip", "application/x-zip-compressed",
            "application/x-rar-compressed", "application/vnd.rar",
            "application/x-7z-compressed", "application/x-tar", "application/gzip",
            "application/x-bzip2", "application/x-xz", "application/x-lzma",
            "application/x-sqlite3", "application/vnd.sqlite3",
            "application/vnd.android.package-archive",
            "application/x-msdownload", "application/vnd.microsoft.portable-executable",
            "application/x-dosexec", "application/x-ms-dos-executable",
            "application/x-msi", "application/vnd.ms-installer",
            "application/x-msix", "application/x-appx",
            "application/x-iso9660-image", "application/x-apple-diskimage",
            "application/x-vhd", "text/tab-separated-values", "application/xhtml+xml",
            "application/vnd.ms-access", "application/x-msaccess");

    /**
     * Extensions matched via DISPLAY_NAME LIKE when no caller extensions are
     * given, because MediaStore frequently stores NULL or a wrong MIME for
     * archives (zip, rar, 7z…) and ebook formats on many devices.
     */
    private static final List<String> DOCUMENT_FALLBACK_EXTS = Arrays.asList(
            "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "lzma", "zst",
            "apk", "xapk", "apks", "ipa",
            "exe", "msi", "msix", "appx", "jar",
            "bat", "cmd", "ps1", "vbs", "sh",
            "iso", "img", "dmg", "vhd", "vhdx",
            "pdf", "doc", "docx", "docm", "dot", "dotx",
            "xls", "xlsx", "xlsm", "xlsb", "xlt",
            "ppt", "pptx", "pptm", "pps", "ppsx", "pot",
            "odt", "ods", "odp", "pages", "numbers", "key",
            "txt", "rtf", "md", "csv", "tsv", "log",
            "html", "htm", "xml", "json", "yaml", "yml", "ini", "cfg",
            "epub", "mobi", "azw3", "fb2", "cbz", "cbr",
            "db", "sqlite", "sqlite3", "mdb", "accdb");

    /** All archive / package extensions scanned by {@link Type#ARCHIVE}. */
    private static final Set<String> ARCHIVE_EXTS = new LinkedHashSet<>(Arrays.asList(
            "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz",
            "lz", "lzma", "zst", "tzst", "apk", "aab", "deb", "rpm", "jar", "war",
            "cbz", "cbr", "epub", "whl", "egg"));

    /**
     * Extensions always matched via DISPLAY_NAME LIKE rather than mime_type IN,
     * because MimeTypeMap may map them to unexpected types (e.g. "ts" →
     * "video/mp2ts") or return null on some devices.
     */
    private static final Set<String> ALWAYS_LIKE_EXTS = new HashSet<>(Arrays.asList(
            "dart", "kt", "kts", "swift", "py", "rb", "go", "rs", "cpp", "c",
            "h", "cs", "java", "js", "ts", "sh", "bash", "zsh", "fish",
            "toml", "yaml", "yml", "ini", "cfg", "conf", "env", "properties",
            "gradle", "cmake", "makefile",
            "md", "markdown", "tex", "log", "diff", "patch",
            "db", "sqlite", "sqlite3", "mdb"));
}
