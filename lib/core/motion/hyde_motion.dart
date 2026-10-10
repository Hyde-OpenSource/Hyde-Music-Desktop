import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Motion tokens. Every interactive animation in the app is spring-driven so
/// it can be interrupted and re-targeted mid-flight, the way UIKit springs are.
///
/// Values are expressed as SwiftUI-style (response, dampingFraction) pairs and
/// converted to Flutter's mass/stiffness/damping.
abstract final class HydeSprings {
  /// SwiftUI `.smooth` — navigation, sheets, large layout changes.
  static final smooth = _spring(response: 0.5, damping: 1.0);

  /// SwiftUI `.snappy` — tab indicator, toggles.
  static final snappy = _spring(response: 0.38, damping: 0.86);

  /// SwiftUI `.bouncy` — glass press release, menu pop-in.
  static final bouncy = _spring(response: 0.42, damping: 0.68);

  /// Very quick, critically damped — press-down feedback.
  static final press = _spring(response: 0.18, damping: 1.0);

  static SpringDescription _spring({required double response, required double damping}) {
    // stiffness = (2π / response)², damping = 4π·ζ / response (unit mass).
    final stiffness = (2 * 3.141592653589793 / response) * (2 * 3.141592653589793 / response);
    final c = 4 * 3.141592653589793 * damping / response;
    return SpringDescription(mass: 1, stiffness: stiffness, damping: c);
  }
}

abstract final class HydeDurations {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
}

/// Animates [controller] to [target] with [spring], keeping the current
/// velocity so retargeting mid-animation stays continuous.
TickerFuture springTo(AnimationController controller, double target, SpringDescription spring, {double? velocity}) {
  final sim = SpringSimulation(spring, controller.value, target, velocity ?? controller.velocity);
  return controller.animateWith(sim);
}
