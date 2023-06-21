import 'package:diffutil_dart/diffutil.dart';

/// Note: This is a dart-only project, running flutter pub get will fail with an error message of a missing
/// pubspec.yaml in the example folder. Just run pub get instead.

void main() {
  final oldList = [1, 2, 3];
  final newList = [2, 3, 4];

  print('difference between $oldList and $newList, without move detection:');

  final listDiff = calculateListDiff(oldList, newList).getUpdates();

  // use the diff using a list of diff objects
  for (final update in listDiff) {
    switch(update){
      case Insert(position: final pos, count: final count) : print('inserted $count item on $pos');
      case Remove(position: final pos, count: final count) : print('removed $count item on $pos');
      case Change(position: final pos, payload: final payload) : print('changed item on $pos with payload $payload');
      case Move(from: final from, to: final to) : print('moved item from $from to $to');
    }
  }

  print('changeset: $listDiff');

  final oldList2 = [1, 2, 3];
  final newList2 = [1, 3, 2];

  print('\n');

  print('difference between $oldList2 and $newList2, without move detection:');

  final listDiff2 =
      calculateListDiff(oldList2, newList2, detectMoves: false)
      .getUpdates();

  print('changeset: $listDiff2');

  print('\n');

  print('difference between $oldList2 and $newList2, with move detection:');

  final listDiff3 =
calculateListDiff(oldList2, newList2, detectMoves: true)
      .getUpdates();

  print('changeset: $listDiff3');

  print('\n');

  print(
      'difference between $oldList and $newList, with data, with move detection:');

  final listDiff4 =
      calculateListDiff(oldList, newList, detectMoves: true)
      .getUpdatesWithData();

  print('changeset: $listDiff4');

  print('\n');

  final oldList3 = [];
  final newList3 = [1, 2, 3];

  print('difference between $oldList3 and $newList3, batched:');

  final listDiff5 =
      calculateListDiff(oldList3, newList3).getUpdates(batch: true);

  print('changeset: $listDiff5');

  print('\n');

  print('difference between $oldList3 and $newList3, unbatched:');

  final listDiff6 =
      calculateListDiff(oldList3, newList3).getUpdates(batch: false);

  print('changeset: $listDiff6');

  print('\n');

  final dataObjectList1 = [DataObject(id: 1, payload: 0)];
  final dataObjectList2 = [DataObject(id: 1, payload: 1)];

  print(
      'data object diff between $dataObjectList1 and $dataObjectList2, default behaviour');

  print(      calculateListDiff(dataObjectList1, dataObjectList2)
      .getUpdatesWithData());

  print('\n');

  print(
      'data object diff $dataObjectList1 and $dataObjectList2, with custom delegate with that respects identity');

  print(
      calculateDiff(DataObjectListDiff(dataObjectList1, dataObjectList2))
      .getUpdatesWithData());
}

class DataObject {
  final int id;
  final int? payload;

  DataObject({required this.id, this.payload});

  @override
  String toString() {
    return 'DataObject{id: $id, payload: $payload}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataObject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          payload == other.payload;

  @override
  int get hashCode => id.hashCode ^ payload.hashCode;
}

class DataObjectListDiff extends ListDiffDelegate<DataObject> {
  DataObjectListDiff(List<DataObject> oldList, List<DataObject> newList)
      : super(oldList, newList);

  @override
  bool areContentsTheSame(int oldItemPosition, int newItemPosition) {
    return equalityChecker(oldList[oldItemPosition], newList[newItemPosition]);
  }

  @override
  bool areItemsTheSame(int oldItemPosition, int newItemPosition) {
    return oldList[oldItemPosition].id == newList[newItemPosition].id;
  }
}
