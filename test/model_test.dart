import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:test/test.dart';

//ignore_for_file: equal_elements_in_set
void main() {
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

    expect({
      const diffutil.Insert(count: 1, position: 1),
      const diffutil.Insert(count: 2, position: 2),
    }, hasLength(2));
    expect({
      const diffutil.Remove(count: 1, position: 1),
      const diffutil.Remove(count: 2, position: 2),
    }, hasLength(2));
    expect({
      const diffutil.Change(position: 1),
      const diffutil.Change(position: 12),
    }, hasLength(2));
    expect({
      const diffutil.Move(from: 1, to: 2),
      const diffutil.Move(from: 2, to: 1),
    }, hasLength(2));
  });

  test('toString()', () {
    expect(const diffutil.Insert(position: 1, count: 2).toString(),
        'Insert{position: 1, count: 2}');
    expect(const diffutil.Remove(position: 1, count: 2).toString(),
        'Remove{position: 1, count: 2}');
    expect(const diffutil.Change(position: 1, payload: 2).toString(),
        'Change{position: 1, payload: 2}');
    expect(
        const diffutil.Move(from: 1, to: 2).toString(), 'Move{from: 1, to: 2}');
  });
}
