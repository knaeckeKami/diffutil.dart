## 5.0.0

- BREAKING: optimize exact diff calculation by trimming matching suffixes before running Myers. This keeps diffs minimal, but duplicate-heavy lists may now choose a different valid anchor/update position than 4.x.
- Improve common diff performance by reusing typed-data buffers for k-lines/status arrays and interning larger non-aligned list diffs.
- Add an AOT/JIT benchmark harness under `tool/bench/bench.dart`.
- Add hash-collision regression tests for both update APIs.

## 4.0.1

- fix endless loopi/wrong result in certain cases (#21, #18)

## 4.0.0

- Fix bug that caused wrong update list to be returned when the list would contain duplicate items (see https://github.com/knaeckeKami/diffutil.dart/issues/15)
- BREAKING: add sealed class modifiers to data classes, require Dart 3.0

## 3.0.0


- added `DiffResult::getUpdatesWithData`. To make this work, following changes have been made: 
    -  The functions `calculateDiff()`, `calculateListDiff`, `calculateCustomListDiff` now have an additional 
       generic type parameter. This is a breaking change (if you used `calculateCustomListDiff`
       with a single explicit type parameter, it now has two)
    - `DiffResult`has now a generic type parameter for the type of the data of the underlying lists
    

## 2.0.0

- stable nullsafe release

## 2.0.0-nullsafety.0

- removed deprecated methods
- migrate to nullsafety

## 1.0.2

- More tests, add github action badges

## 1.0.1

- Relax version constraint of package meta

## 1.0.0

Major revamp to make the libary more Dart-y and less cumbersome to use!

- Add ability to calculate the changeset as list of DiffUpdate object, where each object is of type Insert, Remove, Change or Insert
- Ability to turn off changeset batching (See README for an explanation on changeset batching)
- Improved the example

- Deprecated the old way the get the changeset via ListUpdateCallback.

## 0.1.0+1

- more tests

## 0.1.0

- Fix bug in move detection
- Tighten up privacy of instance variables that were unnecessarily public
- add tests

## 0.0.7

Fix lint errors

## 0.0.6

Fix missing exports

## 0.0.5

Add support for custom list-like types

## 0.0.4

Add example

## 0.0.3

Update Package description

## 0.0.2

Dokumentation Fixes


## 0.0.1 - Initial Release
