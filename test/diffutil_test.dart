import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:diffutil_dart/src/model/diffupdate.dart';
import 'package:test/test.dart';

void main() {
  group('basis behaviour: ', () {
    test('same list should have no diff', () {
      final updates =
          diffutil.calculateListDiff([1, 2, 3], [1, 2, 3]).getUpdates();

      expect(updates, isEmpty);
    });

    test(
        'empty list -> [1,2,3] should have one call to onInserted with count of 3 on position 0',
        () {
      final updates =
          diffutil.calculateListDiff([], [1, 2, 3]).getUpdates(batch: true);

      expect(updates, const [Insert(position: 0, count: 3)]);
    });

    test(
        '[1,2,3] -> empty list should have one call to onRemoved with count of 3 on position 0',
        () {
      final updates = diffutil.calculateListDiff([1, 2, 3], []).getUpdates();

      expect(updates, const [diffutil.Remove(position: 0, count: 3)]);
    });

    test('[1,2,3] -> [1,2,4] list should have one insert and one remvove', () {
      final updates =
          diffutil.calculateListDiff([1, 2, 3], [1, 0, 3]).getUpdates();

      expect(updates, [
        const Remove(position: 1, count: 1),
        const Insert(position: 1, count: 1)
      ]);
    });

    test(
        '[1,2,3] -> [1,4,1] list should have one call to onChanged on position 2',
        () {
      final updates =
          diffutil.calculateListDiff([1, 2, 3], [1, 3, 4, 5]).getUpdates();

      expect(updates, [
        const Insert(position: 3, count: 2),
        const Remove(position: 1, count: 1)
      ]);
    });
  });

  group('change detection: ', () {
    test('onChanged should be called', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 0)], [DataObject(id: 1, payload: 1)]))
          .getUpdates();

      expect(updates, [const Change(position: 0, payload: null)]);
    });

    test('onChanged should not be called if no payload changed', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1)], [DataObject(id: 1, payload: 1)]))
          .getUpdates();

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
          .getUpdates();

      expect(updates, [
        const Insert(position: 1, count: 1),
        const Change(position: 0, payload: null),
      ]);
    });

    test('onRemoved works also with change detection', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2)]))
          .getUpdates();

      expect(updates, [
        const Remove(position: 1, count: 1),
        const Change(position: 0, payload: null),
      ]);
    });

    test('onInserted and onRemoved works also with change detection', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2), DataObject(id: 3, payload: 2)]))
          .getUpdates();

      expect(updates, [
        const Remove(position: 1, count: 1),
        const Insert(count: 1, position: 1),
        const Change(position: 0),
      ]);
    });

    test('change detection with payload', () {
      final updates = diffutil
          .calculateDiff<DataObject>(DataObjectListDiffWithPayload(
              [DataObject(id: 1, payload: 0)], [DataObject(id: 1, payload: 1)]))
          .getUpdates();

      expect(updates, [const Change(position: 0, payload: 1)]);
    });
  });

  group('move detection:', () {
    test('should detect moves', () {
      final updates = diffutil
          .calculateListDiff([1, 2], [2, 1], detectMoves: true).getUpdates();

      expect(updates, [const Move(from: 0, to: 1)]);
    });

    test('should detect moves and inserts', () {
      final updates = diffutil.calculateListDiff([
        1,
        2
      ], [
        3,
        2,
        1,
      ], detectMoves: true).getUpdates();

      expect(updates, [
        const Move(
          from: 1,
          to: 0,
        ),
        const Insert(position: 0, count: 1)
      ]);
    });

    test('should detect moves and removes', () {
      final updates = diffutil.calculateListDiff([0, 1, 2, 3], [2, 1],
          detectMoves: true).getUpdates();

      expect(updates, [
        const Remove(position: 3, count: 1),
        const Move(from: 1, to: 2),
        const Remove(position: 0, count: 1),
      ]);
    });
  });

  test('test custom list diff', () {
    final updates = diffutil.calculateCustomListDiff<int, List<int>>(
        [1, 2, 3], [2, 1, 4, 5],
        detectMoves: true,
        getLength: ((l) => l.length),
        getByIndex: (l, i) => l[i]).getUpdates();

    expect(updates, const [
      Remove(position: 2, count: 1),
      Insert(position: 1, count: 2),
      Move(from: 3, to: 0)
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
        .getUpdates();

    expect(updates, const [
      Insert(position: 2, count: 1),
      Change(position: 1, payload: null),
      Move(from: 0, to: 1),
      Insert(position: 0, count: 1)
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
        .getUpdates();

    expect(updates, [
      const Insert(position: 2, count: 1),
      const Change(position: 0, payload: null),
      const Change(position: 1, payload: null),
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
        .getUpdates();

    expect(updates, [
      const Remove(position: 2, count: 1),
      const Change(position: 1, payload: null),
      const Move(from: 0, to: 1),
      const Change(position: 1, payload: null)
    ]);
  });

  group('test list result calculation', () {
    test('insert works in result list', () {
      expect(
          diffutil
              .calculateListDiff([1, 2, 3], [1, 2, 3])
              .getUpdates(batch: true)
              .toList(),
          isEmpty);

      var updates = diffutil
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
          .getUpdates()
          .toList();

      expect(updates, const [
        DiffUpdate.insert(position: 2, count: 1),
        DiffUpdate.change(position: 0, payload: null),
        DiffUpdate.change(position: 1, payload: null),
      ]);

      updates = diffutil
          .calculateListDiff([0, 1, 2, 3], [2, 1], detectMoves: true)
          .getUpdates(batch: true)
          .toList();

      expect(updates, const [
        DiffUpdate.remove(position: 3, count: 1),
        DiffUpdate.move(from: 1, to: 2),
        DiffUpdate.remove(position: 0, count: 1),
      ]);
    });

    test(
        'empty list -> [1,2,3] should have one call to onInserted with count of 3 on position 0',
        () {
      final updates = diffutil.calculateListDiff([], [1, 2, 3]).getUpdates();

      expect(updates, const [DiffUpdate.insert(position: 0, count: 3)]);
    });

    test(
        '[1,2,3] -> empty list should have one call to onRemoved with count of 3 on position 0',
        () {
      final updates = diffutil
          .calculateListDiff([1, 2, 3], [])
          .getUpdates(batch: true)
          .toList();

      expect(updates, const [DiffUpdate.remove(position: 0, count: 3)]);
    });

    test(
        '[1,2,3] -> empty list should have 3 remove operations when noch batched',
        () {
      final updates = diffutil
          .calculateListDiff([1, 2, 3], [])
          .getUpdates(batch: false)
          .toList();

      expect(updates, const [
        DiffUpdate.remove(position: 2, count: 1),
        DiffUpdate.remove(position: 1, count: 1),
        DiffUpdate.remove(position: 0, count: 1)
      ]);
    });
  });

  group("regression tests", () {
    test(
        "github issue #15 https://github.com/knaeckeKami/diffutil.dart/issues/15",
        () {
      expect(
        diffutil
            .calculateListDiff([1, 0, 2, 0, 3], [1, 0, 3], detectMoves: false)
            .getUpdates(batch: false)
            .toList(),
        const [
          Remove(position: 2, count: 1),
          Remove(position: 1, count: 1),
        ],
      );
    });
  });

  test("github issue #21: move detection bug", () {
    final start = [1, 2, 3, 4, 5, 6];
    final end = [1, 4, 2, 5, 6, 3];

    final updates = diffutil
        .calculateListDiff(start, end, detectMoves: true)
        .getUpdates(batch: false)
        .toList();

    expect(updates, const [
      Move(from: 2, to: 5),
      Move(from: 1, to: 2),
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
}
