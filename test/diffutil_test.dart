import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:mockito/mockito.dart' as mockito;
import 'package:test/test.dart';

void main() {
  MockitoDiffCallback mockCallback;

  setUp(() {
    mockCallback = MockitoDiffCallback();
  });

  group("basis behaviour: ", () {
    test("same list should have no diff", () {
      diffutil.calculateListDiff(
          [1, 2, 3], [1, 2, 3]).dispatchUpdatesTo(mockCallback);

      mockito.verifyZeroInteractions(mockCallback);
    });

    test(
        "empty list -> [1,2,3] should have one call to onInserted with count of 3 on position 0",
        () {
      diffutil.calculateListDiff([], [1, 2, 3]).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onInserted(0, 3));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test(
        "[1,2,3] -> empty list should have one call to onRemoved with count of 3 on position 0",
        () {
      diffutil.calculateListDiff([1, 2, 3], []).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onRemoved(0, 3));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test(
        "[1,2,3] -> [1,2,4] list should have one call to onChanged on position 2",
        () {
      diffutil.calculateListDiff(
          [1, 2, 3], [1, 0, 3]).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onRemoved(
        1,
        1,
      ));
      mockito.verify(mockCallback.onInserted(
        1,
        1,
      ));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test(
        "[1,2,3] -> [1,4,1] list should have one call to onChanged on position 2",
        () {
      diffutil.calculateListDiff(
          [1, 2, 3], [1, 3, 4, 5]).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onInserted(
        3,
        2,
      ));
      mockito.verify(mockCallback.onRemoved(
        1,
        1,
      ));

      mockito.verifyNoMoreInteractions(mockCallback);
    });
  });

  group("change detection: ", () {
    test("onChanged should be called", () {
      diffutil
          .calculateDiff(DataObjectListDiff(
              [DataObject(id: 1, payload: 0)], [DataObject(id: 1, payload: 1)]))
          .dispatchUpdatesTo(mockCallback);
      mockito.verify(mockCallback.onChanged(0, 1, null));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test("onChanged should not be called if no payload changed", () {
      diffutil
          .calculateDiff(DataObjectListDiff(
              [DataObject(id: 1, payload: 1)], [DataObject(id: 1, payload: 1)]))
          .dispatchUpdatesTo(mockCallback);

      mockito.verifyZeroInteractions(mockCallback);
    });

    test("onInserted works also with change detection", () {
      diffutil
          .calculateDiff(DataObjectListDiff([
            DataObject(id: 1, payload: 1),
          ], [
            DataObject(id: 1, payload: 2),
            DataObject(id: 2, payload: 2)
          ]))
          .dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onChanged(0, 1, null));

      mockito.verify(mockCallback.onInserted(1, 1));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test("onRemoved works also with change detection", () {
      diffutil
          .calculateDiff(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2)]))
          .dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onChanged(0, 1, null));

      mockito.verify(mockCallback.onRemoved(1, 1));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test("onInserted and onRemoved works also with change detection", () {
      diffutil
          .calculateDiff(DataObjectListDiff(
              [DataObject(id: 1, payload: 1), DataObject(id: 2, payload: 2)],
              [DataObject(id: 1, payload: 2), DataObject(id: 3, payload: 2)]))
          .dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onChanged(0, 1, null));

      mockito.verify(mockCallback.onInserted(1, 1));

      mockito.verify(mockCallback.onRemoved(1, 1));

      mockito.verifyNoMoreInteractions(mockCallback);
    });
  });

  group("move detection:", () {
    test("should detect moves", () {
      diffutil.calculateListDiff([1, 2], [2, 1],
          detectMoves: true).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onMoved(1, 0));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test("should detect moves and inserts", () {
      diffutil.calculateListDiff([
        1,
        2
      ], [
        3,
        2,
        1,
      ], detectMoves: true).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onMoved(1, 0));

      mockito.verify(mockCallback.onInserted(0, 1));

      mockito.verifyNoMoreInteractions(mockCallback);
    });

    test("should detect moves and removes", () {
      diffutil.calculateListDiff([0, 1, 2, 3], [2, 1],
          detectMoves: true).dispatchUpdatesTo(mockCallback);

      mockito.verify(mockCallback.onRemoved(3, 1));

      mockito.verify(mockCallback.onRemoved(0, 1));

      mockito.verify(mockCallback.onMoved(1, 0));

      mockito.verifyNoMoreInteractions(mockCallback);
    });
  });

  test("test custom list diff", () {
    diffutil.calculateCustomListDiff<int, List<int>>([1, 2, 3], [2, 1, 4, 5],
        detectMoves: true,
        getLength: (l) => l.length,
        getByIndex: (l, i) => l[i]).dispatchUpdatesTo(mockCallback);

    mockito.verify(mockCallback.onRemoved(2, 1));

    mockito.verify(mockCallback.onInserted(1, 2));

    mockito.verify(mockCallback.onMoved(3, 0));

    mockito.verifyNoMoreInteractions(mockCallback);
  });

  test("change detection + move detection", () {
    diffutil
        .calculateDiff(
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
        .dispatchUpdatesTo(mockCallback);

    mockito.verify(mockCallback.onInserted(1, 1));
    mockito.verify(mockCallback.onMoved(2, 0));
    mockito.verify(mockCallback.onChanged(0, 1, null));
    mockito.verify(mockCallback.onInserted(0, 1));

    mockito.verifyNoMoreInteractions(mockCallback);
  });

  test("change detection + move detection 2", () {
    diffutil
        .calculateDiff(
            DataObjectListDiff([
              DataObject(id: 1, payload: 1),
              DataObject(id: 2, payload: 2)
            ], [
              DataObject(id: 1, payload: 0),
              DataObject(id: 2, payload: 3),
              DataObject(id: 1, payload: 1)
            ]),
            detectMoves: true)
        .dispatchUpdatesTo(mockCallback);

    mockito.verify(mockCallback.onInserted(2, 1));
    mockito.verify(mockCallback.onChanged(0, 2, null));

    mockito.verifyNoMoreInteractions(mockCallback);
  });

  test("change detection + move detection 3", () {
    diffutil
        .calculateDiff(
            DataObjectListDiff([
              DataObject(id: 1, payload: 1),
              DataObject(id: 3, payload: 0),
              DataObject(id: 2, payload: 2),
            ], [
              DataObject(id: 3, payload: 1),
              DataObject(id: 1, payload: 0),
            ]),
            detectMoves: true)
        .dispatchUpdatesTo(mockCallback);

    mockito.verifyInOrder([
      mockCallback.onRemoved(2, 1),
      mockCallback.onChanged(1, 1, null),
      mockCallback.onMoved(0, 1),
      mockCallback.onChanged(1, 1, null)
    ]);

    mockito.verifyNoMoreInteractions(mockCallback);
  });
}

class MockitoDiffCallback extends mockito.Mock
    implements diffutil.ListUpdateCallback {}

class DataObject {
  final int id;
  final int payload;

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
