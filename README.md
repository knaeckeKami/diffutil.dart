# diffutil.dart

[![Pub Package](https://img.shields.io/pub/v/diffutil_dart.svg)](https://pub.dartlang.org/packages/diffutil_dart)
[![Build Status](https://github.com/knaeckeKami/diffutil.dart/workflows/Build/badge.svg)](https://github.com/knaeckeKami/diffutil.dart/actions)
[![codecov](https://codecov.io/gh/knaeckeKami/diffutil.dart/branch/master/graph/badge.svg)](https://codecov.io/gh/knaeckeKami/diffutil.dart)


Calculate the difference between two lists.

Heavily inspired bei Android's [DiffUtil](https://developer.android.com/reference/kotlin/androidx/recyclerview/widget/DiffUtil) class, the code was adopted for Dart.

Uses Myers algorithm internally. 


## What is this good for?

There are often situations, where an app displays a list of items, which are fetched from an external data source like a server endpoint or a database, and updates are not
sent as delta, but as a whole new list.

It can be useful to take the old list and the new list and calculate the difference between those two, for example when animating the insertion and removal of new
items in the displayed list (See [diffutil_sliverlist](https://pub.dev/packages/diffutil_sliverlist)).

This package does exactly that:
It takes two lists and calculates the difference (or to be more accurate: edit script) between those two lists as list of Insert, Remove, Change and Move operations.


## Usage

### Calculating diffs:

Simple usage:

```dart
final diffResult = calculateListDiff<int>([1, 2 ,3], [1, 3, 4]);
```

Custom equality:

```dart
final diffResult = calculateListDiff<YourClassWithId>(oldList, newList, (o1, o2) => o1.id == o2.id);
```

If you don't want to use plain old Dart lists (for example if you're using built_value or kt.dart), and don't want to convert your custom list 
to standard lists, you can use
the `calculateDiff` function and implement your own `DiffDelegate` easily.

Or use `calculateCustomListDiff` and `CustomListDiffDelegate`.

Move detection is disabled by default. 

### Using the result:

Call `.getUpdates()` on the `diffResult` to get a List of `DiffUpdate` objects. These are sealed classes of type Insert, Remove, Change or Move.
Move operations are only calculated if `calculateListDiff` was called with `detectMoves: true`


```dart
  for (final update in diffResult.getUpdates())
    update.when(
      insert: (pos, count) => print("inserted $count on $pos"),
      remove: (pos, count) => print("removed $count on $pos"),
      change: (pos, payload) => print("changed on $pos with payload $payload"),
      move: (from, to) => print("move $from to $to"),
    );
```

By default, `Insert` and `Remove` Operations are batched. (e.g. multiple consecutive inserts or removes are represented by a single `Insert`/`Remove` object with a `count` field > 1).
If you want to turn off edit script batching, call `getUpdates(batch: false)`.
This means, every `Insert` and `Remove` operation will have a count of 1 and the edit script of `[]` and `[1, 2]` will be 

`[Insert(position: 0, count : 1), Insert(position: 0, count :1 )]` 

instead of

`[Insert(position: 0, count: 2)]`

## Updates with data

If you need the concrete items that have been inserted/removed/changed/moved, call `getUpdatesWithData()`.

```dart

     diffutil.calculateListDiff([1, 2, 3], [1, 0, 3]).getUpdatesWithData();

```

returns

```dart
      [
        DataRemove(position: 1, data: 2),
        DataInsert(position: 1, data: 0)
      ];
```

The result of ``getUpdatesWithData`()` cannot be batched.
You can use the resulting `Iterable<DataDiffUpdate>` like this:

```dart
 for (final update in updates) {
      update.when(
        insert: (pos, data) => print('insert $pos $data'),
        remove: (pos, data) => print('remove $pos $data'),
        change: (pos, oldData, newData) => print('change on $pos from $oldData to $newData'),
        move: (from, to, data) => print('move $data from $from to $to'),
      );
    }

```

Note that if you implement you own `DiffDelegate` and call `calculateDiff()` directly, the 
`DiffDelegate` also needs to implement `IndexableItemDiffDelegate` if you want to call `getUpdatesWithData()`.

## Performance metrics:

Same as Android's DiffUtil:

 - O(N) space 
 - O(N + D^2) time performance where D is the length of the edit script.
 - additional O(N^2) time where N is the total number of added and removed items if move detection is enabled
 
 The edit script is the smallest set of operations needed to transform the first list into the second list.

