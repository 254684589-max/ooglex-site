package com.ooglex.music;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.view.KeyEvent;

import org.json.JSONObject;

/** The WebView owns the only audio element. This service only publishes/controls that player.
 * Started/foreground only while playing or buffering; paused sessions remain Activity-bound.
 * No boot receiver, sticky restart, wake lock, second audio engine, or playback after Activity teardown.
 */
public class MediaPlaybackService extends Service {
    private static final String CHANNEL = "music_playback";
    private static final int NOTIFICATION = 41;
    private static final long ACTIONS = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE
            | PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_SKIP_TO_NEXT
            | PlaybackState.ACTION_SKIP_TO_PREVIOUS | PlaybackState.ACTION_SEEK_TO | PlaybackState.ACTION_STOP;

    interface Controller { void command(String action, double value); }
    final class LocalBinder extends Binder { MediaPlaybackService service() { return MediaPlaybackService.this; } }
    private final LocalBinder binder = new LocalBinder();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private MediaSession session;
    private NotificationManager notifications;
    private Controller controller;
    private String title = "", artist = "", album = "";
    private String status = "none";
    private long duration = 0, position = 0;
    private boolean foreground;
    private final Runnable bufferingTimeout = () -> { command("nativeerror", 0); reset(); };
    private final BroadcastReceiver noisy = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { command("pause", 0); }
    };

    @Override public void onCreate() {
        super.onCreate();
        notifications = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL, "音乐播放", NotificationManager.IMPORTANCE_LOW);
            channel.setSound(null, null);
            notifications.createNotificationChannel(channel);
        }
        session = new MediaSession(this, "OoglexMusic");
        session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
        session.setCallback(new MediaSession.Callback() {
            @Override public void onPlay() { command("play", 0); }
            @Override public void onPause() { command("pause", 0); }
            @Override public void onStop() { command("pause", 0); }
            @Override public void onSkipToNext() { command("next", 0); }
            @Override public void onSkipToPrevious() { command("previous", 0); }
            @Override public void onSeekTo(long pos) { command("seek", pos / 1000.0); }
            @Override public boolean onMediaButtonEvent(Intent intent) {
                KeyEvent key = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
                if (key == null) return false;
                int code = key.getKeyCode();
                if (code == KeyEvent.KEYCODE_MEDIA_NEXT || code == KeyEvent.KEYCODE_MEDIA_PREVIOUS) {
                    if (key.getAction() == KeyEvent.ACTION_DOWN && key.getRepeatCount() == 0) {
                        command(code == KeyEvent.KEYCODE_MEDIA_NEXT ? "next" : "previous", 0);
                    }
                    return true;
                }
                return super.onMediaButtonEvent(intent);
            }
        }, handler);
        IntentFilter filter = new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(noisy, filter);
    }

    @Override public IBinder onBind(Intent intent) { return binder; }
    void attach(Controller value) { controller = value; }
    void detach() { reset(); controller = null; }

    private void command(String action, double value) {
        if (controller != null) controller.command(action, value);
    }

    void update(JSONObject data) {
        if (controller == null) return;
        String next = data.optString("status", "none");
        if (!(next.equals("playing") || next.equals("buffering") || next.equals("paused"))) {
            reset(); return;
        }
        boolean changed = !next.equals(status) || !title.equals(text(data, "title"))
                || !artist.equals(text(data, "artist")) || !album.equals(text(data, "album"));
        boolean enteringBuffer = next.equals("buffering") && !status.equals("buffering");
        status = next;
        title = text(data, "title"); artist = text(data, "artist"); album = text(data, "album");
        duration = millis(data.optDouble("duration", 0));
        position = Math.min(duration > 0 ? duration : Long.MAX_VALUE, millis(data.optDouble("position", 0)));
        MediaMetadata metadata = new MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, duration).build();
        session.setMetadata(metadata);
        int state = status.equals("playing") ? PlaybackState.STATE_PLAYING
                : status.equals("buffering") ? PlaybackState.STATE_BUFFERING : PlaybackState.STATE_PAUSED;
        session.setPlaybackState(new PlaybackState.Builder().setActions(ACTIONS)
                .setState(state, position, state == PlaybackState.STATE_PLAYING ? 1f : 0f).build());
        // Activate after publishing metadata/actions; the system must not see an empty active session.
        if (!session.isActive()) session.setActive(true);
        if (status.equals("playing") || status.equals("buffering")) {
            if (!beginForeground()) return;
            if (changed) notifications.notify(NOTIFICATION, notification());
        } else {
            endForeground();
            if (changed) notifications.notify(NOTIFICATION, notification());
        }
        if (!status.equals("buffering")) handler.removeCallbacks(bufferingTimeout);
        else if (enteringBuffer) { handler.removeCallbacks(bufferingTimeout); handler.postDelayed(bufferingTimeout, 30000); }
    }

    private static String text(JSONObject data, String key) {
        String value = data.optString(key, "");
        return value.substring(0, Math.min(240, value.length()));
    }
    private static long millis(double seconds) {
        return Double.isNaN(seconds) || Double.isInfinite(seconds) ? 0
                : (long) (Math.max(0, Math.min(864000, seconds)) * 1000);
    }

    private boolean beginForeground() {
        if (foreground) return true;
        try {
            Intent intent = new Intent(this, MediaPlaybackService.class);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent);
            else startService(intent);
            promote();
            return true;
        } catch (IllegalStateException | SecurityException error) {
            // Background start restrictions differ by Android version. Fail visibly in the page.
            command("nativeerror", 0);
            reset();
            return false;
        }
    }

    private void promote() {
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        else startForeground(NOTIFICATION, notification());
        foreground = true;
    }

    private void endForeground() {
        if (foreground) {
            if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_DETACH);
            else stopForeground(false);
            foreground = false;
        }
        stopSelf(); // Remains bound only as long as the owning Activity exists.
    }

    private PendingIntent action(String action, int request) {
        Intent intent = new Intent(this, MediaPlaybackService.class).setAction(action);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        if (Build.VERSION.SDK_INT >= 26) return PendingIntent.getForegroundService(this, request, intent, flags);
        return PendingIntent.getService(this, request, intent, flags);
    }

    @SuppressWarnings("deprecation")
    private Notification notification() {
        Intent open = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        session.setSessionActivity(content);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        boolean playing = status.equals("playing") || status.equals("buffering");
        return builder.setSmallIcon(R.drawable.ic_media_notification)
                .setContentTitle(title).setContentText(artist).setSubText(album)
                .setContentIntent(content).setVisibility(Notification.VISIBILITY_PUBLIC)
                .setCategory(Notification.CATEGORY_TRANSPORT).setOnlyAlertOnce(true)
                .setOngoing(playing).setShowWhen(false)
                .addAction(android.R.drawable.ic_media_previous, "上一曲", action("previous", 1))
                .addAction(playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
                        playing ? "暂停" : "播放", action(playing ? "pause" : "play", 2))
                .addAction(android.R.drawable.ic_media_next, "下一曲", action("next", 3))
                .setStyle(new Notification.MediaStyle().setMediaSession(session.getSessionToken()).setShowActionsInCompactView(0, 1, 2))
                .build();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (controller == null || status.equals("none")) {
            // No page/player: never restart playback from a stale notification or process restart.
            reset(); return START_NOT_STICKY;
        }
        // A getForegroundService PendingIntent must be acknowledged before processing its action.
        if (!foreground) promote();
        String action = intent == null ? null : intent.getAction();
        if (action != null) {
            if (action.equals("play") || action.equals("pause") || action.equals("next") || action.equals("previous")) command(action, 0);
            // JS acknowledges the actual state; do not guess that a play request succeeded.
        }
        if (status.equals("paused")) endForeground();
        return START_NOT_STICKY;
    }

    void reset() {
        handler.removeCallbacks(bufferingTimeout);
        status = "none";
        if (session != null) {
            session.setPlaybackState(new PlaybackState.Builder().setActions(0).setState(PlaybackState.STATE_NONE, 0, 0).build());
            session.setMetadata(null); session.setActive(false);
        }
        endForeground();
        notifications.cancel(NOTIFICATION);
    }

    @Override public void onTaskRemoved(Intent intent) { command("pause", 0); controller = null; reset(); super.onTaskRemoved(intent); }
    @Override public void onDestroy() {
        command("pause", 0);
        reset(); controller = null;
        unregisterReceiver(noisy);
        session.release();
        super.onDestroy();
    }
}
