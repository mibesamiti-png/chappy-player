/// Permission policy for .chappy capability declarations.
/// Checks only the manifest allowlist; Android OS consent is separate.
const chappyMediaResources = <String>{'camera', 'microphone'};

bool canRequestChappyMedia(
  Iterable<String> manifestPermissions,
  Iterable<String> requestedResources,
) {
  final requested = requestedResources.toSet();
  if (requested.isEmpty || requested.length != requestedResources.length) {
    return false;
  }
  if (requested.any((resource) => !chappyMediaResources.contains(resource))) {
    return false;
  }
  return manifestPermissions.toSet().containsAll(requested);
}
