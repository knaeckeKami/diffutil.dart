import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:diffutil_dart/src/model/diffupdate.dart';
import 'package:diffutil_dart/src/model/diffupdate_with_data.dart';
import 'package:test/test.dart';

void main() {
  group('basis behaviour: ', () {
    test('same list should have no diff', () {
      final updates =
          diffutil.calculateListDiff([1, 2, 3], [1, 2, 3]).getUpdatesWithData();

      expect(updates, isEmpty);
    });

    test(
        'empty list -> [1,2,3] should have one call to onInserted with count of 3 on position 0',
        () {
      final updates =
          diffutil.calculateListDiff<int>([], [1, 2, 3]).getUpdatesWithData();

      expect(updates, const [
        DataInsert(position: 0, data: 3),
        DataInsert(position: 0, data: 2),
        DataInsert(position: 0, data: 1),
      ]);
    });

    test(
        '[1,2,3] -> empty list should have one call to onRemoved with count of 3 on position 0',
        () {
      final updates =
          diffutil.calculateListDiff<int>([1, 2, 3], []).getUpdatesWithData();

      expect(updates, const [
        DataRemove(position: 2, data: 3),
        DataRemove(position: 1, data: 2),
        DataRemove(position: 0, data: 1)
      ]);
    });

    test('[1,2,3] -> [1,2,4] list should have one insert and one remove', () {
      final updates =
          diffutil.calculateListDiff([1, 2, 3], [1, 0, 3]).getUpdatesWithData();

      expect(updates, const <DataDiffUpdate<int>>[
        DataRemove(position: 1, data: 2),
        DataInsert(position: 1, data: 0)
      ]);
    });

    test(
        '[1,2,3] -> [1,4,1] list should have one call to onChanged on position 2',
        () {
      final updates = diffutil
          .calculateListDiff([1, 2, 3], [1, 3, 4, 5]).getUpdatesWithData();

      expect(updates, const <DataDiffUpdate<int>>[
        DataInsert(position: 3, data: 5),
        DataInsert(position: 3, data: 4),
        DataRemove(position: 1, data: 2)
      ]);
    });

    test('should not emit moves when move detection is disabled', () {
      final updates = diffutil.calculateListDiff([0, 1, 2, 3], [2, 1],
          detectMoves: false).getUpdatesWithData();

      expect(updates, const [
        DataRemove(position: 3, data: 3),
        DataRemove(position: 2, data: 2),
        DataRemove(position: 0, data: 0),
        DataInsert(position: 0, data: 2),
      ]);
    });
  });

  group('change detection: ', () {
    test('onChanged should be called', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 0)], [DataObject(id: 1, payload: 1)]))
          .getUpdatesWithData();

      expect(updates, <DataDiffUpdate<DataObject>>[
        DataChange(
            position: 0,
            oldData: DataObject(id: 1, payload: 0),
            newData: DataObject(id: 1, payload: 1))
      ]);
    });

    test('onChanged should not be called if no payload changed', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1)], [DataObject(id: 1, payload: 1)]))
          .getUpdatesWithData();

      expect(updates, isEmpty);
    });

    test('onInserted works also with change detection', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff([
            DataObject(id: 1, payload: 1),
          ], [
            DataObject(id: 1, payload: 2),
            DataObject(id: 2, payload: 2)
          ]))
          .getUpdatesWithData();

      expect(updates, [
        DataInsert(position: 1, data: DataObject(id: 2, payload: 2)),
        DataChange(
            position: 0,
            oldData: DataObject(id: 1, payload: 1),
            newData: DataObject(id: 1, payload: 2)),
      ]);
    });

    test('onRemoved works also with change detection', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2)]))
          .getUpdatesWithData();

      expect(updates, [
        DataRemove(position: 1, data: DataObject(id: 2, payload: 2)),
        DataChange(
            position: 0,
            oldData: DataObject(id: 1, payload: 1),
            newData: DataObject(id: 1, payload: 2)),
      ]);
    });

    test('onInserted and onRemoved works also with change detection', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2), DataObject(id: 3, payload: 2)]))
          .getUpdatesWithData();

      expect(updates, [
        DataRemove(position: 1, data: DataObject(id: 2, payload: 2)),
        DataInsert(position: 1, data: DataObject(id: 3, payload: 2)),
        DataChange(
            position: 0,
            oldData: DataObject(id: 1, payload: 1),
            newData: DataObject(id: 1, payload: 2)),
      ]);
    });

    test('change detection with payload', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiffWithPayload(
              [DataObject(id: 1, payload: 0)], [DataObject(id: 1, payload: 1)]))
          .getUpdatesWithData();

      expect(updates, [
        DataChange(
            position: 0,
            oldData: DataObject(id: 1, payload: 0),
            newData: DataObject(id: 1, payload: 1))
      ]);
    });
  });

  group('move detection:', () {
    test('should detect moves', () {
      final updates = diffutil.calculateListDiff([1, 2], [2, 1],
          detectMoves: true).getUpdatesWithData();

      expect(updates, const [DataMove(from: 1, to: 0, data: 2)]);
    });

    test('should detect moves and inserts', () {
      final updates = diffutil.calculateListDiff([
        1,
        2
      ], [
        3,
        2,
        1,
      ], detectMoves: true).getUpdatesWithData();

      expect(updates, const [
        DataMove(from: 1, to: 0, data: 2),
        DataInsert(position: 0, data: 3)
      ]);
    });

    test('should detect moves and removes', () {
      final updates = diffutil.calculateListDiff([0, 1, 2, 3], [2, 1],
          detectMoves: true).getUpdatesWithData();

      expect(updates, const [
        DataRemove(position: 3, data: 3),
        DataRemove(position: 0, data: 0),
        DataMove(from: 1, to: 0, data: 2)
      ]);
    });
  });

  test('test custom list diff', () {
    final updates = diffutil.calculateCustomListDiff<int, List<int>>(
        [1, 2, 3], [2, 1, 4, 5],
        detectMoves: true,
        getLength: ((l) => l.length),
        getByIndex: (l, i) => l[i]).getUpdatesWithData();

    expect(updates, const [
      DataRemove(position: 2, data: 3),
      DataInsert(position: 1, data: 5),
      DataInsert(position: 1, data: 4),
      DataMove(from: 3, to: 0, data: 2)
    ]);
  });

  test('change detection + move detection', () {
    final updates = diffutil
        .calculateDiff<DataObject>(
            DataObjectListDiff([
              DataObject(id: 1, payload: 1),
              DataObject(id: 2, payload: 2)
            ], [
              DataObject(id: 0, payload: -1),
              DataObject(id: 2, payload: 3),
              DataObject(id: 1, payload: 1),
              DataObject(id: 3, payload: 2)
            ]),
            detectMoves: true)
        .getUpdatesWithData();

    expect(updates, <DataDiffUpdate<DataObject>>[
      DataInsert(position: 1, data: DataObject(id: 3, payload: 2)),
      DataMove(from: 2, to: 0, data: DataObject(id: 2, payload: 3)),
      DataChange(
          position: 0,
          oldData: DataObject(id: 2, payload: 2),
          newData: DataObject(id: 2, payload: 3)),
      DataInsert(
        position: 0,
        data: DataObject(id: 0, payload: -1),
      )
    ]);
  });

  test('change detection + move detection 2', () {
    final updates = diffutil
        .calculateDiff<DataObject>(
            DataObjectListDiff([
              DataObject(id: 1, payload: 1),
              DataObject(id: 2, payload: 2)
            ], [
              DataObject(id: 1, payload: 0),
              DataObject(id: 2, payload: 3),
              DataObject(id: 1, payload: 1)
            ]),
            detectMoves: true)
        .getUpdatesWithData();

    expect(updates, [
      DataInsert(position: 2, data: DataObject(id: 1, payload: 1)),
      DataChange(
        position: 1,
        oldData: DataObject(id: 2, payload: 2),
        newData: DataObject(id: 2, payload: 3),
      ),
      DataChange(
        position: 0,
        oldData: DataObject(id: 1, payload: 1),
        newData: DataObject(id: 1, payload: 0),
      ),
    ]);
  });

  test('change detection + move detection 3', () {
    final updates = diffutil
        .calculateDiff<DataObject>(
            DataObjectListDiff([
              DataObject(id: 1, payload: 1),
              DataObject(id: 3, payload: 0),
              DataObject(id: 2, payload: 2),
            ], [
              DataObject(id: 3, payload: 1),
              DataObject(id: 1, payload: 0),
            ]),
            detectMoves: true)
        .getUpdatesWithData();

    expect(updates, [
      DataRemove(position: 2, data: DataObject(id: 2, payload: 2)),
      DataChange(
          position: 1,
          oldData: DataObject(id: 3, payload: 0),
          newData: DataObject(id: 3, payload: 1)),
      DataMove(from: 0, to: 1, data: DataObject(id: 1, payload: 1)),
      DataChange(
          position: 1,
          oldData: DataObject(id: 1, payload: 1),
          newData: DataObject(id: 1, payload: 0))
    ]);
  });
}

class DataObjectListDiff extends diffutil.ListDiffDelegate<DataObject> {
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

class DataObjectListDiffWithPayload
    extends diffutil.ListDiffDelegate<DataObject> {
  DataObjectListDiffWithPayload(
      List<DataObject> oldList, List<DataObject> newList)
      : super(oldList, newList);

  @override
  bool areContentsTheSame(int oldItemPosition, int newItemPosition) {
    return equalityChecker(oldList[oldItemPosition], newList[newItemPosition]);
  }

  @override
  bool areItemsTheSame(int oldItemPosition, int newItemPosition) {
    return oldList[oldItemPosition].id == newList[newItemPosition].id;
  }

  @override
  Object? getChangePayload(int oldItemPosition, int newItemPosition) {
    return newList[newItemPosition].payload;
  }
}

class DataObject {
  final int? id;
  final int? payload;

  DataObject({this.id, this.payload});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataObject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          payload == other.payload;

  @override
  int get hashCode => id.hashCode ^ payload.hashCode;

  @override
  String toString() {
    return 'DataObject{id: $id, payload: $payload}';
  }
}
