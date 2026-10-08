import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../utils/app_logger.dart';

/// How a repeater login attempt ended.
enum RepeaterLoginOutcome {
  /// The repeater accepted the password.
  success,

  /// The repeater answered and refused the password.
  rejected,

  /// No answer after every attempt.
  timedOut,

  /// [shouldContinue] returned false before the login finished.
  cancelled,
}

class RepeaterLoginResult {
  final RepeaterLoginOutcome outcome;

  /// Only meaningful on success. The repeater firmware reports 1 or 0 here
  /// rather than the real permission bits.
  final bool isAdmin;

  const RepeaterLoginResult(this.outcome, {this.isAdmin = false});

  bool get succeeded => outcome == RepeaterLoginOutcome.success;
}

/// Logs in to a repeater: sends the login frame, waits for the push reply and
/// retries on silence, and records how the chosen route performed.
///
/// An empty [password] is a guest login, which works on repeaters that allow
/// guest access. [onAttempt] is called with the 1-based attempt number before
/// each send, and [replyGrace] is extra waiting time added to the estimated
/// round trip. Return false from [shouldContinue] to abandon the login (for
/// example when a dialog was closed); the result is then `cancelled` and no
/// route result is recorded.
Future<RepeaterLoginResult> loginToRepeater(
  MeshCoreConnector connector,
  Contact repeater,
  String password, {
  int maxAttempts = 5,
  Duration replyGrace = const Duration(seconds: 2),
  void Function(int attempt)? onAttempt,
  bool Function()? shouldContinue,
}) async {
  appLogger.info(
    'Login started for ${repeater.name} (${repeater.publicKeyHex})',
    tag: 'RepeaterLogin',
  );
  final selection = await connector.preparePathForContactSend(repeater);
  final loginFrame = buildSendLoginFrame(repeater.publicKey, password);
  final pathLengthValue = selection.useFlood ? -1 : selection.hopCount;
  final responseBytes = loginFrame.length > maxFrameSize
      ? loginFrame.length
      : maxFrameSize;
  final timeoutMs = connector.calculateTimeout(
    pathLength: pathLengthValue,
    messageBytes: responseBytes,
  );
  final timeoutSeconds = (timeoutMs / 1000).ceil();
  final timeout = Duration(milliseconds: timeoutMs) + replyGrace;
  final selectionLabel = selection.useFlood
      ? 'flood'
      : '${selection.hopCount} hops';
  appLogger.info('Login routing: $selectionLabel', tag: 'RepeaterLogin');

  bool? loginResult;
  var isAdmin = false;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (shouldContinue != null && !shouldContinue()) {
      return const RepeaterLoginResult(RepeaterLoginOutcome.cancelled);
    }
    onAttempt?.call(attempt + 1);

    appLogger.info(
      'Sending login attempt ${attempt + 1}/$maxAttempts',
      tag: 'RepeaterLogin',
    );
    final reply = _awaitLoginResponse(connector, repeater, timeout);
    await connector.sendFrame(loginFrame);
    (loginResult, isAdmin) = await reply;
    if (loginResult == true) {
      appLogger.info(
        'Login succeeded for ${repeater.name}',
        tag: 'RepeaterLogin',
      );
      break;
    }
    if (loginResult == false) {
      appLogger.warn('Login failed for ${repeater.name}', tag: 'RepeaterLogin');
      break;
    }
    appLogger.warn(
      'Login attempt ${attempt + 1} timed out after ${timeoutSeconds}s',
      tag: 'RepeaterLogin',
    );
  }

  if (loginResult == null) {
    appLogger.warn(
      'Login timed out for ${repeater.name}',
      tag: 'RepeaterLogin',
    );
  }
  connector.recordRepeaterPathResult(
    repeater,
    selection,
    loginResult == true,
    null,
  );

  if (loginResult == true) {
    return RepeaterLoginResult(RepeaterLoginOutcome.success, isAdmin: isAdmin);
  }
  return RepeaterLoginResult(
    loginResult == false
        ? RepeaterLoginOutcome.rejected
        : RepeaterLoginOutcome.timedOut,
  );
}

/// Waits for the login push from [repeater]. Completes with (true, admin) on
/// success, (false, _) on refusal and (null, _) when [timeout] passes.
///
/// The listener is attached when this is called, before the frame is sent, so
/// a fast reply cannot be missed.
Future<(bool?, bool)> _awaitLoginResponse(
  MeshCoreConnector connector,
  Contact repeater,
  Duration timeout,
) async {
  final completer = Completer<bool?>();
  Timer? timer;
  StreamSubscription<Uint8List>? subscription;
  final targetPrefix = repeater.publicKey.sublist(0, 6);
  var isAdmin = false;
  subscription = connector.receivedFrames.listen((frame) {
    if (frame.isEmpty) return;
    final code = frame[0];
    if (code != pushCodeLoginSuccess && code != pushCodeLoginFail) return;
    if (frame.length < 8) return;
    // NOTE: a bug in the repeater firmware only ever sends 1 or 0 back, not the
    // expected client permissions
    isAdmin = (frame[1] == 1);
    final prefix = frame.sublist(2, 8);
    if (!listEquals(prefix, targetPrefix)) return;

    if (!completer.isCompleted) {
      completer.complete(code == pushCodeLoginSuccess);
    }
    subscription?.cancel();
    timer?.cancel();
  });

  timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(null);
      subscription?.cancel();
    }
  });

  final result = await completer.future;
  timer.cancel();
  await subscription.cancel();
  return (result, isAdmin);
}
