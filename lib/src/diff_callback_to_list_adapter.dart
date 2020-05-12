import 'package:diffutil_dart/diffutil.dart';
import 'package:diffutil_dart/src/model/diffupdate.dart';

class CallbackToListAdapter implements ListUpdateCallback {
  final List<DiffUpdate> updates = [];

  @override
  void onChanged(int position, int count, Object payload) {
    for (int i = 0; i < count; i++)
      updates.add(DiffUpdate.change(position: position + i, payload: payload));
  }

  @override
  void onInserted(int position, int count) {
    updates.add(DiffUpdate.insert(position: position, count: count));
  }

  @override
  void onMoved(int from, int to) {
    updates.add(DiffUpdate.move(from: from, to: to));
  }

  @override
  void onRemoved(int position, int count) {
    updates.add(DiffUpdate.remove(position: position, count: count));
  }
}
