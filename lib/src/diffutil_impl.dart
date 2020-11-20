import 'dart:math';
import 'dart:typed_data';

import 'package:diffutil_dart/src/diff_delegate.dart';
import 'package:diffutil_dart/src/model/diffupdate.dart';

///
///Snakes represent a match between two lists. It is optionally prefixed or postfixed with an
///add or remove operation. See the Myers' paper for details.
///
class _Snake {
  ///
  ///Position in the old list
  ///
  int x;

  ///
  ///Position in the new list
  ///
  int y;

  ///
  ///Number of matches. Might be 0.
  ///
  int size;

  ///
  ///If true, this is a removal from the original list followed by {@code size} matches.
  ///If false, this is an addition from the new list followed by {@code size} matches.
  ///
  bool removal;

  ///
  ///If true, the addition or removal is at the end of the snake.
  ///If false, the addition or removal is at the beginning of the snake.
  ///
  bool reverse;

  _Snake(
      {required this.x,
      required this.y,
      required this.size,
      required this.removal,
      required this.reverse});

  @override
  String toString() {
    return 'Snake{x: $x, y: $y, size: $size, removal: $removal, reverse: $reverse}';
  }
}

final Comparator<_Snake> _snakeComparator = (o1, o2) {
  final cmpX = o1.x - o2.x;
  return cmpX == 0 ? o1.y - o2.y : cmpX;
};

class _Range {
  int? oldListStart;
  int? oldListEnd;
  int? newListStart;
  int? newListEnd;

  _Range(
      {this.oldListStart, this.oldListEnd, this.newListStart, this.newListEnd});
}

///
///This class holds the information about the result of a
/// calculateDiff call.
///<p>
///You can consume the updates in a DiffResult via
/// dispatchUpdatesTo().
///
class DiffResult {
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

  // Ignore this update.
  // If this is an addition from the new list, it means the item is actually removed from an
  // earlier position and its move will be dispatched when we process the matching removal
  // from the old list.
  // If this is a removal from the old list, it means the item is actually added back to an
  // earlier index in the new list and we'll dispatch its move when we are processing that
  // addition.
  static const int FLAG_IGNORE = FLAG_MOVED_NOT_CHANGED << 1;

  // since we are re-using the int arrays that were created in the Myers' step, we mask
  // change flags
  static const int FLAG_OFFSET = 5;
  static const int FLAG_MASK = (1 << FLAG_OFFSET) - 1;

  // The Myers' snakes. At this point, we only care about their diagonal sections.
  final List<_Snake> _mSnakes;

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
  DiffResult._(DiffDelegate callback, List<_Snake> snakes,
      List<int> oldItemStatuses, List<int> newItemStatuses, bool detectMoves)
      : _mSnakes = snakes,
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
    _addRootSnake();
    _findMatchingItems();
  }

  ///
  ///We always add a Snake to 0/0 so that we can run loops from end to beginning and be done
  ///when we run out of snakes.
  ///
  void _addRootSnake() {
    final firstSnake = _mSnakes.isEmpty ? null : _mSnakes.first;
    if (firstSnake == null || firstSnake.x != 0 || firstSnake.y != 0) {
      final root = _Snake(x: 0, y: 0, removal: false, size: 0, reverse: false);
      _mSnakes.insert(0, root);
    }
  }

  ///
  ///This method traverses each addition / removal and tries to match it to a previous
  ///removal / addition. This is how we detect move operations.
  ///<p>
  ///This class also flags whether an item has been changed or not.
  ///<p>
  ///DiffUtil does this pre-processing so that if it is running on a big list, it can be moved
  ///to background thread where most of the expensive stuff will be calculated and kept in
  ///the statuses maps. DiffResult uses this pre-calculated information while dispatching
  ///the updates (which is probably being called on the main thread).
  ///
  void _findMatchingItems() {
    int? posOld = _mOldListSize;
    int? posNew = _mNewListSize;
    // traverse the matrix from right bottom to 0,0.
    for (var i = _mSnakes.length - 1; i >= 0; i--) {
      final snake = _mSnakes[i];
      final endX = snake.x + snake.size;
      final endY = snake.y + snake.size;
      if (_mDetectMoves) {
        while (posOld! > endX) {
          // this is a removal. Check remaining snakes to see if this was added before
          _findAddition(posOld, posNew, i);
          posOld--;
        }
        while (posNew! > endY) {
          // this is an addition. Check remaining snakes to see if this was removed
          // before
          _findRemoval(posOld, posNew, i);
          posNew--;
        }
      }
      for (var j = 0; j < snake.size; j++) {
        // matching items. Check if it is changed or not
        final oldItemPos = snake.x + j;
        final newItemPos = snake.y + j;
        final isSame = _mCallback.areContentsTheSame(oldItemPos, newItemPos);
        final changeFlag = isSame ? FLAG_NOT_CHANGED : FLAG_CHANGED;
        _mOldItemStatuses[oldItemPos] =
            (newItemPos << FLAG_OFFSET) | changeFlag;
        _mNewItemStatuses[newItemPos] =
            (oldItemPos << FLAG_OFFSET) | changeFlag;
      }
      posOld = snake.x;
      posNew = snake.y;
    }
  }

  void _findAddition(int x, int? y, int snakeIndex) {
    if (_mOldItemStatuses[x - 1] != 0) {
      return; // already set by a latter item
    }
    _findMatchingItem(x, y, snakeIndex, false);
  }

  void _findRemoval(int? x, int y, int snakeIndex) {
    if (_mNewItemStatuses[y - 1] != 0) {
      return; // already set by a latter item
    }
    _findMatchingItem(x, y, snakeIndex, true);
  }

  ///
  ///Finds a matching item that is before the given coordinates in the matrix
  ///(before : left and above).*

  ///@param x The x position in the matrix (position in the old list)
  ///@param y The y position in the matrix (position in the new list)
  ///@param snakeIndex The current snake index
  ///@param removal True if we are looking for a removal, false otherwise
  ///

  ///@return True if such item is found.
  ///
  bool _findMatchingItem(
      final int? x, final int? y, final int snakeIndex, final bool removal) {
    int myItemPos;
    int? curX;
    int? curY;
    if (removal) {
      myItemPos = y! - 1;
      curX = x;
      curY = y - 1;
    } else {
      myItemPos = x! - 1;
      curX = x - 1;
      curY = y;
    }
    for (var i = snakeIndex; i >= 0; i--) {
      final snake = _mSnakes[i];
      final endX = snake.x + snake.size;
      final endY = snake.y + snake.size;
      if (removal) {
        // check removals for a match
        for (var pos = curX! - 1; pos >= endX; pos--) {
          if (_mCallback.areItemsTheSame(pos, myItemPos)) {
            // found!
            final isSame = _mCallback.areContentsTheSame(pos, myItemPos);
            final changeFlag =
                isSame ? FLAG_MOVED_NOT_CHANGED : FLAG_MOVED_CHANGED;
            _mNewItemStatuses[myItemPos] = (pos << FLAG_OFFSET) | FLAG_IGNORE;
            _mOldItemStatuses[pos] = (myItemPos << FLAG_OFFSET) | changeFlag;
            return true;
          }
        }
      } else {
        // check for additions for a match
        for (var pos = curY! - 1; pos >= endY; pos--) {
          if (_mCallback.areItemsTheSame(myItemPos, pos)) {
            // found
            final isSame = _mCallback.areContentsTheSame(myItemPos, pos);
            final changeFlag =
                isSame ? FLAG_MOVED_NOT_CHANGED : FLAG_MOVED_CHANGED;
            _mOldItemStatuses[x! - 1] = (pos << FLAG_OFFSET) | FLAG_IGNORE;
            _mNewItemStatuses[pos] = ((x - 1) << FLAG_OFFSET) | changeFlag;
            return true;
          }
        }
      }
      curX = snake.x;
      curY = snake.y;
    }
    return false;
  }

  Iterable<DiffUpdate> getUpdates({bool batch = true}) {
    final updates = <DiffUpdate>[];
    // These are add/remove ops that are converted to moves. We track their positions until
    // their respective update operations are processed.
    final postponedUpdates = <_PostponedUpdate>[];
    int? posOld = _mOldListSize;
    int? posNew = _mNewListSize;
    for (var snakeIndex = _mSnakes.length - 1; snakeIndex >= 0; snakeIndex--) {
      final snake = _mSnakes[snakeIndex];
      final snakeSize = snake.size;
      final endX = snake.x + snakeSize;
      final endY = snake.y + snakeSize;
      if (endX < posOld!) {
        _dispatchRemovals(postponedUpdates, updates, endX, posOld - endX, endX);
      }
      if (endY < posNew!) {
        _dispatchAdditions(
            postponedUpdates, updates, endX, posNew - endY, endY);
      }
      for (var i = snakeSize - 1; i >= 0; i--) {
        if ((_mOldItemStatuses[snake.x + i] & FLAG_MASK) == FLAG_CHANGED) {
          updates.add(DiffUpdate.change(
              position: snake.x + i,
              payload: _mCallback.getChangePayload(snake.x + i, snake.y + i)));
        }
      }
      posOld = snake.x;
      posNew = snake.y;
    }
    return batch ? updates.batch() : updates;
  }

  static _PostponedUpdate? _removePostponedUpdate(
      List<_PostponedUpdate> updates, int pos, bool removal) {
    for (var i = updates.length - 1; i >= 0; i--) {
      final update = updates[i];
      if (update.posInOwnerList == pos && update.removal == removal) {
        updates.removeAt(i);
        for (var j = i; j < updates.length; j++) {
          // offset other ops since they swapped positions
          updates[j].currentPos += removal ? 1 : -1;
        }
        return update;
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'DiffResult{mSnakes: $_mSnakes}, ';
  }

  void _dispatchRemovals(List<_PostponedUpdate> postponedUpdates,
      List<DiffUpdate> updates, int start, int count, int globalIndex) {
    if (!_mDetectMoves) {
      updates.add(DiffUpdate.remove(position: start, count: count));
      return;
    }
    for (var i = count - 1; i >= 0; i--) {
      final status = _mOldItemStatuses[globalIndex + i] & FLAG_MASK;
      switch (status) {
        case 0: // real removal
          updates.add(DiffUpdate.remove(position: start + i, count: 1));
          for (final update in postponedUpdates) {
            update.currentPos -= 1;
          }
          break;
        case FLAG_MOVED_CHANGED:
        case FLAG_MOVED_NOT_CHANGED:
          final pos = _mOldItemStatuses[globalIndex + i] >> FLAG_OFFSET;
          final update = _removePostponedUpdate(postponedUpdates, pos, false)!;
          // the item was moved to that position. we do -1 because this is a move not
          // add and removing current item offsets the target move by 1
          //noinspection ConstantConditions
          updates
              .add(DiffUpdate.move(from: start + i, to: update.currentPos - 1));
          if (status == FLAG_MOVED_CHANGED) {
            // also dispatch a change
            updates.add(DiffUpdate.change(
                position: update.currentPos - 1,
                payload: _mCallback.getChangePayload(globalIndex + i, pos)));
          }
          break;
        case FLAG_IGNORE: // ignoring this
          postponedUpdates.add(_PostponedUpdate(
              posInOwnerList: globalIndex + i,
              currentPos: start + i,
              removal: true));
          break;
        default:
          throw StateError(
              'unknown flag for pos  ${globalIndex + i}:  $status');
      }
    }
  }

  void _dispatchAdditions(List<_PostponedUpdate> postponedUpdates,
      List<DiffUpdate> updates, int start, int count, int globalIndex) {
    if (!_mDetectMoves) {
      updates.add(DiffUpdate.insert(position: start, count: count));
      return;
    }
    for (var i = count - 1; i >= 0; i--) {
      final status = _mNewItemStatuses[globalIndex + i] & FLAG_MASK;
      switch (status) {
        case 0: // real addition
          updates.add(DiffUpdate.insert(position: start, count: 1));
          for (final update in postponedUpdates) {
            update.currentPos += 1;
          }
          break;
        case FLAG_MOVED_CHANGED:
        case FLAG_MOVED_NOT_CHANGED:
          final pos = _mNewItemStatuses[globalIndex + i] >> FLAG_OFFSET;
          final update = _removePostponedUpdate(postponedUpdates, pos, true)!;
          // the item was moved from that position
          updates.add(DiffUpdate.move(from: update.currentPos, to: start));
          if (status == FLAG_MOVED_CHANGED) {
            // also dispatch a change
            updates.add(DiffUpdate.change(
                position: start,
                payload: _mCallback.getChangePayload(pos, globalIndex + i)));
          }
          break;
        case FLAG_IGNORE: // ignoring this
          postponedUpdates.add(_PostponedUpdate(
              posInOwnerList: globalIndex + i,
              currentPos: start,
              removal: false));
          break;
        default:
          throw StateError('unknown flag for pos ${globalIndex + i}:  $status');
      }
    }
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
DiffResult calculateDiff(DiffDelegate cb, {bool detectMoves = false}) {
  final oldSize = cb.getOldListSize();
  final newSize = cb.getNewListSize();
  final snakes = <_Snake>[];
  // instead of a recursive implementation, we keep our own stack to avoid potential stack
  // overflow exceptions
  final stack = <_Range>[];
  stack.add(_Range(
      oldListStart: 0,
      oldListEnd: oldSize,
      newListStart: 0,
      newListEnd: newSize));
  final max = oldSize + newSize + (oldSize - newSize).abs();
  // allocate forward and backward k-lines. K lines are diagonal lines in the matrix. (see the
  // paper for details)
  // These arrays lines keep the max reachable position for each k-line.
  final forward = Int32List(max * 2);
  final backward = Int32List(max * 2);
  // We pool the ranges to avoid allocations for each recursive call.
  final rangePool = <_Range>[];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final snake = _diffPartial(cb, range.oldListStart!, range.oldListEnd!,
        range.newListStart!, range.newListEnd!, forward, backward, max);
    if (snake != null) {
      if (snake.size > 0) {
        snakes.add(snake);
      }
      // offset the snake to convert its coordinates from the Range's area to global
      snake.x += range.oldListStart!;
      snake.y += range.newListStart!;
      // add new ranges for left and right
      final left = rangePool.isEmpty ? _Range() : rangePool.removeLast();
      left.oldListStart = range.oldListStart;
      left.newListStart = range.newListStart;
      if (snake.reverse) {
        left.oldListEnd = snake.x;
        left.newListEnd = snake.y;
      } else {
        if (snake.removal) {
          left.oldListEnd = snake.x - 1;
          left.newListEnd = snake.y;
        } else {
          left.oldListEnd = snake.x;
          left.newListEnd = snake.y - 1;
        }
      }
      stack.add(left);
      // re-use range for right
      //noinspection UnnecessaryLocalVariable
      final right = range;
      if (snake.reverse) {
        if (snake.removal) {
          right.oldListStart = snake.x + snake.size + 1;
          right.newListStart = snake.y + snake.size;
        } else {
          right.oldListStart = snake.x + snake.size;
          right.newListStart = snake.y + snake.size + 1;
        }
      } else {
        right.oldListStart = snake.x + snake.size;
        right.newListStart = snake.y + snake.size;
      }
      stack.add(right);
    } else {
      rangePool.add(range);
    }
  }
  // sort snakes
  snakes.sort(_snakeComparator);
  return DiffResult._(cb, snakes, forward, backward, detectMoves);
}

_Snake? _diffPartial(DiffDelegate cb, int startOld, int endOld, int startNew,
    int endNew, List<int> forward, List<int> backward, int kOffset) {
  final oldSize = endOld - startOld;
  final newSize = endNew - startNew;
  if (endOld - startOld < 1 || endNew - startNew < 1) {
    return null;
  }
  final delta = oldSize - newSize;
  final dLimit = (oldSize + newSize + 1) ~/ 2;
  forward.fillRange(kOffset - dLimit - 1, kOffset + dLimit + 1, 0);
  // Arrays.fill(forward, kOffset - dLimit - 1, kOffset + dLimit + 1, 0);
  backward.fillRange(
      kOffset - dLimit - 1 + delta, kOffset + dLimit + 1 + delta, oldSize);
  final checkInFwd = delta % 2 != 0;
  for (var d = 0; d <= dLimit; d++) {
    for (var k = -d; k <= d; k += 2) {
// find forward path
// we can reach k from k - 1 or k + 1. Check which one is further in the graph
      int x;
      bool removal;
      if (k == -d ||
          k != d && forward[kOffset + k - 1] < forward[kOffset + k + 1]) {
        x = forward[kOffset + k + 1];
        removal = false;
      } else {
        x = forward[kOffset + k - 1] + 1;
        removal = true;
      }
// set y based on x
      var y = x - k;
// move diagonal as long as items match
      while (x < oldSize &&
          y < newSize &&
          cb.areItemsTheSame(startOld + x, startNew + y)) {
        x++;
        y++;
      }
      forward[kOffset + k] = x;
      if (checkInFwd && k >= delta - d + 1 && k <= delta + d - 1) {
        if (forward[kOffset + k] >= backward[kOffset + k]) {
          final x = backward[kOffset + k];
          final outSnake = _Snake(
            x: x,
            y: x - k,
            size: forward[kOffset + k] - backward[kOffset + k],
            removal: removal,
            reverse: false,
          );
          return outSnake;
        }
      }
    }
    for (var k = -d; k <= d; k += 2) {
// find reverse path at k + delta, in reverse
      final backwardK = k + delta;
      int x;
      bool removal;
      if (backwardK == d + delta ||
          backwardK != -d + delta &&
              backward[kOffset + backwardK - 1] <
                  backward[kOffset + backwardK + 1]) {
        x = backward[kOffset + backwardK - 1];
        removal = false;
      } else {
        x = backward[kOffset + backwardK + 1] - 1;
        removal = true;
      }
// set y based on x
      var y = x - backwardK;
// move diagonal as long as items match
      while (x > 0 &&
          y > 0 &&
          cb.areItemsTheSame(startOld + x - 1, startNew + y - 1)) {
        x--;
        y--;
      }
      backward[kOffset + backwardK] = x;
      if (!checkInFwd && k + delta >= -d && k + delta <= d) {
        if (forward[kOffset + backwardK] >= backward[kOffset + backwardK]) {
          final x = backward[kOffset + backwardK];
          final outSnake = _Snake(
            x: x,
            y: x - backwardK,
            size: forward[kOffset + backwardK] - backward[kOffset + backwardK],
            removal: removal,
            reverse: true,
          );
          return outSnake;
        }
      }
    }
  }
  throw StateError('''DiffUtil hit an unexpected case while trying to calculate
the optimal path. Please make sure your data is not changing during the
diff calculation.''');
}

/// calculate the difference between the two given lists.
///
/// @param oldList the old list
/// @param newList the new list
/// @param detectMoves wheter move detection should be enabled
/// @param equalityChecker use this if you don't want to use the equality as defined by the == operator
DiffResult calculateListDiff<T>(List<T> oldList, List<T> newList,
    {bool detectMoves = true, bool Function(T, T)? equalityChecker}) {
  return calculateDiff(ListDiffDelegate(oldList, newList, equalityChecker),
      detectMoves: detectMoves);
}

/// you can use this function if you want to use custom list-types, such as BuiltList
/// or KtList and want to avoid copying
DiffResult calculateCustomListDiff<T, L>(L oldList, L newList,
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
