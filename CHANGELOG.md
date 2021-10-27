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
