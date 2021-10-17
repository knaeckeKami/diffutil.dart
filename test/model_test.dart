import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:test/test.dart';

void main() {
  test('when() works', () {
    const updates = <diffutil.DiffUpdate>[
      diffutil.Insert(count: 1, position: 1),
      diffutil.Remove(count: 1, position: 1),
      diffutil.Change(position: 1),
      diffutil.Move(from: 1, to: 2),
    ];

    for (final update in updates) {
      update.when(
        insert: (count, pos) => expect(update, isA<diffutil.Insert>()),
        remove: (count, pos) => expect(update, isA<diffutil.Remove>()),
        change: (count, pos) => expect(update, isA<diffutil.Change>()),
        move: (from, to) => expect(update, isA<diffutil.Move>()),
      );
    }
  });

  test('equals/hashcode works', () {
    expect({
      const diffutil.Insert(count: 1, position: 1),
      const diffutil.Insert(count: 1, position: 1),
    }, hasLength(1));
    expect({
      const diffutil.Remove(count: 1, position: 1),
      const diffutil.Remove(count: 1, position: 1),
    }, hasLength(1));
    expect({
      const diffutil.Change(position: 1),
      const diffutil.Change(position: 1),
    }, hasLength(1));
    expect({
      const diffutil.Move(from: 1, to: 2),
      const diffutil.Move(from: 1, to: 2),
    }, hasLength(1));
  });
}
