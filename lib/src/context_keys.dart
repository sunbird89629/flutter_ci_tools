/// Centralised string keys for values stored in [PipelineContext]'s KV bag.
///
/// Library actions write and read their results through these constants so
/// producers and consumers never disagree on a raw string literal.
class ContextKeys {
  ContextKeys._();

  /// Resolved build number (`int`). Written by `ResolveBuildVersionAction`.
  static const buildNumber = 'buildNumber';

  /// Build artifact (`File`). Written by `BuildAndroidAction` / `BuildIOSAction`.
  static const buildArtifact = 'buildArtifact';

  /// Pgyer download URL (`String`). Written by `PgyerUploadAction` / V2.
  static const pgyerDownloadUrl = 'pgyerDownloadUrl';
}
