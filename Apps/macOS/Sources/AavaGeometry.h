#pragma once

// Shared by SwiftUI chrome and Chromium's native page container.
static const double AavaFrameInset = 8.0;
static const double AavaFrameRadius = 24.0;
static inline double AavaInsetRadius(double outer, double inset) {
  return outer > inset ? outer - inset : 0.0;
}
