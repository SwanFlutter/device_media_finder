package com.example.device_media_finder;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

/** DeviceMediaFinderPlugin */
public class DeviceMediaFinderPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private static final int REQ_CODE = 9713;

    private MethodChannel channel;
    private Context appContext;
    private ActivityPluginBinding binding;

    // Background work runs on this pool, keeping the platform thread free.
    private final ExecutorService io = Executors.newCachedThreadPool();
    private final Handler main = new Handler(Looper.getMainLooper());

    private MediaStoreScanner scanner;
    private ThumbnailEngine thumbs;

    private MediaStoreScanner scanner() {
        if (scanner == null) scanner = new MediaStoreScanner(appContext);
        return scanner;
    }

    private ThumbnailEngine thumbs() {
        if (thumbs == null) thumbs = new ThumbnailEngine(appContext);
        return thumbs;
    }

    /**
     * Replies exactly once and always on the main thread, so background tasks
     * can never trigger a "Reply already submitted" crash.
     */
    private final class SafeResult implements Result {
        private Result delegate;

        SafeResult(Result delegate) {
            this.delegate = delegate;
        }

        @Override
        public void success(Object result) {
            post(d -> d.success(result));
        }

        @Override
        public void error(String code, String msg, Object details) {
            post(d -> d.error(code, msg, details));
        }

        @Override
        public void notImplemented() {
            post(Result::notImplemented);
        }

        private synchronized void post(Consumer<Result> block) {
            final Result d = delegate;
            if (d == null) return;
            delegate = null;
            main.post(() -> block.accept(d));
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPlugin.FlutterPluginBinding b) {
        appContext = b.getApplicationContext();
        channel = new MethodChannel(b.getBinaryMessenger(), "device_media_finder");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, Result rawResult) {
        final SafeResult result = new SafeResult(rawResult);
        switch (call.method) {
            case "getPlatformVersion":
                result.success("Android " + Build.VERSION.RELEASE);
                break;

            case "getMediaPage": {
                final MediaStoreScanner.Type type = parseType(call.argument("type"));
                final List<String> exts = argExtensions(call);
                final int page = argInt(call, "page", 0);
                final int size = clamp(argInt(call, "pageSize", 100), 1, 500);
                io.execute(() -> {
                    try {
                        result.success(scanner().queryPage(type, exts, page * size, size, null));
                    } catch (Throwable t) {
                        result.error("QUERY_ERROR", t.getMessage(), null);
                    }
                });
                break;
            }

            case "getMediaCount": {
                final MediaStoreScanner.Type type = parseType(call.argument("type"));
                final List<String> exts = argExtensions(call);
                io.execute(() -> {
                    try {
                        result.success(scanner().count(type, exts, null));
                    } catch (Throwable t) {
                        result.error("QUERY_ERROR", t.getMessage(), null);
                    }
                });
                break;
            }

            case "getThumbnail": {
                String src = call.argument("uri");
                if (src == null) src = call.argument("path");
                if (src == null) {
                    result.error("INVALID_ARGUMENT", "uri/path required", null);
                    break;
                }
                final String source = src;
                final int w = argInt(call, "width", 256);
                final int h = argInt(call, "height", w);
                final long stamp = argLong(call, "dateModified", 0L);
                String k = call.argument("kind");
                final String kind = (k != null) ? k : "image";
                io.execute(() -> result.success(thumbs().thumbnail(
                        source, w, h, stamp, "video".equals(kind), "audio".equals(kind))));
                break;
            }

            case "clearThumbnailCache":
                io.execute(() -> {
                    thumbs().clear();
                    result.success(true);
                });
                break;

            case "getDirectories":
                io.execute(() -> result.success(publicDirectories()));
                break;

            case "getDirectoryContents": {
                String p = call.argument("path");
                final String path = (p != null) ? p : Environment.getExternalStorageDirectory().getPath();
                final int page = argInt(call, "page", 0);
                final int size = clamp(argInt(call, "pageSize", 200), 1, 1000);
                io.execute(() -> {
                    try {
                        result.success(listDir(path, page, size));
                    } catch (Throwable t) {
                        result.error("FILE_ACCESS_ERROR", t.getMessage(), null);
                    }
                });
                break;
            }

            case "hasStoragePermission":
                result.success(hasPermission());
                break;
            case "hasAllFilesAccess":
                result.success(hasAllFilesAccess());
                break;
            case "requestStoragePermission":
                requestPermission(result);
                break;
            case "openAllFilesAccessSettings":
                openAllFilesSettings();
                result.success(true);
                break;

            default:
                result.notImplemented();
        }
    }

    // ─── Argument helpers ─────────────────────────────────────────────────

    private static int argInt(MethodCall call, String key, int def) {
        Object v = call.argument(key);
        return v instanceof Number ? ((Number) v).intValue() : def;
    }

    private static long argLong(MethodCall call, String key, long def) {
        Object v = call.argument(key);
        return v instanceof Number ? ((Number) v).longValue() : def;
    }

    @SuppressWarnings("unchecked")
    private static List<String> argExtensions(MethodCall call) {
        Object v = call.argument("extensions");
        return v instanceof List ? (List<String>) v : Collections.<String>emptyList();
    }

    private static int clamp(int v, int lo, int hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    private static MediaStoreScanner.Type parseType(String s) {
        if (s == null) return MediaStoreScanner.Type.ANY;
        switch (s) {
            case "image": return MediaStoreScanner.Type.IMAGE;
            case "video": return MediaStoreScanner.Type.VIDEO;
            case "audio": return MediaStoreScanner.Type.AUDIO;
            case "document": return MediaStoreScanner.Type.DOCUMENT;
            case "archive": return MediaStoreScanner.Type.ARCHIVE;
            default: return MediaStoreScanner.Type.ANY;
        }
    }

    // ─── Directory browsing ───────────────────────────────────────────────

    private List<Map<String, Object>> listDir(String path, int page, int size) {
        File dir = new File(path);
        if (!dir.isDirectory()) throw new IllegalArgumentException("Invalid directory: " + path);
        File[] arr = dir.listFiles();
        List<File> all = new ArrayList<>();
        if (arr != null) Collections.addAll(all, arr);
        all.sort((a, b) -> {
            if (a.isDirectory() != b.isDirectory()) return a.isDirectory() ? -1 : 1;
            return a.getName().toLowerCase().compareTo(b.getName().toLowerCase());
        });
        int from = page * size;
        if (from >= all.size()) return new ArrayList<>();
        List<File> slice = all.subList(from, Math.min(from + size, all.size()));
        List<Map<String, Object>> out = new ArrayList<>(slice.size());
        for (File f : slice) {
            Map<String, Object> m = new HashMap<>();
            m.put("name", f.getName());
            m.put("path", f.getAbsolutePath());
            m.put("isDirectory", f.isDirectory());
            m.put("size", f.length());
            m.put("dateModified", f.lastModified());
            m.put("extension", f.isDirectory() ? "" : extLower(f.getName()));
            out.add(m);
        }
        return out;
    }

    private List<Map<String, String>> publicDirectories() {
        String[] types = {
                Environment.DIRECTORY_DCIM, Environment.DIRECTORY_PICTURES,
                Environment.DIRECTORY_MOVIES, Environment.DIRECTORY_MUSIC,
                Environment.DIRECTORY_DOWNLOADS, Environment.DIRECTORY_DOCUMENTS
        };
        List<Map<String, String>> out = new ArrayList<>();
        for (String t : types) {
            try {
                File d = Environment.getExternalStoragePublicDirectory(t);
                if (d != null && d.exists()) {
                    Map<String, String> m = new HashMap<>();
                    m.put("name", t);
                    m.put("path", d.getAbsolutePath());
                    out.add(m);
                }
            } catch (Throwable ignored) {
            }
        }
        File ext = Environment.getExternalStorageDirectory();
        if (ext != null) {
            Map<String, String> m = new HashMap<>();
            m.put("name", "Internal Storage");
            m.put("path", ext.getAbsolutePath());
            out.add(0, m);
        }
        return out;
    }

    private static String extLower(String name) {
        int idx = name.lastIndexOf('.');
        return idx < 0 ? "" : name.substring(idx + 1).toLowerCase();
    }

    // ─── Permissions ──────────────────────────────────────────────────────

    private boolean hasAllFilesAccess() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager();
    }

    private boolean granted(String perm) {
        return ContextCompat.checkSelfPermission(appContext, perm) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean hasPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return granted(Manifest.permission.READ_MEDIA_IMAGES)
                    || granted(Manifest.permission.READ_MEDIA_VIDEO)
                    || granted(Manifest.permission.READ_MEDIA_AUDIO);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
                    || granted(Manifest.permission.READ_EXTERNAL_STORAGE);
        } else {
            return granted(Manifest.permission.READ_EXTERNAL_STORAGE);
        }
    }

    /** One listener, one requestCode, no chance of a double reply. */
    private void requestPermission(Result result) {
        if (hasPermission()) {
            result.success(true);
            return;
        }
        final ActivityPluginBinding b = binding;
        if (b == null) {
            result.error("NO_ACTIVITY", "Activity unavailable", null);
            return;
        }
        final String[] perms = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                ? new String[]{
                        Manifest.permission.READ_MEDIA_IMAGES,
                        Manifest.permission.READ_MEDIA_VIDEO,
                        Manifest.permission.READ_MEDIA_AUDIO}
                : new String[]{Manifest.permission.READ_EXTERNAL_STORAGE};

        final PluginRegistry.RequestPermissionsResultListener listener =
                new PluginRegistry.RequestPermissionsResultListener() {
                    @Override
                    public boolean onRequestPermissionsResult(int code, String[] p, int[] g) {
                        if (code != REQ_CODE) return false;
                        b.removeRequestPermissionsResultListener(this);
                        boolean anyGranted = false;
                        for (int r : g) {
                            if (r == PackageManager.PERMISSION_GRANTED) {
                                anyGranted = true;
                                break;
                            }
                        }
                        result.success(g.length > 0 && anyGranted);
                        return true;
                    }
                };
        b.addRequestPermissionsResultListener(listener);
        ActivityCompat.requestPermissions(b.getActivity(), perms, REQ_CODE);
    }

    /** MANAGE_EXTERNAL_STORAGE is granted only through an Intent, never requestPermissions. */
    private void openAllFilesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return;
        Intent i = new Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:" + appContext.getPackageName()));
        if (binding != null) {
            binding.getActivity().startActivity(i);
        } else {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            appContext.startActivity(i);
        }
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────

    @Override
    public void onDetachedFromEngine(FlutterPlugin.FlutterPluginBinding b) {
        channel.setMethodCallHandler(null);
        io.shutdownNow();
        if (thumbs != null) thumbs.shutdown();
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding b) {
        binding = b;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding b) {
        binding = b;
    }

    @Override
    public void onDetachedFromActivity() {
        binding = null;
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        binding = null;
    }
}
