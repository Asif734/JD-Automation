import 'dart:io';

/// Both app variants use one OS lock. The lock disappears on process exit,
/// including crashes; a stale filename never means that automation is busy.
class AutomationLease {
  AutomationLease(this.directory);
  final Directory directory;
  RandomAccessFile? _file;
  static final Set<String> _localOwners = {};

  Future<bool> acquire() async {
    if (_file != null) return true;
    final key = directory.absolute.path;
    if (!_localOwners.add(key)) return false;
    RandomAccessFile? candidate;
    try {
      await directory.create(recursive: true);
      candidate =
          await File('$key/automation.lock').open(mode: FileMode.append);
      await candidate.lock(FileLock.exclusive);
      _file = candidate;
      return true;
    } on FileSystemException {
      await candidate?.close();
      _localOwners.remove(key);
      return false;
    } catch (_) {
      await candidate?.close();
      _localOwners.remove(key);
      rethrow;
    }
  }

  Future<void> release() async {
    final file = _file;
    if (file == null) return;
    _file = null;
    await file.unlock();
    await file.close();
    _localOwners.remove(directory.absolute.path);
  }
}
