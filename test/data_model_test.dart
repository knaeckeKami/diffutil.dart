import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:test/test.dart';

//ignore_for_file: equal_elements_in_set

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
      const diffutil.DataInsert(data: null, position: 1),
      const diffutil.DataInsert(data: null, position: 1),
    }, hasLength(1));
    expect({
      const diffutil.DataRemove(data: null, position: 1),
      const diffutil.DataRemove(data: null, position: 1),
    }, hasLength(1));
    expect({
      const diffutil.DataChange(position: 1, oldData: null, newData: 1),
      const diffutil.DataChange(position: 1, oldData: null, newData: 1),
    }, hasLength(1));
    expect({
      const diffutil.DataMove(from: 1, to: 2, data: null),
      const diffutil.DataMove(from: 1, to: 2, data: null),
    }, hasLength(1));

    expect({
      const diffutil.DataInsert(data: null, position: 1),
      const diffutil.DataInsert(data: 1, position: 1),
    }, hasLength(2));
    expect({
      const diffutil.DataRemove(data: null, position: 1),
      const diffutil.DataRemove(data: 1, position: 1),
    }, hasLength(2));
    expect({
      const diffutil.DataChange(position: 1, oldData: null, newData: 1),
      const diffutil.DataChange(position: 1, oldData: null, newData: 2),
    }, hasLength(2));
    expect({
      const diffutil.DataMove(from: 1, to: 2, data: null),
      const diffutil.DataMove(from: 1, to: 2, data: 1),
    }, hasLength(2));
  });

  test('toString()', () {
    expect(const diffutil.DataInsert(position: 1, data: 2).toString(),
        'Insert{position: 1, data: 2}');
    expect(const diffutil.DataRemove(position: 1, data: 2).toString(),
        'Remove{position: 1, data: 2}');
    expect(
        const diffutil.DataChange(position: 1, oldData: 2, newData: 3)
            .toString(),
        'Change{position: 1, old data: 2, new data: 3}');
    expect(const diffutil.DataMove(from: 1, to: 2, data: 3).toString(),
        'Move{from: 1, to: 2, data: 3}');
  });
}
