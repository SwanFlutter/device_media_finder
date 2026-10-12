/// The category of media to query from the device.
///
/// The [name] of each value is sent verbatim over the method channel, so it
/// must stay in sync with the native `parseType` mapping.
enum MediaType {
  /// Photos indexed by `MediaStore` ([MediaStore.Images]).
  image,

  /// Videos of any container/codec and any size ([MediaStore.Video]).
  video,

  /// Audio files of any format and any size ([MediaStore.Audio]).
  audio,

  /// Office/text/eBook documents. Resolved by a MediaStore query merged with a
  /// bounded file-system scan, because many OEM ROMs do not index documents.
  document,

  /// Archives and app packages (zip, rar, 7z, apk, ...). Also resolved with a
  /// merged file-system scan.
  archive,

  /// Every file, optionally narrowed by [extensions].
  any,
}
