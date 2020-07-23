import 'package:diffutil_dart/diffutil.dart' as diffutil;

/// Note: This is a dart-only project, running flutter pub get will fail with an error message of a missing
/// pubspec.yaml in the example folder. Just run pub get instead.

void main() {
  final oldList = [1, 2, 3];
  final newList = [2, 3, 4];

  print("difference between $oldList and $newList, without move detection:");

  final listDiff = diffutil.calculateListDiff(oldList, newList).getUpdates();

  // use the diff using a list of diff objects
  for (final update in listDiff) {
    update.when(
      insert: (pos, count) => print("inserted $count item on $pos"),
      remove: (pos, count) => print("removed $count item on $pos"),
      change: (pos, payload) => print("changed on $pos with payload $payload"),
      move: (from, to) => print("move from $from to $to"),
    );
  }

  print("changeset: $listDiff");

  final oldList2 = [1, 2, 3];
  final newList2 = [1, 3, 2];

  print("\n");

  print("difference between $oldList2 and $newList2, without move detection:");

  final listDiff2 = diffutil
      .calculateListDiff(oldList2, newList2, detectMoves: false)
      .getUpdates();

  print("changeset: $listDiff2");

  print("\n");

  print("difference between $oldList2 and $newList2, with move detection:");

  final listDiff3 =
      diffutil.calculateListDiff(oldList2, newList2, detectMoves: true).getUpdates();

  print("changeset: $listDiff3");

  print("\n");

  final oldList3 = [];
  final newList3 = [1,2,3];

  print("difference between $oldList3 and $newList3, batched:");

  final listDiff4 = diffutil.calculateListDiff(oldList3, newList3).getUpdates(batch: true);

  print("changeset: $listDiff4");

  print("\n");

  print("difference between $oldList3 and $newList3, unbatched:");

  final listDiff5 = diffutil.calculateListDiff(oldList3, newList3).getUpdates(batch: false);

  print("changeset: $listDiff5");

  print("\n");



}

// ignore: deprecated_member_use_from_same_package
class MyListCallback implements diffutil.ListUpdateCallback {
  @override
  void onChanged(int position, int count, Object payload) {
    print("$count item(s) on position $position changed!");
  }

  @override
  void onInserted(int position, int count) {
    print("$count item(s) on position $position have been inserted!");
  }

  @override
  void onMoved(int fromPosition, int toPosition) {
    print("item on position $fromPosition moved to $toPosition!");
  }

  @override
  void onRemoved(int position, int count) {
    print("$count item(s) on position have been removed!");
  }
}
