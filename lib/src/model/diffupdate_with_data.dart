sealed class DataDiffUpdate<T> {
  const factory DataDiffUpdate.insert(
      {required int position, required T data}) = DataInsert;

  const factory DataDiffUpdate.remove(
      {required int position, required T data}) = DataRemove;

  const factory DataDiffUpdate.change(
      {required int position,
      required T oldData,
      required T newData}) = DataChange;

  const factory DataDiffUpdate.move(
      {required int from, required int to, required T data}) = DataMove;

  /// call one of the given callback functions depending on the type of this object.
  ///
  /// @param insert callback function to be called if this object is of type [DataInsert]
  /// @param remove callback function to be called if this object is of type [DateRemove]
  /// @param change callback function to be called if this object is of type [DateChange]
  /// @param move callback function to be called if this object is of type [DateMove]
  ///
  S when<S>({
    required S Function(int position, T data) insert,
    required S Function(int position, T data) remove,
    required S Function(int position, T oldData, T newData) change,
    required S Function(int from, int to, T data) move,
  });
}

class DataInsert<T> implements DataDiffUpdate<T> {
  final int position;

  final T data;

  const DataInsert({
    required this.position,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataInsert &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          data == other.data;

  @override
  int get hashCode => position.hashCode ^ data.hashCode;

  @override
  S when<S>(
      {required S Function(int p1, T p2) insert,
      required S Function(int p1, T p2)? remove,
      required S Function(int position, T oldData, T newData) change,
      required S Function(int p1, int p2, T data)? move}) {
    return insert(position, data);
  }

  @override
  String toString() {
    return 'Insert{position: $position, data: $data}';
  }
}

class DataRemove<T> implements DataDiffUpdate<T> {
  final int position;

  final T data;

  const DataRemove({
    required this.position,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataRemove &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          data == other.data;

  @override
  int get hashCode => position.hashCode ^ data.hashCode;

  @override
  S when<S>(
      {S Function(int p1, T p2)? insert,
      required S Function(int p1, T p2) remove,
      S Function(int position, T oldData, T newData)? change,
      S Function(int p1, int p2, T data)? move}) {
    return remove(position, data);
  }

  @override
  String toString() {
    return 'Remove{position: $position, data: $data}';
  }
}

class DataChange<T> implements DataDiffUpdate<T> {
  final int position;
  final T oldData;

  final T newData;

  const DataChange(
      {required this.position, required this.oldData, required this.newData});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataChange &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          oldData == other.oldData &&
          newData == other.newData;

  @override
  int get hashCode => position.hashCode ^ newData.hashCode;

  @override
  S when<S>(
      {required S Function(int p1, T p2) insert,
      required S Function(int p1, T p2) remove,
      required S Function(int p1, T p2, T p3) change,
      required S Function(int p1, int p2, T data) move}) {
    return change(position, oldData, newData);
  }

  @override
  String toString() {
    return 'Change{position: $position, old data: $oldData, new data: $newData}';
  }
}

class DataMove<T> implements DataDiffUpdate<T> {
  final int from;
  final int to;
  final T data;

  const DataMove({
    required this.from,
    required this.to,
    required this.data,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataMove &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to &&
          data == other.data;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;

  @override
  S when<S>(
      {S Function(int p1, T p2)? insert,
      S Function(int p1, T p2)? remove,
      S Function(int position, T oldData, T newData)? change,
      required S Function(int p1, int p2, T data) move}) {
    return move(from, to, data);
  }

  @override
  String toString() {
    return 'Move{from: $from, to: $to, data: $data}';
  }
}
