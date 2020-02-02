# diffutil

Calculate the difference between two lists.

Heavily inspired bei Android's [DiffUtil](https://developer.android.com/reference/kotlin/androidx/recyclerview/widget/DiffUtil) class, the code was adopted for Dart.

Uses Myers algorithm internally. 

## Usage

### Calculating diffs:

Simple usage:

```dart
final diffResult = calculateListDiff([1, 2 ,3], [1, 3, 4]);
```

Custom equality:

```dart
final diffResult = calculateListDiff(oldList, newList, (o1, o2) => o1.id == o2.id);
```

If you don't want to use plain old Dart lists (for example if you're using built_value or kt.dart), and don't want to convert your custom list 
to standard lists, you can use
the `calculateDiff` function and implement your own `DiffDelegate` easily.



## Performance metrics:

Same as Android's DiffUtil:

 - O(N) space 
 - O(N + D^2) time performance where D is the length of the edit script.
 - additional O(N^2) time where N is the total number of added and removed items if move detection is enabled