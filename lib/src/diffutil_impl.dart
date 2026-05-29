// ignore_for_file: constant_identifier_names

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:diffutil_dart/src/diff_delegate.dart';
import 'package:diffutil_dart/src/model/diffupdate.dart';
import 'package:diffutil_dart/src/model/diffupdate_with_data.dart';

///Snakes represent a match between two lists. It is optionally prefixed or postfixed with an
///add or remove operation. See the Myers' paper for details.
///
final class _Snake {
  /// Position in the old list
  int startX;

  /// Position in the new list
  int startY;

  /// End position in the old list, exclusive
  int endX;

  /// End position in the new list, exclusive
  int endY;

  bool reverse;

  _Snake(
      {required this.startX,
      required this.startY,
      required this.endX,
      required this.endY,
      required this.reverse});

  @pragma("vm:prefer-inline")
  bool hasAdditionOrRemoval() {
    return endY - startY != endX - startX;
  }

  @pragma("vm:prefer-inline")
  bool isAddition() {
    return endY - startY > endX - startX;
  }

  @pragma("vm:prefer-inline")
  int diagonalSize() {
    return min(endX - startX, endY - startY);
  }

  @pragma("vm:prefer-inline")
  _Diagonal toDiagonal() {
    if (hasAdditionOrRemoval()) {
      if (reverse) {
        // snake edge it at the end
        return _Diagonal(startX, startY, diagonalSize());
      } else {
        // snake edge it at the beginning
        if (isAddition()) {
          return _Diagonal(startX, startY + 1, diagonalSize());
        } else {
          return _Diagonal(startX + 1, startY, diagonalSize());
        }
      }
    } else {
      // we are a pure diagonal
      return _Diagonal(startX, startY, endX - startX);
    }
  }
}

///
/// A diagonal is a match in the graph.
/// Rather than snakes, we only record the diagonals in the path.
///
final class _Diagonal {
  final int x;
  final int y;
  final int size;

  _Diagonal(this.x, this.y, this.size);

  @pragma("vm:prefer-inline")
  int endX() {
    return x + size;
  }

  @pragma("vm:prefer-inline")
  int endY() {
    return y + size;
  }
}

@pragma("vm:prefer-inline")
int _diagonalComparator(_Diagonal o1, _Diagonal o2) {
  return o1.x - o2.x;
}

final class _Range {
  int oldListStart;
  int oldListEnd;
  int newListStart;
  int newListEnd;

  _Range(
      {required this.oldListStart,
      required this.oldListEnd,
      required this.newListStart,
      required this.newListEnd});

  _Range.empty()
      : oldListStart = 0,
        oldListEnd = 0,
        newListStart = 0,
        newListEnd = 0;

  @pragma("vm:prefer-inline")
  int oldSize() {
    return oldListEnd - oldListStart;
  }

  @pragma("vm:prefer-inline")
  int newSize() {
    return newListEnd - newListStart;
  }
}

/// Two centered k-line arrays backed by a single Int32List allocation.
/// [fwd]/[bwd] share the same backing buffer but address disjoint halves,
/// saving one typed-array allocation per diff call.
final class _KLineArrays {
  final Int32List _data;
  final int _fwdMid;
  final int _bwdMid;
  final int _half;

  _KLineArrays(int kLineSize)
      : _half = kLineSize,
        _fwdMid = kLineSize ~/ 2,
        _bwdMid = kLineSize + kLineSize ~/ 2,
        _data = Int32List(kLineSize * 2);

  @pragma("vm:prefer-inline")
  int fwd(int index) => _data[_fwdMid + index];

  @pragma("vm:prefer-inline")
  void setFwd(int index, int value) {
    _data[_fwdMid + index] = value;
  }

  @pragma("vm:prefer-inline")
  int bwd(int index) => _data[_bwdMid + index];

  @pragma("vm:prefer-inline")
  void setBwd(int index, int value) {
    _data[_bwdMid + index] = value;
  }

  /// Return the forward half for reuse as old-item statuses in DiffResult.
  Int32List get forwardData => Int32List.sublistView(_data, 0, _half);

  /// Return the backward half for reuse as new-item statuses in DiffResult.
  Int32List get backwardData => Int32List.sublistView(_data, _half);
}

///
///This class holds the information about the result of a
/// calculateDiff call.
///<p>
///You can consume the updates in a DiffResult via
/// dispatchUpdatesTo().
///
class DiffResult<T> {
  ///
  ///While reading the flags below, keep in mind that when multiple items move in a list,
  ///Myers's may pick any of them as the anchor item and consider that one NOT_CHANGED while
  ///picking others as additions and removals. This is completely fine as we later detect
  ///all moves.
  ///<p>
  ///Below, when an item is mentioned to stay in the same 'location', it means we won't
  ///dispatch a move/add/remove for it, it DOES NOT mean the item is still in the same
  ///position.
  ///
  // item stayed the same.
  static const int FLAG_NOT_CHANGED = 1;

  // item stayed in the same location but changed.
  static const int FLAG_CHANGED = FLAG_NOT_CHANGED << 1;

  // Item has moved and also changed.
  static const int FLAG_MOVED_CHANGED = FLAG_CHANGED << 1;

  // Item has moved but did not change.
  static const int FLAG_MOVED_NOT_CHANGED = FLAG_MOVED_CHANGED << 1;

  // Item move
  static const int FLAG_MOVED = FLAG_MOVED_CHANGED | FLAG_MOVED_NOT_CHANGED;

  // since we are re-using the int arrays that were created in the Myers' step, we mask
  // change flags
  static const int FLAG_OFFSET = 4;
  static const int FLAG_MASK = (1 << FLAG_OFFSET) - 1;

  // The Myers' snakes. At this point, we only care about their diagonal sections.
  final List<_Diagonal> _mDiagonals;

  // The list to keep oldItemStatuses. As we traverse old items, we assign flags to them
  // which also includes whether they were a real removal or a move (and its new index).
  final List<int> _mOldItemStatuses;

  // The list to keep newItemStatuses. As we traverse new items, we assign flags to them
  // which also includes whether they were a real addition or a move(and its old index).
  final List<int> _mNewItemStatuses;

  // The callback that was given to calcualte diff method.
  final DiffDelegate _mCallback;
  final int _mOldListSize;
  final int _mNewListSize;
  final bool _mDetectMoves;

  ///
  ///@param callback The callback that was used to calculate the diff
  ///@param snakes The list of Myers' snakes
  ///@param oldItemStatuses An int[] that can be re-purposed to keep metadata
  ///@param newItemStatuses An int[] that can be re-purposed to keep metadata
  ///@param detectMoves True if this DiffResult will try to detect moved items
  ///
  DiffResult._(DiffDelegate callback, List<_Diagonal> diagonals,
      List<int> oldItemStatuses, List<int> newItemStatuses, bool detectMoves)
      : _mDiagonals = diagonals,
        _mOldItemStatuses = oldItemStatuses,
        _mNewItemStatuses = newItemStatuses,
        _mCallback = callback,
        _mOldListSize = callback.getOldListSize(),
        _mNewListSize = callback.getNewListSize(),
        _mDetectMoves = detectMoves {
    _mOldItemStatuses.fillRange(0, _mOldItemStatuses.length, 0);
    _mNewItemStatuses.fillRange(0, _mNewItemStatuses.length, 0);
    _addEdgeDiagonals();
    _findMatchingItems();
  }

  /// Add edge diagonals so that we can iterate as long as there are diagonals w/o lots of
  /// null checks around
  void _addEdgeDiagonals() {
    final first = _mDiagonals.isEmpty ? null : _mDiagonals[0];
    // see if we should add 1 to the 0,0
    if (first == null || first.x != 0 || first.y != 0) {
      _mDiagonals.insert(0, _Diagonal(0, 0, 0));
    }
    // always add one last
    _mDiagonals.add(_Diagonal(_mOldListSize, _mNewListSize, 0));
  }

  /// Find position mapping from old list to new list.
  /// If moves are requested, we'll also try to do an n^2 search between additions and
  /// removals to find moves.
  void _findMatchingItems() {
    for (_Diagonal diagonal in _mDiagonals) {
      for (int offset = 0; offset < diagonal.size; offset++) {
        final int posX = diagonal.x + offset;
        final int posY = diagonal.y + offset;
        final bool theSame = _mCallback.areContentsTheSame(posX, posY);
        final int changeFlag = theSame ? FLAG_NOT_CHANGED : FLAG_CHANGED;
        _mOldItemStatuses[posX] = (posY << FLAG_OFFSET) | changeFlag;
        _mNewItemStatuses[posY] = (posX << FLAG_OFFSET) | changeFlag;
      }
    }
    // now all matches are marked, lets look for moves
    if (_mDetectMoves) {
      // traverse each addition / removal from the end of the list, find matching
      // addition removal from before
      _findMoveMatches();
    }
  }

  void _findMoveMatches() {
    // for each removal, find matching addition
    int posX = 0;
    for (_Diagonal diagonal in _mDiagonals) {
      while (posX < diagonal.x) {
        if (_mOldItemStatuses[posX] == 0) {
          // there is a removal, find matching addition from the rest
          _findMatchingAddition(posX);
        }
        posX++;
      }
      // snap back for the next diagonal
      posX = diagonal.endX();
    }
  }

  /// Search the whole list to find the addition for the given removal of position posX
  ///
  /// @param posX position in the old list
  void _findMatchingAddition(int posX) {
    int posY = 0;
    final int diagonalsSize = _mDiagonals.length;
    for (int i = 0; i < diagonalsSize; i++) {
      final _Diagonal diagonal = _mDiagonals[i];
      while (posY < diagonal.y) {
        // found some additions, evaluate
        if (_mNewItemStatuses[posY] == 0) {
          // not evaluated yet
          final matching = _mCallback.areItemsTheSame(posX, posY);
          if (matching) {
            // yay found it, set values
            final contentsMatching = _mCallback.areContentsTheSame(posX, posY);
            final int changeFlag =
                contentsMatching ? FLAG_MOVED_NOT_CHANGED : FLAG_MOVED_CHANGED;
            // once we process one of these, it will mark the other one as ignored.
            _mOldItemStatuses[posX] = (posY << FLAG_OFFSET) | changeFlag;
            _mNewItemStatuses[posY] = (posX << FLAG_OFFSET) | changeFlag;
            return;
          }
        }
        posY++;
      }
      posY = diagonal.endY();
    }
  }

  Iterable<DiffUpdate> getUpdates({bool batch = true}) {
    final updates = <DiffUpdate>[];
    // track up to date current list size for moves
    // when a move is found, we record its position from the end of the list (which is
    // less likely to change since we iterate in reverse).
    // Later when we find the match of that move, we dispatch the update
    int currentListSize = _mOldListSize;
    // list of postponed moves
    final postponedUpdates = <_PostponedUpdate>[];
    // posX and posY are exclusive
    int posX = _mOldListSize;
    int posY = _mNewListSize;
    // iterate from end of the list to the beginning.
    // this just makes offsets easier since changes in the earlier indices has an effect
    // on the later indices.
    for (int diagonalIndex = _mDiagonals.length - 1;
        diagonalIndex >= 0;
        diagonalIndex--) {
      final _Diagonal diagonal = _mDiagonals[(diagonalIndex)];
      final int endX = diagonal.endX();
      final int endY = diagonal.endY();
      // dispatch removals and additions until we reach to that diagonal
      // first remove then add so that it can go into its place and we don't need
      // to offset values
      while (posX > endX) {
        posX--;
        // REMOVAL
        final int status = _mOldItemStatuses[posX];
        if ((status & FLAG_MOVED) != 0) {
          final int newPos = status >> FLAG_OFFSET;
          // get postponed addition
          final _PostponedUpdate? postponedUpdate =
              getPostponedUpdate(postponedUpdates, newPos, false);
          if (postponedUpdate != null) {
            // this is an addition that was postponed. Now dispatch it.
            final int updatedNewPos =
                currentListSize - postponedUpdate.currentPos;
            updates.add(Move(from: posX, to: updatedNewPos - 1));
            if ((status & FLAG_MOVED_CHANGED) != 0) {
              final Object? changePayload =
                  _mCallback.getChangePayload(posX, newPos);
              updates.add(
                  Change(position: updatedNewPos - 1, payload: changePayload));
            }
          } else {
            // first time we are seeing this, we'll see a matching addition
            postponedUpdates.add(_PostponedUpdate(
                posInOwnerList: posX,
                currentPos: currentListSize - posX - 1,
                removal: true));
          }
        } else {
          // simple removal
          updates.add(Remove(position: posX, count: 1));
          currentListSize--;
        }
      }
      while (posY > endY) {
        posY--;
        // ADDITION
        final int status = _mNewItemStatuses[posY];
        if ((status & FLAG_MOVED) != 0) {
          // this is a move not an addition.
          // see if this is postponed
          final int oldPos = status >> FLAG_OFFSET;
          // get postponed removal
          final _PostponedUpdate? postponedUpdate =
              getPostponedUpdate(postponedUpdates, oldPos, true);
          // empty size returns 0 for indexOf
          if (postponedUpdate == null) {
            // postpone it until we see the removal
            postponedUpdates.add(_PostponedUpdate(
                posInOwnerList: posY,
                currentPos: currentListSize - posX,
                removal: false));
          } else {
            // oldPosFromEnd = foundListSize - posX
            // we can find posX if we swap the list sizes
            // posX = listSize - oldPosFromEnd
            final int updatedOldPos =
                currentListSize - postponedUpdate.currentPos - 1;
            updates.add(Move(from: updatedOldPos, to: posX));
            if ((status & FLAG_MOVED_CHANGED) != 0) {
              final Object? changePayload =
                  _mCallback.getChangePayload(oldPos, posY);
              updates.add(Change(position: posX, payload: changePayload));
            }
          }
        } else {
          // simple addition
          updates.add(Insert(position: posX, count: 1));
          currentListSize++;
        }
      }
      // now dispatch updates for the diagonal
      posX = diagonal.x;
      posY = diagonal.y;
      for (int i = 0; i < diagonal.size; i++) {
        // dispatch changes
        if ((_mOldItemStatuses[posX] & FLAG_MASK) == FLAG_CHANGED) {
          final Object? changePayload = _mCallback.getChangePayload(posX, posY);
          updates.add(Change(position: posX, payload: changePayload));
        }
        posX++;
        posY++;
      }
      // snap back for the next diagonal
      posX = diagonal.x;
      posY = diagonal.y;
    }
    return batch ? updates.batch() : updates;
  }

  Iterable<DataDiffUpdate<T>> getUpdatesWithData() {
    final delegate = _mCallback;
    if (delegate is! IndexableItemDiffDelegate<T>) {
      throw Exception(
          "$delegate is not a IndexableItemDiffDelegate<$T>. call getUpdates() instead or implement IndexableItemDiffDelegate in your DiffDelegate ");
    }
    final updates = <DataDiffUpdate<T>>[];
    // track up to date current list size for moves
    // when a move is found, we record its position from the end of the list (which is
    // less likely to change since we iterate in reverse).
    // Later when we find the match of that move, we dispatch the update
    int currentListSize = _mOldListSize;
    // list of postponed moves
    final postponedUpdates = <_PostponedUpdate>[];
    // posX and posY are exclusive
    int posX = _mOldListSize;
    int posY = _mNewListSize;
    // iterate from end of the list to the beginning.
    // this just makes offsets easier since changes in the earlier indices has an effect
    // on the later indices.
    for (int diagonalIndex = _mDiagonals.length - 1;
        diagonalIndex >= 0;
        diagonalIndex--) {
      final _Diagonal diagonal = _mDiagonals[(diagonalIndex)];

      final int endX = diagonal.endX();
      final int endY = diagonal.endY();
      // dispatch removals and additions until we reach to that diagonal
      // first remove then add so that it can go into its place and we don't need
      // to offset values
      while (posX > endX) {
        posX--;
        // REMOVAL
        final int status = _mOldItemStatuses[posX];
        final item = delegate.getOldItemAtIndex(posX);
        if ((status & FLAG_MOVED) != 0) {
          final int newPos = status >> FLAG_OFFSET;
          // get postponed addition
          final _PostponedUpdate? postponedUpdate =
              getPostponedUpdate(postponedUpdates, newPos, false);
          if (postponedUpdate != null) {
            // this is an addition that was postponed. Now dispatch it.
            final int updatedNewPos =
                currentListSize - postponedUpdate.currentPos;
            updates
                .add(DataMove(from: posX, to: updatedNewPos - 1, data: item));
            if ((status & FLAG_MOVED_CHANGED) != 0) {
              updates.add(DataChange(
                position: updatedNewPos - 1,
                newData: delegate.getNewItemAtIndex(newPos),
                oldData: item,
              ));
            }
          } else {
            // first time we are seeing this, we'll see a matching addition
            postponedUpdates.add(_PostponedUpdate(
                posInOwnerList: posX,
                currentPos: currentListSize - posX - 1,
                removal: true));
          }
        } else {
          // simple removal
          updates.add(DataRemove(position: posX, data: item));
          currentListSize--;
        }
      }
      while (posY > endY) {
        posY--;
        // ADDITION
        final int status = _mNewItemStatuses[posY];
        final item = delegate.getNewItemAtIndex(posY);

        if ((status & FLAG_MOVED) != 0) {
          // this is a move not an addition.
          // see if this is postponed
          final int oldPos = status >> FLAG_OFFSET;
          // get postponed removal
          final _PostponedUpdate? postponedUpdate =
              getPostponedUpdate(postponedUpdates, oldPos, true);
          // empty size returns 0 for indexOf
          if (postponedUpdate == null) {
            // postpone it until we see the removal
            postponedUpdates.add(_PostponedUpdate(
                posInOwnerList: posY,
                currentPos: currentListSize - posX,
                removal: false));
          } else {
            // oldPosFromEnd = foundListSize - posX
            // we can find posX if we swap the list sizes
            // posX = listSize - oldPosFromEnd
            final int updatedOldPos =
                currentListSize - postponedUpdate.currentPos - 1;
            updates.add(DataMove(from: updatedOldPos, to: posX, data: item));
            if ((status & FLAG_MOVED_CHANGED) != 0) {
              updates.add(DataDiffUpdate.change(
                  position: posX,
                  oldData: delegate.getOldItemAtIndex(oldPos),
                  newData: item));
            }
          }
        } else {
          // simple addition
          updates.add(DataInsert(position: posX, data: item));
          currentListSize++;
        }
      }
      // now dispatch updates for the diagonal
      posX = diagonal.x;
      posY = diagonal.y;
      for (int i = 0; i < diagonal.size; i++) {
        // dispatch changes
        if ((_mOldItemStatuses[posX] & FLAG_MASK) == FLAG_CHANGED) {
          updates.add(DataDiffUpdate.change(
              position: posX,
              oldData: delegate.getOldItemAtIndex(posX),
              newData: delegate.getNewItemAtIndex(posY)));
          //updates.add(Change(position: posX, payload: changePayload));
        }
        posX++;
        posY++;
      }
      // snap back for the next diagonal
      posX = diagonal.x;
      posY = diagonal.y;
    }
    return updates;
  }

  _PostponedUpdate? getPostponedUpdate(
      List<_PostponedUpdate> postponedUpdates, int posInList, bool removal) {
    _PostponedUpdate? postponedUpdate;

    int i = 0;

    while (i < postponedUpdates.length) {
      final update = postponedUpdates.elementAt(i);
      if (update.posInOwnerList == posInList && update.removal == removal) {
        postponedUpdate = update;
        postponedUpdates.removeAt(i);
        break;
      }
      i++;
    }
    while (i < postponedUpdates.length) {
      // re-offset all others
      final update = postponedUpdates.elementAt(i);
      if (removal) {
        update.currentPos--;
      } else {
        update.currentPos++;
      }
      i++;
    }
    return postponedUpdate;
  }
}

class _PostponedUpdate {
  final int posInOwnerList;
  int currentPos;
  final bool removal;

  _PostponedUpdate(
      {required this.posInOwnerList,
      required this.currentPos,
      required this.removal});
}

///
/// Calculates the list of update operations that can convert one list into the other one.
/// <p>
/// If your old and new lists are sorted by the same constraint and items never move (swap
/// positions), you can disable move detection which takes <code>O(N^2)</code> time where
/// N is the number of added, moved, removed items.
///
/// @param cb The callback that acts as a gateway to the backing list data
/// @param detectMoves True if DiffUtil should try to detect moved items, false otherwise.
///
/// @return A DiffResult that contains the information about the edit sequence to convert the
/// old list into the new list.
///
DiffResult<T> calculateDiff<T>(DiffDelegate cb, {bool detectMoves = false}) {
  return _calculateDiffCoreDelegate<T>(cb, detectMoves);
}

/// calculate the difference between the two given lists.
///
/// @param oldList the old list
/// @param newList the new list
/// @param detectMoves whether move detection should be enabled
/// @param equalityChecker use this if you don't want to use the equality as defined by the == operator
DiffResult<T> calculateListDiff<T>(
  List<T> oldList,
  List<T> newList, {
  bool detectMoves = true,
  bool Function(T, T)? equalityChecker,
}) {
  final delegate = ListDiffDelegate<T>(oldList, newList, equalityChecker);

  // With a custom equality checker we cannot safely intern via HashMap
  // (whose keys use operator== / hashCode, which may differ from the checker).
  if (equalityChecker != null) {
    return calculateDiff<T>(delegate, detectMoves: detectMoves);
  }

  final oldSize = oldList.length;
  final newSize = newList.length;

  final minSize = oldSize < newSize ? oldSize : newSize;
  int prefix = 0;
  while (prefix < minSize && delegate.areItemsTheSame(prefix, prefix)) {
    prefix++;
  }
  int suffix = 0;
  final maxSuffix = minSize - prefix;
  while (suffix < maxSuffix &&
      delegate.areItemsTheSame(oldSize - 1 - suffix, newSize - 1 - suffix)) {
    suffix++;
  }

  final trimmedOldStart = prefix;
  final trimmedOldEnd = oldSize - suffix;
  final trimmedNewStart = prefix;
  final trimmedNewEnd = newSize - suffix;

  if (_shouldIntern(
    oldList,
    newList,
    trimmedOldStart,
    trimmedOldEnd,
    trimmedNewStart,
    trimmedNewEnd,
  )) {
    final interner = HashMap<T, int>();
    int nextId = 1;
    final oldIds = Int32List(oldSize);
    final newIds = Int32List(newSize);
    for (int i = trimmedOldStart; i < trimmedOldEnd; i++) {
      oldIds[i] = interner.putIfAbsent(oldList[i], () => nextId++);
    }
    for (int i = trimmedNewStart; i < trimmedNewEnd; i++) {
      newIds[i] = interner.putIfAbsent(newList[i], () => nextId++);
    }

    return _calculateDiffCorePreTrimmed<T>(
      delegate,
      (int x, int y) => oldIds[x] == newIds[y],
      detectMoves,
      prefix,
      suffix,
    );
  }

  return _calculateDiffCorePreTrimmedDelegate<T>(
    delegate,
    detectMoves,
    prefix,
    suffix,
  );
}

bool _shouldIntern<T>(
  List<T> oldList,
  List<T> newList,
  int oldStart,
  int oldEnd,
  int newStart,
  int newEnd,
) {
  final oldLength = oldEnd - oldStart;
  final newLength = newEnd - newStart;
  if (oldLength <= 0 || newLength <= 0) {
    return false;
  }

  final totalLength = oldLength + newLength;
  if (totalLength < 512) {
    return false;
  }

  // If the remaining middle is still mostly equal at the same offsets, Myers
  // will usually find long snakes cheaply. Interning would add a full HashMap
  // pass to a workload that is already close to linear.
  final sampleLength = oldLength < newLength ? oldLength : newLength;
  final step = max(1, sampleLength ~/ 64);
  var sampled = 0;
  var alignedMatches = 0;
  for (var offset = 0; offset < sampleLength && sampled < 64; offset += step) {
    sampled++;
    if (oldList[oldStart + offset] == newList[newStart + offset]) {
      alignedMatches++;
    }
  }

  return sampled == 0 || alignedMatches * 4 < sampled * 3;
}

/// you can use this function if you want to use custom list-types, such as BuiltList
/// or KtList and want to avoid copying
DiffResult<T> calculateCustomListDiff<T, L>(L oldList, L newList,
    {bool detectMoves = true,
    bool Function(T, T)? equalityChecker,
    required T Function(L, int) getByIndex,
    required int Function(L) getLength}) {
  return calculateDiff(
      CustomListDiffDelegate<T, L>(
        oldList: oldList,
        newList: newList,
        equalityChecker: equalityChecker,
        getLength: getLength,
        getByIndex: getByIndex,
      ),
      detectMoves: detectMoves);
}

DiffResult<T> _calculateDiffCoreDelegate<T>(
  DiffDelegate cb,
  bool detectMoves,
) {
  final oldSize = cb.getOldListSize();
  final newSize = cb.getNewListSize();

  final minSize = oldSize < newSize ? oldSize : newSize;
  int prefix = 0;
  while (prefix < minSize && cb.areItemsTheSame(prefix, prefix)) {
    prefix++;
  }
  int suffix = 0;
  final maxSuffix = minSize - prefix;
  while (suffix < maxSuffix &&
      cb.areItemsTheSame(oldSize - 1 - suffix, newSize - 1 - suffix)) {
    suffix++;
  }

  return _calculateDiffCorePreTrimmedDelegate<T>(
      cb, detectMoves, prefix, suffix);
}

DiffResult<T> _calculateDiffCorePreTrimmedDelegate<T>(
  DiffDelegate cb,
  bool detectMoves,
  int prefix,
  int suffix,
) {
  final oldSize = cb.getOldListSize();
  final newSize = cb.getNewListSize();

  final diagonals = <_Diagonal>[];
  if (prefix > 0) diagonals.add(_Diagonal(0, 0, prefix));
  if (suffix > 0) {
    diagonals.add(_Diagonal(oldSize - suffix, newSize - suffix, suffix));
  }

  final trimmedOldStart = prefix;
  final trimmedOldEnd = oldSize - suffix;
  final trimmedNewStart = prefix;
  final trimmedNewEnd = newSize - suffix;

  if (trimmedOldEnd <= trimmedOldStart || trimmedNewEnd <= trimmedNewStart) {
    return DiffResult._(
        cb, diagonals, Int32List(oldSize), Int32List(newSize), detectMoves);
  }

  final max = (oldSize + newSize + 1) ~/ 2;
  final kLines = _KLineArrays(max * 2 + 1);
  final stack = <_Range>[];
  stack.add(_Range(
      oldListStart: trimmedOldStart,
      oldListEnd: trimmedOldEnd,
      newListStart: trimmedNewStart,
      newListEnd: trimmedNewEnd));
  final rangePool = <_Range>[];

  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final snake = _midPointDelegate(range, cb, kLines);

    if (snake != null) {
      if (snake.diagonalSize() > 0) {
        diagonals.add(snake.toDiagonal());
      }

      final _Range left = rangePool.isEmpty
          ? _Range.empty()
          : rangePool.removeAt(rangePool.length - 1);
      left.oldListStart = range.oldListStart;
      left.newListStart = range.newListStart;
      left.oldListEnd = snake.startX;
      left.newListEnd = snake.startY;
      stack.add(left);

      final _Range right = range;
      right.oldListEnd = range.oldListEnd;
      right.newListEnd = range.newListEnd;
      right.oldListStart = snake.endX;
      right.newListStart = snake.endY;
      stack.add(right);
    } else {
      rangePool.add(range);
    }
  }

  diagonals.sort(_diagonalComparator);
  return DiffResult._(
      cb, diagonals, kLines.forwardData, kLines.backwardData, detectMoves);
}

/// Inner algorithm after prefix/suffix lengths are already known.
/// Used by the interned path where the hot comparison is an integer ID check.
DiffResult<T> _calculateDiffCorePreTrimmed<T>(
  DiffDelegate cb,
  bool Function(int, int) areEqual,
  bool detectMoves,
  int prefix,
  int suffix,
) {
  final oldSize = cb.getOldListSize();
  final newSize = cb.getNewListSize();

  final diagonals = <_Diagonal>[];
  if (prefix > 0) diagonals.add(_Diagonal(0, 0, prefix));
  if (suffix > 0) {
    diagonals.add(_Diagonal(oldSize - suffix, newSize - suffix, suffix));
  }

  final trimmedOldStart = prefix;
  final trimmedOldEnd = oldSize - suffix;
  final trimmedNewStart = prefix;
  final trimmedNewEnd = newSize - suffix;

  // Early return for trivial cases — avoid allocating large k-line arrays.
  if (trimmedOldEnd <= trimmedOldStart || trimmedNewEnd <= trimmedNewStart) {
    return DiffResult._(
        cb, diagonals, Int32List(oldSize), Int32List(newSize), detectMoves);
  }

  final max = (oldSize + newSize + 1) ~/ 2;
  final kLines = _KLineArrays(max * 2 + 1);

  {
    final stack = <_Range>[];
    stack.add(_Range(
        oldListStart: trimmedOldStart,
        oldListEnd: trimmedOldEnd,
        newListStart: trimmedNewStart,
        newListEnd: trimmedNewEnd));
    final rangePool = <_Range>[];

    while (stack.isNotEmpty) {
      final range = stack.removeLast();

      // --- Recursive sub-range prefix/suffix trimming ---
      // After splitting at the middle snake, each sub-range may also share
      // common elements at its boundaries.  Finding them here avoids pushing
      // those elements into the O(ND) search.
      _trimSubRange(range, areEqual, diagonals);

      if (range.oldSize() < 1 || range.newSize() < 1) {
        rangePool.add(range);
        continue;
      }

      final snake = _midPoint(range, areEqual, kLines);

      if (snake != null) {
        if (snake.diagonalSize() > 0) {
          diagonals.add(snake.toDiagonal());
        }

        final _Range left = rangePool.isEmpty
            ? _Range.empty()
            : rangePool.removeAt(rangePool.length - 1);
        left.oldListStart = range.oldListStart;
        left.newListStart = range.newListStart;
        left.oldListEnd = snake.startX;
        left.newListEnd = snake.startY;
        stack.add(left);

        final _Range right = range;
        right.oldListEnd = range.oldListEnd;
        right.newListEnd = range.newListEnd;
        right.oldListStart = snake.endX;
        right.newListStart = snake.endY;
        stack.add(right);
      } else {
        rangePool.add(range);
      }
    }
  }

  diagonals.sort(_diagonalComparator);
  return DiffResult._(
      cb, diagonals, kLines.forwardData, kLines.backwardData, detectMoves);
}

/// Trim matching elements at the start and end of [range], adding any
/// matches found as diagonals.  Mutates [range] in place.
@pragma("vm:prefer-inline")
void _trimSubRange(
    _Range range, bool Function(int, int) areEqual, List<_Diagonal> diagonals) {
  // prefix
  int subPrefix = 0;
  final subMinSize = min(range.oldSize(), range.newSize());
  while (subPrefix < subMinSize &&
      areEqual(
          range.oldListStart + subPrefix, range.newListStart + subPrefix)) {
    subPrefix++;
  }
  if (subPrefix > 0) {
    diagonals.add(_Diagonal(range.oldListStart, range.newListStart, subPrefix));
    range.oldListStart += subPrefix;
    range.newListStart += subPrefix;
  }
  // suffix
  int subSuffix = 0;
  final subMaxSuffix = min(range.oldSize(), range.newSize());
  while (subSuffix < subMaxSuffix &&
      areEqual(
          range.oldListEnd - 1 - subSuffix, range.newListEnd - 1 - subSuffix)) {
    subSuffix++;
  }
  if (subSuffix > 0) {
    diagonals.add(_Diagonal(
        range.oldListEnd - subSuffix, range.newListEnd - subSuffix, subSuffix));
    range.oldListEnd -= subSuffix;
    range.newListEnd -= subSuffix;
  }
}

extension _Batch on Iterable<DiffUpdate> {
  Iterable<DiffUpdate> batch() sync* {
    DiffUpdate? lastUpdate;
    for (final update in this) {
      if (lastUpdate.runtimeType != update.runtimeType) {
        if (lastUpdate != null) {
          yield lastUpdate;
        }
        lastUpdate = update;
      } else {
        if (lastUpdate is Move || lastUpdate is Change) {
          yield lastUpdate!;
          lastUpdate = update;
        } else if (update is Insert) {
          final lastInsert = lastUpdate as Insert;
          if ((update.position - lastInsert.position).abs() <= 1) {
            lastUpdate = DiffUpdate.insert(
                position: min(update.position, lastInsert.position),
                count: update.count + lastInsert.count);
          } else {
            yield lastUpdate;
            lastUpdate = update;
          }
        } else {
          final remove = update as Remove;
          final lastRemove = lastUpdate as Remove;
          if ((remove.position - lastRemove.position).abs() <= 1) {
            lastUpdate = DiffUpdate.remove(
                position: min(remove.position, lastRemove.position),
                count: remove.count + lastRemove.count);
          } else {
            yield lastUpdate;
            lastUpdate = update;
          }
        }
      }
    }
    if (lastUpdate != null) yield lastUpdate;
  }
}

@pragma("vm:prefer-inline")
_Snake? _midPointDelegate(_Range range, DiffDelegate cb, _KLineArrays kLines) {
  if (range.oldSize() < 1 || range.newSize() < 1) {
    return null;
  }
  final max = (range.oldSize() + range.newSize() + 1) ~/ 2;
  kLines.setFwd(1, range.oldListStart);
  kLines.setBwd(1, range.oldListEnd);
  for (int d = 0; d < max; d++) {
    _Snake? snake = _forwardSnakeDelegate(range, cb, kLines, d);
    if (snake != null) {
      return snake;
    }
    snake = _backwardSnakeDelegate(range, cb, kLines, d);
    if (snake != null) {
      return snake;
    }
  }
  return null;
}

@pragma("vm:prefer-inline")
_Snake? _forwardSnakeDelegate(
    _Range range, DiffDelegate cb, _KLineArrays kLines, int d) {
  final bool checkForSnake = ((range.oldSize() ^ range.newSize()) & 1) == 1;
  final delta = range.oldSize() - range.newSize();
  final oldEnd = range.oldListEnd;
  final newEnd = range.newListEnd;
  final oldStart = range.oldListStart;
  final newStart = range.newListStart;
  for (int k = -d; k <= d; k += 2) {
    final int startX;
    final int startY;
    int x, y;
    if (k == -d || (k != d && kLines.fwd(k + 1) > kLines.fwd(k - 1))) {
      x = startX = kLines.fwd(k + 1);
    } else {
      startX = kLines.fwd(k - 1);
      x = startX + 1;
    }
    y = newStart + (x - oldStart) - k;
    startY = (d == 0 || x != startX) ? y : y - 1;
    while (x < oldEnd && y < newEnd && cb.areItemsTheSame(x, y)) {
      x++;
      y++;
    }
    kLines.setFwd(k, x);
    if (checkForSnake) {
      final backwardsK = delta - k;
      if (backwardsK >= -d + 1 &&
          backwardsK <= d - 1 &&
          kLines.bwd(backwardsK) <= x) {
        return _Snake(
            startX: startX, startY: startY, endX: x, endY: y, reverse: false);
      }
    }
  }
  return null;
}

@pragma("vm:prefer-inline")
_Snake? _backwardSnakeDelegate(
    _Range range, DiffDelegate cb, _KLineArrays kLines, int d) {
  final checkForSnake = ((range.oldSize() ^ range.newSize()) & 1) == 0;
  final delta = range.oldSize() - range.newSize();
  final oldStart = range.oldListStart;
  final newStart = range.newListStart;
  final oldEnd = range.oldListEnd;
  final newEnd = range.newListEnd;
  for (int k = -d; k <= d; k += 2) {
    final int startX;
    final int startY;
    int x, y;
    if (k == -d || (k != d && kLines.bwd(k + 1) < kLines.bwd(k - 1))) {
      x = startX = kLines.bwd(k + 1);
    } else {
      startX = kLines.bwd(k - 1);
      x = startX - 1;
    }
    y = newEnd - ((oldEnd - x) - k);
    startY = (d == 0 || x != startX) ? y : y + 1;
    while (x > oldStart && y > newStart && cb.areItemsTheSame(x - 1, y - 1)) {
      x--;
      y--;
    }
    kLines.setBwd(k, x);
    if (checkForSnake) {
      final forwardsK = delta - k;
      if (forwardsK >= -d && forwardsK <= d && kLines.fwd(forwardsK) >= x) {
        return _Snake(
            startX: x, startY: y, endX: startX, endY: startY, reverse: true);
      }
    }
  }
  return null;
}

@pragma("vm:prefer-inline")
_Snake? _midPoint(
    _Range range, bool Function(int, int) areEqual, _KLineArrays kLines) {
  if (range.oldSize() < 1 || range.newSize() < 1) {
    return null;
  }
  final max = (range.oldSize() + range.newSize() + 1) ~/ 2;
  kLines.setFwd(1, range.oldListStart);
  kLines.setBwd(1, range.oldListEnd);
  for (int d = 0; d < max; d++) {
    _Snake? snake = _forwardSnake(range, areEqual, kLines, d);
    if (snake != null) {
      return snake;
    }
    snake = _backwardSnake(range, areEqual, kLines, d);
    if (snake != null) {
      return snake;
    }
  }
  return null;
}

@pragma("vm:prefer-inline")
_Snake? _forwardSnake(_Range range, bool Function(int, int) areEqual,
    _KLineArrays kLines, int d) {
  final bool checkForSnake = ((range.oldSize() ^ range.newSize()) & 1) == 1;
  final delta = range.oldSize() - range.newSize();
  final oldEnd = range.oldListEnd;
  final newEnd = range.newListEnd;
  final oldStart = range.oldListStart;
  final newStart = range.newListStart;
  for (int k = -d; k <= d; k += 2) {
    final int startX;
    final int startY;
    int x, y;
    if (k == -d || (k != d && kLines.fwd(k + 1) > kLines.fwd(k - 1))) {
      x = startX = kLines.fwd(k + 1);
    } else {
      startX = kLines.fwd(k - 1);
      x = startX + 1;
    }
    y = newStart + (x - oldStart) - k;
    startY = (d == 0 || x != startX) ? y : y - 1;
    while (x < oldEnd && y < newEnd && areEqual(x, y)) {
      x++;
      y++;
    }
    kLines.setFwd(k, x);
    if (checkForSnake) {
      final backwardsK = delta - k;
      if (backwardsK >= -d + 1 &&
          backwardsK <= d - 1 &&
          kLines.bwd(backwardsK) <= x) {
        return _Snake(
            startX: startX, startY: startY, endX: x, endY: y, reverse: false);
      }
    }
  }
  return null;
}

@pragma("vm:prefer-inline")
_Snake? _backwardSnake(_Range range, bool Function(int, int) areEqual,
    _KLineArrays kLines, int d) {
  final checkForSnake = ((range.oldSize() ^ range.newSize()) & 1) == 0;
  final delta = range.oldSize() - range.newSize();
  final oldStart = range.oldListStart;
  final newStart = range.newListStart;
  final oldEnd = range.oldListEnd;
  final newEnd = range.newListEnd;
  for (int k = -d; k <= d; k += 2) {
    final int startX;
    final int startY;
    int x, y;
    if (k == -d || (k != d && kLines.bwd(k + 1) < kLines.bwd(k - 1))) {
      x = startX = kLines.bwd(k + 1);
    } else {
      startX = kLines.bwd(k - 1);
      x = startX - 1;
    }
    y = newEnd - ((oldEnd - x) - k);
    startY = (d == 0 || x != startX) ? y : y + 1;
    while (x > oldStart && y > newStart && areEqual(x - 1, y - 1)) {
      x--;
      y--;
    }
    kLines.setBwd(k, x);
    if (checkForSnake) {
      final forwardsK = delta - k;
      if (forwardsK >= -d && forwardsK <= d && kLines.fwd(forwardsK) >= x) {
        return _Snake(
            startX: x, startY: y, endX: startX, endY: startY, reverse: true);
      }
    }
  }
  return null;
}
