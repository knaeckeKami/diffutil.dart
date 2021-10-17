import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:test/test.dart';

void main() {
  test('when() works', () {
    const updates = <diffutil.DataDiffUpdate<int>>[
      diffutil.DataInsert(position: 0, data: 0),
      diffutil.DataRemove(position: 1, data: 1),
      diffutil.DataChange(position: 1, newData: 2, oldData: 3),
      diffutil.DataMove(from: 1, to: 2, data: 4),
    ];

    for (final update in updates) {
      update.when(
        insert: (pos, data) => expect(update, isA<diffutil.DataInsert<int>>()),
        remove: (pos, data) => expect(update, isA<diffutil.DataRemove<int>>()),
        change: (pos, oldData, newData) =>
            expect(update, isA<diffutil.DataChange<int>>()),
        move: (from, to, data) => expect(update, isA<diffutil.DataMove<int>>()),
      );
    }
  });

  group(('when() detailed tests'), () {
    test('when() insert', () {
      const diffutil.DataInsert(position: 0, data: 1).when(
        insert: (pos, data) {
          expect(pos, 0);
          expect(data, 1);
        },
        remove: (pos, data) => fail("should not be remove"),
        change: (pos, oldData, newData) => fail("should not be change"),
        move: (from, to, data) => fail("should not be move"),
      );
    });

    test('when() remove', () {
      const diffutil.DataRemove(position: 0, data: 1).when(
        insert: (pos, data) => fail("should not be insert"),
        remove: (pos, data) => () {
          expect(pos, 0);
          expect(data, 1);
        },
        change: (pos, oldData, newData) => fail("should not be change"),
        move: (from, to, data) => fail("should not be move"),
      );
    });

    test('when() change', () {
      const diffutil.DataChange(position: 0, oldData: 1, newData: 2).when(
        insert: (pos, data) => fail("should not be insert"),
        remove: (pos, data) => fail("should not be remove"),
        change: (pos, oldData, newData) {
          expect(pos, 0);
          expect(oldData, 1);
          expect(newData, 2);
        },
        move: (from, to, data) => fail("should not be move"),
      );
    });

    test('when() move', () {
      const diffutil.DataMove(from: 1, to: 2, data: 3).when(
          insert: (pos, data) => fail("should not be insert"),
          remove: (pos, data) => fail("should not be remove"),
          change: (pos, oldData, newData) => fail("should not be change"),
          move: (from, to, data) {
            expect(from, 1);
            expect(to, 2);
            expect(data, 3);
          });
    });
  });

  test('equals/hashcode works', () {
    expect({
      const diffutil.Insert(count: 1, position: 1),
      const diffutil.Insert(
          count: 1, position: 1), //ignore: equal_elements_in_set
    }, hasLength(1));
    expect({
      const diffutil.Remove(count: 1, position: 1),
      const diffutil.Remove(
          count: 1, position: 1), //ignore: equal_elements_in_set
    }, hasLength(1));
    expect({
      const diffutil.Change(position: 1),
      const diffutil.Change(position: 1), //ignore: equal_elements_in_set
    }, hasLength(1));
    expect({
      const diffutil.Move(from: 1, to: 2),
      const diffutil.Move(from: 1, to: 2), //ignore: equal_elements_in_set
    }, hasLength(1));
  });
}
