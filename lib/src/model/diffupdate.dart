sealed class DiffUpdate {
  const factory DiffUpdate.insert({required int position, required int count}) =
      Insert;

  const factory DiffUpdate.remove({required int position, required int count}) =
      Remove;

  const factory DiffUpdate.change({required int position, Object? payload}) =
      Change;

  const factory DiffUpdate.move({required int from, required int to}) = Move;
}

abstract class BatchableDiff {
  int get position;

  int get count;
}

class Insert implements DiffUpdate, BatchableDiff {
  @override
  final int position;
  @override
  final int count;

  const Insert({required this.position, required this.count});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Insert &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          count == other.count;

  @override
  int get hashCode => position.hashCode ^ count.hashCode;

  @override
  String toString() {
    return 'Insert{position: $position, count: $count}';
  }
}

class Remove implements DiffUpdate, BatchableDiff {
  @override
  final int position;
  @override
  final int count;

  const Remove({required this.position, required this.count});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Remove &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          count == other.count;

  @override
  int get hashCode => position.hashCode ^ count.hashCode;


  @override
  String toString() {
    return 'Remove{position: $position, count: $count}';
  }
}

class Change implements DiffUpdate {
  final int position;
  final Object? payload;

  const Change({required this.position, this.payload});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Change &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          payload == other.payload;

  @override
  int get hashCode => position.hashCode ^ payload.hashCode;

  @override
  String toString() {
    return 'Change{position: $position, payload: $payload}';
  }
}

class Move implements DiffUpdate {
  final int from;
  final int to;

  const Move({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Move &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;

  @override
  String toString() {
    return 'Move{from: $from, to: $to}';
  }
}
