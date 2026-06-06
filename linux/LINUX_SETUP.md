# Linux Setup — Wasla

## Audio Requirements (GStreamer)

`audioplayers` on Linux uses GStreamer as its backend.
Without the following packages, **all sounds are completely silent**
(no crash, no error — just silence):

```bash
sudo apt install \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad
```

Run this once on any Linux machine you build or run Wasla on.

## Why no error?

`audioplayers` catches GStreamer init failures silently and simply
plays nothing. You won't see a crash — the app runs normally but
call sounds, message sounds, and notifications are all muted.

## Affected features

- Incoming call ringtone
- Outgoing call ringback tone
- Call end chime
- Message sent / received sounds
