import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:test/test.dart';

//ignore_for_file: equal_elements_in_set

void main() {
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
