import 'package:diffutil_dart/diffutil.dart' as diffutil;

/// Note: This is a dart-only project, running flutter pub get will fail with an error message of a missing
/// pubspec.yaml in the example folder. Just run pub get instead.

void main() {

  final List<int> oldList = [10, 20,30];
  final List<int> newList = [30,40];

  final diffResult = diffutil.calculateListDiff(
    oldList,
    newList,
  );

  for (var update in diffResult.getUpdates(batch: false)) {
    update.when(
      insert: (position, count, item) {
        print("inserted count:$count on pos $position. it was the item $item}");
        return;
      },
      remove: (position, count, item) {
        print("removed on pos $position. it was $item}");
        return;
      },
      change: (position, payload) {
        return;
      },
      move: (from, to) {
        print("move in oldList element $from to $to");
        return;
      },
    );
  }

}
