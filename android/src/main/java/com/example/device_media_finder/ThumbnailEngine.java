package com.example.device_media_finder;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.MediaMetadataRetriever;
import android.media.ThumbnailUtils;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import android.util.Log;
import android.util.Size;

import androidx.exifinterface.media.ExifInterface;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Comparator;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;

class ThumbnailEngine {

    private static final String TAG = "MM_Thumb";
    private static final int MAX_CONCURRENT = 4;
    private static final int QUALITY = 85;
    private static final long MAX_CACHE_BYTES = 128L * 1024 * 1024;

    private final Context context;
    private final File dir;
    private final Semaphore gate = new Semaphore(MAX_CONCURRENT);
    private final ConcurrentHashMap<String, Future<String>> inFlight = new ConcurrentHashMap<>();
    private final ExecutorService ioExecutor = Executors.newCachedThreadPool();

    ThumbnailEngine(Context context) {
        this.context = context;
        this.dir = new File(context.getCacheDir(), "mm_thumbs");
        this.dir.mkdirs();
    }

    // ─── Public entry point ───────────────────────────────────────────────

    /**
     * Blocking thumbnail resolver. Callers already run on a background thread;
     * identical requests are de-duplicated so the same file is never decoded
     * twice, and generation is gated by a Semaphore so a fast scroll can't
     * spawn hundreds of MediaMetadataRetriever instances at once.
     */
    String thumbnail(String uriOrPath, int width, int height, long stamp,
                     boolean isVideo, boolean isAudio) {
        final String key = md5(uriOrPath + "|" + width + "|" + height + "|" + stamp);
        final File cached = new File(dir, key + ".jpg");
        if (cached.exists() && cached.length() > 0) return cached.getAbsolutePath();

        final Future<String> future = inFlight.computeIfAbsent(key, k -> ioExecutor.submit(() -> {
            try {
                gate.acquire();
                try {
                    return generate(uriOrPath, width, height, isVideo, isAudio, cached);
                } finally {
                    gate.release();
                }
            } finally {
                inFlight.remove(k);
            }
        }));

        try {
            return future.get();
        } catch (Throwable e) {
            Log.e(TAG, "thumbnail error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            return null;
        }
    }

    void shutdown() {
        ioExecutor.shutdownNow();
    }

    // ─── Core generator ───────────────────────────────────────────────────

    private String generate(String uriOrPath, int w, int h,
                            boolean isVideo, boolean isAudio, File out) {
        Bitmap bmp;
        if (isAudio) {
            bmp = albumArt(uriOrPath, w, h);
        } else if (isVideo) {
            bmp = videoFrame(uriOrPath, w, h);
        } else {
            bmp = imageBitmap(uriOrPath, w, h);
        }
        if (bmp == null) return null;
        try {
            return saveBitmap(bmp, out);
        } finally {
            bmp.recycle();
        }
    }

    private String saveBitmap(Bitmap bmp, File out) {
        try (FileOutputStream fos = new FileOutputStream(out);
             BufferedOutputStream bos = new BufferedOutputStream(fos, 65_536)) {
            bmp.compress(Bitmap.CompressFormat.JPEG, QUALITY, bos);
            bos.flush();
            // NOTE: fd.sync() intentionally omitted — throws SyncFailedException
            // on cacheDir (tmpfs/virtual FS) on many devices. flush() is enough.
        } catch (Throwable e) {
            Log.e(TAG, "saveBitmap failed: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            out.delete();
            return null;
        }
        if (out.length() == 0L) {
            out.delete();
            return null;
        }
        trimCache();
        return out.getAbsolutePath();
    }

    // ─── Image strategies ─────────────────────────────────────────────────

    private Bitmap imageBitmap(String uriOrPath, int w, int h) {
        boolean isContent = uriOrPath.startsWith("content://");
        Uri uri = isContent ? Uri.parse(uriOrPath) : null;

        // Strategy 1: ContentResolver.loadThumbnail (API 29+) — no full decode.
        if (uri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Bitmap b = tryLoadThumbnail(uri, w, h);
            if (b != null) return b;
        }
        // Strategy 2: legacy MediaStore.Images.Thumbnails (API < 29).
        if (uri != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Bitmap b = tryLegacyImageThumbnail(uri, w, h);
            if (b != null) return b;
        }
        // Strategy 3: BitmapFactory two-pass decode (universal fallback).
        return decodeSampled(uriOrPath, w, h);
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private Bitmap tryLoadThumbnail(Uri uri, int w, int h) {
        try {
            return context.getContentResolver().loadThumbnail(uri, new Size(w, h), null);
        } catch (Throwable t) {
            return null;
        }
    }

    private Bitmap tryLegacyImageThumbnail(Uri uri, int w, int h) {
        try {
            String seg = uri.getLastPathSegment();
            if (seg == null) return null;
            long id;
            try {
                id = Long.parseLong(seg);
            } catch (NumberFormatException e) {
                return null;
            }
            @SuppressWarnings("deprecation")
            Bitmap bmp = MediaStore.Images.Thumbnails.getThumbnail(
                    context.getContentResolver(), id,
                    MediaStore.Images.Thumbnails.MINI_KIND, null);
            if (bmp == null) return null;
            return ThumbnailUtils.extractThumbnail(bmp, w, h, ThumbnailUtils.OPTIONS_RECYCLE_INPUT);
        } catch (Throwable t) {
            return null;
        }
    }

    private InputStream openStream(String pathOrUri) {
        try {
            if (pathOrUri.startsWith("content://")) {
                return context.getContentResolver().openInputStream(Uri.parse(pathOrUri));
            }
            return new FileInputStream(new File(pathOrUri));
        } catch (Throwable t) {
            return null;
        }
    }

    /**
     * Two-pass BitmapFactory decode: pass 1 measures dimensions to pick the
     * correct inSampleSize, pass 2 decodes at reduced resolution. Never loads
     * the full image into heap.
     */
    private Bitmap decodeSampled(String pathOrUri, int reqW, int reqH) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        InputStream s1 = openStream(pathOrUri);
        if (s1 != null) {
            try {
                BitmapFactory.decodeStream(s1, null, bounds);
            } finally {
                closeQuietly(s1);
            }
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;

        int sample = 1;
        while (bounds.outWidth / (sample * 2) >= reqW
                && bounds.outHeight / (sample * 2) >= reqH) {
            sample *= 2;
        }

        BitmapFactory.Options opts = new BitmapFactory.Options();
        opts.inSampleSize = sample;
        opts.inPreferredConfig = Bitmap.Config.RGB_565; // half the memory of ARGB_8888

        Bitmap raw = null;
        InputStream s2 = openStream(pathOrUri);
        if (s2 != null) {
            try {
                raw = BitmapFactory.decodeStream(s2, null, opts);
            } finally {
                closeQuietly(s2);
            }
        }
        if (raw == null) return null;
        Bitmap scaled = ThumbnailUtils.extractThumbnail(
                raw, reqW, reqH, ThumbnailUtils.OPTIONS_RECYCLE_INPUT);
        return applyExifRotation(pathOrUri, scaled);
    }

    // ─── Video ────────────────────────────────────────────────────────────

    private Bitmap videoFrame(String uriOrPath, int w, int h) {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            setDataSource(retriever, uriOrPath);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                return retriever.getScaledFrameAtTime(
                        -1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, w, h);
            }
            @SuppressWarnings("deprecation")
            Bitmap frame = retriever.getFrameAtTime();
            if (frame == null) return null;
            return ThumbnailUtils.extractThumbnail(frame, w, h, ThumbnailUtils.OPTIONS_RECYCLE_INPUT);
        } catch (Throwable e) {
            Log.e(TAG, "videoFrame error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            return null;
        } finally {
            try {
                retriever.release();
            } catch (Throwable ignored) {
            }
        }
    }

    // ─── Audio ────────────────────────────────────────────────────────────

    private Bitmap albumArt(String uriOrPath, int w, int h) {
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            setDataSource(retriever, uriOrPath);
            byte[] bytes = retriever.getEmbeddedPicture();
            if (bytes == null) return null;
            BitmapFactory.Options boundsOpts = new BitmapFactory.Options();
            boundsOpts.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, boundsOpts);
            int s = 1;
            while (boundsOpts.outWidth / (s * 2) >= w) s *= 2;
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = s;
            opts.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, opts);
        } catch (Throwable e) {
            Log.e(TAG, "albumArt error: " + e.getClass().getSimpleName() + ": " + e.getMessage());
            return null;
        } finally {
            try {
                retriever.release();
            } catch (Throwable ignored) {
            }
        }
    }

    private void setDataSource(MediaMetadataRetriever retriever, String uriOrPath) throws Exception {
        if (uriOrPath.startsWith("content://")) {
            ParcelFileDescriptor pfd = context.getContentResolver()
                    .openFileDescriptor(Uri.parse(uriOrPath), "r");
            if (pfd != null) {
                try {
                    retriever.setDataSource(pfd.getFileDescriptor());
                } finally {
                    closeQuietly(pfd);
                }
            }
        } else {
            retriever.setDataSource(uriOrPath);
        }
    }

    // ─── EXIF rotation ────────────────────────────────────────────────────

    private Bitmap applyExifRotation(String pathOrUri, Bitmap bmp) {
        float degrees;
        try {
            int orientation;
            if (pathOrUri.startsWith("content://")) {
                InputStream is = context.getContentResolver().openInputStream(Uri.parse(pathOrUri));
                if (is != null) {
                    try {
                        orientation = new ExifInterface(is).getAttributeInt(
                                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
                    } finally {
                        closeQuietly(is);
                    }
                } else {
                    orientation = ExifInterface.ORIENTATION_NORMAL;
                }
            } else {
                orientation = new ExifInterface(pathOrUri).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
            }
            switch (orientation) {
                case ExifInterface.ORIENTATION_ROTATE_90:
                    degrees = 90f;
                    break;
                case ExifInterface.ORIENTATION_ROTATE_180:
                    degrees = 180f;
                    break;
                case ExifInterface.ORIENTATION_ROTATE_270:
                    degrees = 270f;
                    break;
                default:
                    degrees = 0f;
            }
        } catch (Throwable t) {
            degrees = 0f;
        }

        if (degrees == 0f) return bmp;
        Matrix m = new Matrix();
        m.postRotate(degrees);
        Bitmap rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.getWidth(), bmp.getHeight(), m, true);
        if (rotated != bmp) bmp.recycle();
        return rotated;
    }

    // ─── Cache management ─────────────────────────────────────────────────

    private void trimCache() {
        File[] files = dir.listFiles();
        if (files == null) return;
        long total = 0;
        for (File f : files) total += f.length();
        if (total <= MAX_CACHE_BYTES) return;
        Arrays.sort(files, Comparator.comparingLong(File::lastModified));
        for (File f : files) {
            if (total <= MAX_CACHE_BYTES) return;
            total -= f.length();
            f.delete();
        }
    }

    void clear() {
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) f.delete();
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────

    private static void closeQuietly(java.io.Closeable c) {
        try {
            c.close();
        } catch (Throwable ignored) {
        }
    }

    private static String md5(String input) {
        try {
            byte[] digest = MessageDigest.getInstance("MD5").digest(input.getBytes());
            StringBuilder sb = new StringBuilder(digest.length * 2);
            for (byte b : digest) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
}
