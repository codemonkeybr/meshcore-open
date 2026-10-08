/// Platform-appropriate [TelemetryHistoryStore], chosen at compile time.
///
/// The file-backed store imports `dart:io` and `package:path_provider`, so it
/// cannot be imported directly without breaking the web build. Same
/// conditional-export shape as `received_image_blob_store_factory.dart`.
library;

export 'telemetry_history_store_factory_stub.dart'
    if (dart.library.io) 'telemetry_history_store_factory_io.dart';
