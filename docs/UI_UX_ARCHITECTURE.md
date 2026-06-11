# UI/UX ARCHITECTURE — Responsive Scaling

> Technical UI Guidelines & Implementations | June 2026

---

## 1. Core Philosophy

The Wasla interface is built on the principle of **Unified Layout Parity**. A single Flutter widget tree must elegantly adapt to:
- Portrait Mobile Devices (Notches, Safe Areas)
- Landscape Mobile Devices (Constrained vertical heights)
- Desktop / Ultra-wide Monitors (Expansive horizontal real estate)

---

## 2. The `CallScreen` Overflow Prevention Strategy

During WebRTC rendering, native video views `RTCVideoView` often conflict with absolute positioned UI elements (`Positioned`), causing `RenderFlex` overflows—especially in mobile landscape mode where vertical height is severely limited.

### The `SingleChildScrollView` + `math.max` Solution
To ensure the floating controls (`_ControlsPill`), caller name, and call timer never overflow off the screen or overlap the safe areas, the foreground layer of the `CallScreen` employs a bounded scroll view:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    // Determine bounds dynamically based on the current window constraints
    final isDesktop = constraints.maxWidth > 800;
    
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Force the UI to take up exactly the screen height, UNLESS 
          // the screen shrinks below 600px (Landscape), in which case
          // it expands the scrollable canvas to 600px.
          minHeight: math.max(constraints.maxHeight, 600.0),
        ),
        child: IntrinsicHeight(
          child: Column(
            // Push contents gracefully without hard Expanded constraints
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
               // Header ...
               // Name and Timer ...
               // _ControlsPill
            ]
          )
        )
      )
    );
  }
)
```

This guarantees the WebRTC `RTCVideoView` continues to paint flawlessly in the background using `object-fit: cover`, while the UI elements smoothly scroll over the video layer if the user rotates their device to landscape.

---

## 3. Dynamic Padding & Margins (`_ControlsPill`)

The bottom action bar (`_ControlsPill`), containing the Mic, Camera, Speaker, and Hangup buttons, scales dynamically based on device topology.

### Logic Implementation
- **Desktop/Tablet Mode (`maxWidth > 800`):** The pill gains significant lateral margins (`EdgeInsets.symmetric(horizontal: 100)`), preventing the buttons from stretching awkwardly across ultra-wide monitors.
- **Mobile Mode:** The pill rests near the bottom edge (`EdgeInsets.symmetric(horizontal: 12)`), maximizing touch targets for thumbs.
- **Safe Areas:** Wrapped in a `SafeArea` to respect modern smartphone notch cutouts and bottom gesture bars.

---

## 4. UI Rendering Hardware Optimizations

- **AnimatedOpacity:** Used heavily for fading UI elements in and out (e.g., hiding controls after inactivity). `AnimatedOpacity` is preferred over rebuilding the widget tree because it directly utilizes the GPU compositor, avoiding expensive Flutter paint cycles while an active WebRTC 60fps video stream is running.
- **BackdropFilter:** Used for the glassmorphism blur effects on the `_ControlsPill`. It explicitly clamps bounds to prevent the blur shader from bleeding into the raw WebRTC texture layers.
