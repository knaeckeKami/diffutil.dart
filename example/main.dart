import 'package:diffutil_dart/diffutil.dart' as diffutil;

void main() {
  final oldList = [1, 2, 3];
  final newList = [2, 3, 4];

  print("difference between $oldList and $newList, with move detection:");

  final listDiff = diffutil.calculateListDiff(oldList, newList);

  listDiff.dispatchUpdatesTo(MyListCallback());

  final oldList2 = [1, 2, 3];
  final newList2 = [1, 3, 2];

  print("\n");

  print("difference between $oldList and $newList, without move detection:");

  final listDiff2 = diffutil.calculateListDiff(oldList2, newList2, detectMoves: false);

  listDiff2.dispatchUpdatesTo(MyListCallback());

  print("\n");

  print("difference between $oldList and $newList, with move detection:");

  final listDiff3 = diffutil.calculateListDiff(oldList2, newList2, detectMoves: true);

  listDiff3.dispatchUpdatesTo(MyListCallback());

}

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
