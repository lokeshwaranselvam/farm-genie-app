import 'package:flutter_test/flutter_test.dart';
import 'package:farmgenie/utils/face/face_blink_controller.dart';

FaceBlinkSample sample({
  int faces = 1,
  double? left = 0.95,
  double? right = 0.95,
  double? yaw = 0,
  double? pitch = 0,
  double size = 0.5,
  double center = 0,
  double light = 100,
  int? id = 1,
}) => FaceBlinkSample(
  faceCount: faces,
  leftEyeOpen: left,
  rightEyeOpen: right,
  yaw: yaw,
  pitch: pitch,
  faceFraction: size,
  centerOffset: center,
  brightness: light,
  trackingId: id,
);

void openEyes(FaceBlinkController controller, {int start = 0, int id = 1}) {
  for (final offset in [0, 100, 200]) {
    controller.observe(sample(id: id), Duration(milliseconds: start + offset));
  }
}

/// The blink stage on its own; the head-turn challenge is tested separately.
const blinkOnly = FaceBlinkConfig(headTurn: false);

/// A controller whose random turn direction is fixed for the test.
FaceBlinkController turnController(FaceTurnDirection direction) =>
    FaceBlinkController(chooseDirection: () => direction)
      ..reset(Duration.zero);

/// Completes a valid blink ending at 550 ms; the turn challenge starts there.
void completeBlink(FaceBlinkController controller, {int id = 1}) {
  openEyes(controller, id: id);
  controller.observe(
    sample(left: 0.1, right: 0.1, id: id),
    const Duration(milliseconds: 300),
  );
  controller.observe(sample(id: id), const Duration(milliseconds: 450));
  controller.observe(sample(id: id), const Duration(milliseconds: 550));
}

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  test(
    'captures exactly after stable open, closed, and stable reopened eyes',
    () {
      final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
      openEyes(controller);
      expect(controller.progress.stage, FaceBlinkStage.blink);
      expect(controller.progress.canCapture, isFalse);
      controller.observe(
        sample(left: 0.1, right: 0.1),
        const Duration(milliseconds: 300),
      );
      expect(controller.progress.stage, FaceBlinkStage.reopenEyes);
      controller.observe(sample(), const Duration(milliseconds: 450));
      expect(controller.progress.stage, FaceBlinkStage.holdStill);
      controller.observe(sample(), const Duration(milliseconds: 550));
      expect(controller.progress.canCapture, isTrue);
      expect(
        controller
            .observe(sample(faces: 0), const Duration(milliseconds: 650))
            .canCapture,
        isTrue,
      );
    },
  );

  test('starting with closed eyes or winking never completes a blink', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    controller.observe(sample(left: 0.1, right: 0.1), Duration.zero);
    expect(controller.progress.stage, FaceBlinkStage.openEyes);
    openEyes(controller, start: 100);
    for (final time in [400, 500, 600]) {
      controller.observe(
        sample(left: 0.1, right: 0.95),
        Duration(milliseconds: time),
      );
    }
    controller.observe(sample(), const Duration(milliseconds: 700));
    expect(controller.progress.canCapture, isFalse);
    expect(controller.progress.stage, FaceBlinkStage.blink);
  });

  test('unknown eye probabilities reset a partially completed blink', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 300),
    );
    controller.observe(sample(left: null), const Duration(milliseconds: 400));
    expect(controller.progress.stage, FaceBlinkStage.positionFace);
    controller.observe(sample(), const Duration(milliseconds: 500));
    controller.observe(sample(), const Duration(milliseconds: 600));
    expect(controller.progress.canCapture, isFalse);
  });

  for (final faces in [0, 2, 3]) {
    test('$faces faces reset the challenge before capture', () {
      final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
      openEyes(controller);
      controller.observe(
        sample(left: 0.1, right: 0.1),
        const Duration(milliseconds: 300),
      );
      controller.observe(
        sample(faces: faces),
        const Duration(milliseconds: 400),
      );
      controller.observe(sample(), const Duration(milliseconds: 500));
      controller.observe(sample(), const Duration(milliseconds: 600));
      expect(controller.progress.canCapture, isFalse);
    });
  }

  test('a different tracked face cannot finish another face blink', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 300),
    );
    controller.observe(sample(id: 2), const Duration(milliseconds: 450));
    expect(controller.progress.stage, FaceBlinkStage.positionFace);
    controller.observe(sample(id: 2), const Duration(milliseconds: 550));
    expect(controller.progress.canCapture, isFalse);
  });

  test('long or unrealistically short eye closure requires another blink', () {
    for (final reopenedAt in [320, 1250]) {
      final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
      openEyes(controller);
      controller.observe(
        sample(left: 0.1, right: 0.1),
        const Duration(milliseconds: 300),
      );
      controller.observe(sample(), Duration(milliseconds: reopenedAt));
      expect(controller.progress.canCapture, isFalse);
      expect(controller.progress.stage, isNot(FaceBlinkStage.holdStill));
    }
  });

  test('a missing frame interval cannot bridge closed and reopened eyes', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 300),
    );
    controller.observe(sample(), const Duration(milliseconds: 1000));
    controller.observe(sample(), const Duration(milliseconds: 1100));
    expect(controller.progress.canCapture, isFalse);
  });

  test('non-monotonic timestamps reset the challenge', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 300),
    );
    controller.observe(sample(), const Duration(milliseconds: 250));
    expect(controller.progress.stage, FaceBlinkStage.positionFace);
    expect(controller.progress.canCapture, isFalse);
  });

  final badQuality = <String, FaceBlinkSample>{
    'dark': sample(light: 20),
    'too small': sample(size: 0.1),
    'off center': sample(center: 0.4),
    'turned sideways': sample(yaw: 25),
    'tilted': sample(pitch: -25),
    'unknown pose': sample(yaw: null),
    'invalid probability': sample(left: double.nan),
    'missing tracking': sample(id: null),
  };
  for (final entry in badQuality.entries) {
    test('${entry.key} photo cannot finish a partial blink', () {
      final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
      openEyes(controller);
      controller.observe(
        sample(left: 0.1, right: 0.1),
        const Duration(milliseconds: 300),
      );
      controller.observe(entry.value, const Duration(milliseconds: 450));
      expect(controller.progress.stage, FaceBlinkStage.positionFace);
      expect(controller.progress.canCapture, isFalse);
    });
  }

  test('timeout stays blocked until explicit retry resets the session', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    expect(controller.tick(const Duration(seconds: 35)).needsRetry, isTrue);
    expect(
      controller.observe(sample(), const Duration(seconds: 36)).needsRetry,
      isTrue,
    );
    controller.reset(const Duration(seconds: 36));
    openEyes(controller, start: 36000);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 36300),
    );
    controller.observe(sample(), const Duration(milliseconds: 36450));
    expect(
      controller
          .observe(sample(), const Duration(milliseconds: 36550))
          .canCapture,
      isTrue,
    );
  });

  group('head-turn challenge', () {
    test('a blink alone does not allow capture; a direction is requested', () {
      final controller = FaceBlinkController()..reset(Duration.zero);
      completeBlink(controller);
      expect(controller.progress.stage, FaceBlinkStage.turnHead);
      expect(controller.progress.canCapture, isFalse);
      expect(controller.turnDirection, isNotNull);
      expect(controller.readyAt, isNull);
    });

    test('LEFT succeeds with positive yaw, then a return to center', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      expect(controller.progress.instruction, contains('LEFT'));
      controller.observe(sample(yaw: 10), ms(650));
      expect(controller.progress.stage, FaceBlinkStage.turnHead);
      // Eyes may look closed or unclear while the head is turned.
      controller.observe(sample(yaw: 25, left: 0.3, right: null), ms(750));
      expect(controller.progress.stage, FaceBlinkStage.returnCenter);
      controller.observe(sample(yaw: 12), ms(850));
      expect(controller.progress.stage, FaceBlinkStage.returnCenter);
      controller.observe(sample(yaw: 3, left: 0.2, right: 0.2), ms(950));
      expect(controller.progress.canCapture, isFalse);
      controller.observe(sample(yaw: 3), ms(1050));
      expect(controller.progress.canCapture, isTrue);
      expect(controller.readyAt, ms(1050));
    });

    test('RIGHT succeeds with negative yaw, then a return to center', () {
      final controller = turnController(FaceTurnDirection.right);
      completeBlink(controller);
      expect(controller.progress.instruction, contains('RIGHT'));
      controller.observe(sample(yaw: -25), ms(650));
      expect(controller.progress.stage, FaceBlinkStage.returnCenter);
      controller.observe(sample(yaw: -2), ms(750));
      expect(controller.progress.canCapture, isTrue);
      expect(controller.readyAt, ms(750));
    });

    for (final direction in FaceTurnDirection.values) {
      test('turning the wrong way for $direction restarts the blink', () {
        final controller = turnController(direction);
        completeBlink(controller);
        final wrongYaw = direction == FaceTurnDirection.left ? -22.0 : 22.0;
        controller.observe(sample(yaw: wrongYaw), ms(650));
        expect(controller.progress.stage, FaceBlinkStage.positionFace);
        expect(controller.turnDirection, isNull);
        // The correct turn afterwards cannot finish without a new blink.
        controller.observe(sample(yaw: -wrongYaw), ms(750));
        controller.observe(sample(), ms(850));
        expect(controller.progress.canCapture, isFalse);
      });
    }

    test('overshooting to the other side after the turn restarts', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      controller.observe(sample(yaw: 25), ms(650));
      controller.observe(sample(yaw: -21), ms(750));
      expect(controller.progress.stage, FaceBlinkStage.positionFace);
      controller.observe(sample(), ms(850));
      expect(controller.progress.canCapture, isFalse);
    });

    test('the turn must finish before its timeout', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      expect(controller.tick(ms(550 + 5900)).stage, FaceBlinkStage.turnHead);
      expect(
        controller.tick(ms(550 + 6001)).stage,
        FaceBlinkStage.positionFace,
      );
      expect(controller.turnDirection, isNull);
      controller.observe(sample(yaw: 25), ms(6600));
      controller.observe(sample(), ms(6700));
      expect(controller.progress.canCapture, isFalse);
    });

    test('slow frames inside the turn timeout keep the challenge alive', () {
      final controller = turnController(FaceTurnDirection.right);
      completeBlink(controller);
      var time = 550;
      for (var frame = 0; frame < 12; frame++) {
        time += 500;
        controller.observe(sample(yaw: -5), ms(time));
      }
      // 6000 ms after the turn prompt: still allowed.
      expect(time, 6550);
      expect(controller.progress.stage, FaceBlinkStage.turnHead);
      controller.observe(sample(yaw: -5), ms(7050));
      expect(controller.progress.stage, isNot(FaceBlinkStage.turnHead));
      expect(controller.progress.canCapture, isFalse);
    });

    test('a different tracked face during the turn resets the challenge', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      controller.observe(sample(yaw: 25, id: 2), ms(650));
      expect(controller.progress.stage, FaceBlinkStage.positionFace);
      controller.observe(sample(yaw: 0, id: 2), ms(750));
      expect(controller.progress.canCapture, isFalse);
    });

    test('a different tracked face cannot return to center for another', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      controller.observe(sample(yaw: 25), ms(650));
      expect(controller.progress.stage, FaceBlinkStage.returnCenter);
      controller.observe(sample(yaw: 0, id: 2), ms(750));
      expect(controller.progress.stage, FaceBlinkStage.positionFace);
      expect(controller.progress.canCapture, isFalse);
      expect(controller.readyAt, isNull);
    });

    test('a second face during the turn resets the challenge', () {
      final controller = turnController(FaceTurnDirection.right);
      completeBlink(controller);
      controller.observe(sample(yaw: -25, faces: 2), ms(650));
      expect(controller.progress.stage, FaceBlinkStage.positionFace);
    });

    test('reset clears a completed challenge', () {
      final controller = turnController(FaceTurnDirection.left);
      completeBlink(controller);
      controller.observe(sample(yaw: 25), ms(650));
      controller.observe(sample(yaw: 0), ms(750));
      expect(controller.progress.canCapture, isTrue);
      controller.reset(ms(800));
      expect(controller.progress.canCapture, isFalse);
      expect(controller.readyAt, isNull);
    });
  });

  test('reset after backgrounding requires a completely new blink', () {
    final controller = FaceBlinkController(config: blinkOnly)..reset(Duration.zero);
    openEyes(controller);
    controller.observe(
      sample(left: 0.1, right: 0.1),
      const Duration(milliseconds: 300),
    );
    controller.reset(const Duration(seconds: 1));
    controller.observe(sample(), const Duration(milliseconds: 1100));
    controller.observe(sample(), const Duration(milliseconds: 1200));
    expect(controller.progress.canCapture, isFalse);
  });
}
