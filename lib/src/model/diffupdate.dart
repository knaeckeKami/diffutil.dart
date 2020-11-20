abstract class DiffUpdate {
  const factory DiffUpdate.insert({required int position, required int count}) =
      Insert;

  const factory DiffUpdate.remove({required int position, required int count}) =
      Remove;

  const factory DiffUpdate.change({required int position, Object? payload}) =
      Change;

  const factory DiffUpdate.move({required int from, required int to}) = Move;

  /// call one of the given callback functions depending on the type of this object.
  ///
  /// @param insert callback function to be called if this object is of type [Insert]
  /// @param remove callback function to be called if this object is of type [Remove]
  /// @param change callback function to be called if this object is of type [Change]
  /// @param move callback function to be called if this object is of type [Move]
  ///
  T when<T>({
    required T Function(int position, int count) insert,
    required T Function(int position, int count) remove,
    required T Function(int position, Object? payload) change,
    required T Function(int from, int to) move,
  });
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
  T when<T>(
      {required T Function(int p1, int p2) insert,
      required T Function(int p1, int p2)? remove,
      required T Function(int p1, Object? p2)? change,
      required T Function(int p1, int p2)? move}) {
    return insert(position, count);
  }

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
  T when<T>(
      {T Function(int p1, int p2)? insert,
      required T Function(int p1, int p2) remove,
      T Function(int p1, Object p2)? change,
      T Function(int p1, int p2)? move}) {
    return remove(position, count);
  }

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
  T when<T>(
      {required T Function(int p1, int p2) insert,
      required T Function(int p1, int p2) remove,
      required T Function(int p1, Object? p2) change,
      required T Function(int p1, int p2) move}) {
    return change(position, payload);
  }

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
  T when<T>(
      {required T Function(int p1, int p2)? insert,
      required T Function(int p1, int p2)? remove,
      required T Function(int p1, Object p2)? change,
      required T Function(int p1, int p2) move}) {
    return move(from, to);
  }

  @override
  String toString() {
    return 'Move{from: $from, to: $to}';
  }
}
