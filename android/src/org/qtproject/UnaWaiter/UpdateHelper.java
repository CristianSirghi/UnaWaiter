package org.qtproject.UnaWaiter;

import android.app.DownloadManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;

/*
 * UpdateHelper
 * ------------
 * Descarca un APK prin Android DownloadManager si, la final, porneste
 * ecranul de instalare. Nu necesita FileProvider (DownloadManager ofera
 * direct un content:// URI valid pentru instalare).
 *
 * Apelat din C++ (UpdateManager) prin JNI. Portat din D:\MMOffline.
 */
public class UpdateHelper {

    private static long sDownloadId = -1;
    private static DownloadManager sManager = null;
    private static BroadcastReceiver sReceiver = null;
    private static boolean sInstallLaunched = false;

    public static synchronized void startUpdate(final Context context, String apkUrl, String fileName) {
        if (context == null || apkUrl == null || apkUrl.length() == 0)
            return;

        final Context appCtx = context.getApplicationContext();

        // Curatam o eventuala descarcare anterioara.
        cleanupReceiver(appCtx);
        sInstallLaunched = false;

        sManager = (DownloadManager) appCtx.getSystemService(Context.DOWNLOAD_SERVICE);
        if (sManager == null)
            return;

        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(apkUrl));
        request.setMimeType("application/vnd.android.package-archive");
        request.setTitle(fileName);
        request.setNotificationVisibility(
            DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        request.setDestinationInExternalFilesDir(appCtx, null, fileName);
        request.setAllowedOverMetered(true);
        request.setAllowedOverRoaming(true);

        sDownloadId = sManager.enqueue(request);

        sReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context ctx, Intent intent) {
                long id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1);
                if (id != sDownloadId)
                    return;
                launchInstall(appCtx);
                cleanupReceiver(appCtx);
            }
        };

        IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
        // Pe Android 13+ trebuie specificat explicit flag-ul de export.
        // RECEIVER_EXPORTED == 2 (folosim literalul pentru a compila si pe SDK mai vechi).
        if (Build.VERSION.SDK_INT >= 33) {
            appCtx.registerReceiver(sReceiver, filter, 2);
        } else {
            appCtx.registerReceiver(sReceiver, filter);
        }
    }

    private static synchronized void launchInstall(Context appCtx) {
        if (sInstallLaunched || sManager == null || sDownloadId < 0)
            return;

        Uri uri = sManager.getUriForDownloadedFile(sDownloadId);
        if (uri == null)
            return;

        Intent install = new Intent(Intent.ACTION_VIEW);
        install.setDataAndType(uri, "application/vnd.android.package-archive");
        install.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

        try {
            appCtx.startActivity(install);
            sInstallLaunched = true;
        } catch (Exception e) {
            // ignoram - utilizatorul poate instala manual din notificare
        }
    }

    private static synchronized void cleanupReceiver(Context appCtx) {
        if (sReceiver != null) {
            try {
                appCtx.unregisterReceiver(sReceiver);
            } catch (Exception ignored) {
            }
            sReceiver = null;
        }
    }

    /*
     * Progresul descarcarii curente, pentru polling din C++:
     *   0..99 = in curs
     *   100   = gata (instalarea a fost lansata)
     *   -1    = esuat / inexistent
     */
    public static synchronized int getProgress(Context context) {
        if (sManager == null || sDownloadId < 0)
            return -1;

        DownloadManager.Query query = new DownloadManager.Query();
        query.setFilterById(sDownloadId);

        Cursor cursor = null;
        try {
            cursor = sManager.query(query);
            if (cursor == null || !cursor.moveToFirst())
                return -1;

            int statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS);
            int status = statusIdx >= 0 ? cursor.getInt(statusIdx) : -1;

            if (status == DownloadManager.STATUS_FAILED)
                return -1;

            if (status == DownloadManager.STATUS_SUCCESSFUL)
                return 100;

            int totalIdx = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES);
            int doneIdx = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR);
            long total = totalIdx >= 0 ? cursor.getLong(totalIdx) : -1;
            long done = doneIdx >= 0 ? cursor.getLong(doneIdx) : 0;

            if (total <= 0)
                return 0; // inca nu stim dimensiunea totala

            int pct = (int) (done * 100L / total);
            if (pct >= 100)
                pct = 99; // 100 il rezervam pentru STATUS_SUCCESSFUL
            return pct;
        } catch (Exception e) {
            return -1;
        } finally {
            if (cursor != null)
                cursor.close();
        }
    }
}
