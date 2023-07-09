// ignore_for_file: constant_identifier_names

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

  bool hasAdditionOrRemoval() {
    return endY - startY != endX - startX;
  }

  bool isAddition() {
    return endY - startY > endX - startX;
  }

  int diagonalSize() {
    return min(endX - startX, endY - startY);
  }

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

  int oldSize() {
    return oldListEnd - oldListStart;
  }

  int newSize() {
    return newListEnd - newListStart;
  }
}

final class _CenteredArray {
  final Int32List data;
  final int _mid;

  _CenteredArray(int size)
      : _mid = size ~/ 2,
        data = Int32List(size);

  @pragma("vm:prefer-inline")
  int operator [](int index) {
    return data[_mid + index];
  }

  @pragma("vm:prefer-inline")
  void operator []=(int index, int value) {
    data[_mid + index] = value;
  }

  void fill(int value) {
    data.fillRange(0, data.length, value);
  }
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
    if (_mOldItemStatuses.isNotEmpty) {
      _mOldItemStatuses.fillRange(0, _mOldItemStatuses.length - 1, 0);
    }
    if (_mNewItemStatuses.isNotEmpty) {
      _mNewItemStatuses.fillRange(0, _mNewItemStatuses.length - 1, 0);
    }
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
/// Calculates the list of update operations that can covert one list into the other one.
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
  final oldSize = cb.getOldListSize();
  final newSize = cb.getNewListSize();
  final diagonals = <_Diagonal>[];
  // instead of a recursive implementation, we keep our own stack to avoid potential stack
  // overflow exceptions
  final stack = <_Range>[];
  stack.add(_Range(
      oldListStart: 0,
      oldListEnd: oldSize,
      newListStart: 0,
      newListEnd: newSize));
  final max = (oldSize + newSize + 1) ~/ 2;
  // allocate forward and backward k-lines. K lines are diagonal lines in the matrix. (see the
  // paper for details)
  // These arrays lines keep the max reachable position for each k-line.
  final forward = _CenteredArray(max * 2 + 1);
  final backward = _CenteredArray(max * 2 + 1);
  // We pool the ranges to avoid allocations for each recursive call.
  final rangePool = <_Range>[];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final snake = midPoint(range, cb, forward, backward);

    if (snake != null) {
      // if it has a diagonal, save it
      if (snake.diagonalSize() > 0) {
        diagonals.add(snake.toDiagonal());
      }

      // add new ranges for left and right
      final _Range left = rangePool.isEmpty
          ? _Range.empty()
          : rangePool.removeAt(rangePool.length - 1);
      left.oldListStart = range.oldListStart;
      left.newListStart = range.newListStart;
      left.oldListEnd = snake.startX;
      left.newListEnd = snake.startY;

      stack.add(left);

      // re-use range for right
      //noinspection UnnecessaryLocalVariable
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

  return DiffResult._(cb, diagonals, forward.data, backward.data, detectMoves);
}

/// calculate the difference between the two given lists.
///
/// @param oldList the old list
/// @param newList the new list
/// @param detectMoves wheter move detection should be enabled
/// @param equalityChecker use this if you don't want to use the equality as defined by the == operator
DiffResult<T> calculateListDiff<T>(
  List<T> oldList,
  List<T> newList, {
  bool detectMoves = true,
  bool Function(T, T)? equalityChecker,
}) {
  return calculateDiff<T>(
    ListDiffDelegate<T>(oldList, newList, equalityChecker),
    detectMoves: detectMoves,
  );
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

_Snake? midPoint(_Range range, DiffDelegate cb, _CenteredArray forward,
    _CenteredArray backward) {
  if (range.oldSize() < 1 || range.newSize() < 1) {
    return null;
  }
  final max = (range.oldSize() + range.newSize() + 1) ~/ 2;
  forward[1] = range.oldListStart;
  backward[1] = range.oldListEnd;
  for (int d = 0; d < max; d++) {
    _Snake? snake = forwardSnake(range, cb, forward, backward, d);
    if (snake != null) {
      return snake;
    }
    snake = backwardSnake(range, cb, forward, backward, d);
    if (snake != null) {
      return snake;
    }
  }
  return null;
}

_Snake? forwardSnake(_Range range, DiffDelegate cb, _CenteredArray forward,
    _CenteredArray backward, int d) {
  final bool checkForSnake = (range.oldSize() - range.newSize()).abs() % 2 == 1;
  final delta = range.oldSize() - range.newSize();
  for (int k = -d; k <= d; k += 2) {
    // we either come from d-1, k-1 OR d-1. k+1
    // as we move in steps of 2, array always holds both current and previous d values
    // k = x - y and each array value holds the max X, y = x - k
    final int startX;
    final int startY;
    int x, y;
    if (k == -d || (k != d && forward[k + 1] > forward[k - 1])) {
      // picking k + 1, incrementing Y (by simply not incrementing X)
      x = startX = forward[k + 1];
    } else {
      // picking k - 1, incrementing X
      startX = forward[k - 1];
      x = startX + 1;
    }
    y = range.newListStart + (x - range.oldListStart) - k;
    startY = (d == 0 || x != startX) ? y : y - 1;
    // now find snake size
    while (x < range.oldListEnd &&
        y < range.newListEnd &&
        cb.areItemsTheSame(x, y)) {
      x++;
      y++;
    }
    // now we have furthest reaching x, record it
    forward[k] = x;
    if (checkForSnake) {
      // see if we did pass over a backwards array
      // mapping function: delta - k
      final backwardsK = delta - k;
      // if backwards K is calculated and it passed me, found match
      if (backwardsK >= -d + 1 &&
          backwardsK <= d - 1 &&
          backward[(backwardsK)] <= x) {
        // match
        final snake = _Snake(
            startX: startX, startY: startY, endX: x, endY: y, reverse: false);
        return snake;
      }
    }
  }
  return null;
}

_Snake? backwardSnake(_Range range, DiffDelegate cb, _CenteredArray forward,
    _CenteredArray backward, int d) {
  final checkForSnake = (range.oldSize() - range.newSize()) % 2 == 0;
  final delta = range.oldSize() - range.newSize();
  // same as forward but we go backwards from end of the lists to be beginning
  // this also means we'll try to optimize for minimizing x instead of maximizing it
  for (int k = -d; k <= d; k += 2) {
    // we either come from d-1, k-1 OR d-1, k+1
    // as we move in steps of 2, array always holds both current and previous d values
    // k = x - y and each array value holds the MIN X, y = x - k
    // when x's are equal, we prioritize deletion over insertion
    final int startX;
    final int startY;
    int x, y;

    if (k == -d || (k != d && backward[(k + 1)] < backward[(k - 1)])) {
      // picking k + 1, decrementing Y (by simply not decrementing X)
      x = startX = backward[(k + 1)];
    } else {
      // picking k - 1, decrementing X
      startX = backward[(k - 1)];
      x = startX - 1;
    }
    y = range.newListEnd - ((range.oldListEnd - x) - k);
    startY = (d == 0 || x != startX) ? y : y + 1;
    // now find snake size
    while (x > range.oldListStart &&
        y > range.newListStart &&
        cb.areItemsTheSame(x - 1, y - 1)) {
      x--;
      y--;
    }
    // now we have furthest point, record it (min X)
    backward[k] = x;
    if (checkForSnake) {
      // see if we did pass over a backwards array
      // mapping function: delta - k
      final forwardsK = delta - k;
      // if forwards K is calculated and it passed me, found match
      if (forwardsK >= -d && forwardsK <= d && forward[(forwardsK)] >= x) {
        // match
        final snake = _Snake(
            // assignment are reverse since we are a reverse snake
            startX: x,
            startY: y,
            endX: startX,
            endY: startY,
            reverse: true);
        return snake;
      }
    }
  }
  return null;
}
