import 'dart:math' as math;
import 'dart:typed_data';

import 'package:diffutil.dart/src/diff_delegate.dart';


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

  _Snake({this.x, this.y, this.size, this.removal, this.reverse});

  @override
  String toString() {
    return 'Snake{x: $x, y: $y, size: $size, removal: $removal, reverse: $reverse}';
  }
}

final Comparator<_Snake> _snakeComparator = (o1, o2) {
  final int cmpX = o1.x - o2.x;
  return cmpX == 0 ? o1.y - o2.y : cmpX;
};

class _Range {
  int oldListStart;
  int oldListEnd;
  int newListStart;
  int newListEnd;

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
  ///Below, when an item is mentioned to stay in the same "location", it means we won't
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
  final List<_Snake> mSnakes;

  // The list to keep oldItemStatuses. As we traverse old items, we assign flags to them
  // which also includes whether they were a real removal or a move (and its new index).
  final List<int> mOldItemStatuses;

  // The list to keep newItemStatuses. As we traverse new items, we assign flags to them
  // which also includes whether they were a real addition or a move(and its old index).
  final List<int> mNewItemStatuses;

  // The callback that was given to calcualte diff method.
  final DiffDelegate mCallback;
  final int mOldListSize;
  final int mNewListSize;
  final bool mDetectMoves;

  ///
  ///@param callback The callback that was used to calculate the diff
  ///@param snakes The list of Myers' snakes
  ///@param oldItemStatuses An int[] that can be re-purposed to keep metadata
  ///@param newItemStatuses An int[] that can be re-purposed to keep metadata
  ///@param detectMoves True if this DiffResult will try to detect moved items
  ///
  DiffResult._(DiffDelegate callback, List<_Snake> snakes,
      List<int> oldItemStatuses, List<int> newItemStatuses, bool detectMoves)
      : mSnakes = snakes,
        mOldItemStatuses = oldItemStatuses,
        mNewItemStatuses = newItemStatuses,
        mCallback = callback,
        mOldListSize = callback.getOldListSize(),
        mNewListSize = callback.getNewListSize(),
        mDetectMoves = detectMoves {
    if (mOldItemStatuses.isNotEmpty) {
      mOldItemStatuses.fillRange(0, mOldItemStatuses.length - 1, 0);
    }
    if (mNewItemStatuses.isNotEmpty) {
      mNewItemStatuses.fillRange(0, mNewItemStatuses.length - 1, 0);
    }
    _addRootSnake();
    _findMatchingItems();
  }

  ///
  ///We always add a Snake to 0/0 so that we can run loops from end to beginning and be done
  ///when we run out of snakes.
  ///
  void _addRootSnake() {
    final _Snake firstSnake = mSnakes.isEmpty ? null : mSnakes.first;
    if (firstSnake == null || firstSnake.x != 0 || firstSnake.y != 0) {
      final root = _Snake(x: 0, y: 0, removal: false, size: 0, reverse: false);
      mSnakes.insert(0, root);
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
    int posOld = mOldListSize;
    int posNew = mNewListSize;
    // traverse the matrix from right bottom to 0,0.
    for (int i = mSnakes.length - 1; i >= 0; i--) {
      final _Snake snake = mSnakes[i];
      final int endX = snake.x + snake.size;
      final int endY = snake.y + snake.size;
      if (mDetectMoves) {
        while (posOld > endX) {
          // this is a removal. Check remaining snakes to see if this was added before
          _findAddition(posOld, posNew, i);
          posOld--;
        }
        while (posNew > endY) {
          // this is an addition. Check remaining snakes to see if this was removed
          // before
          _findRemoval(posOld, posNew, i);
          posNew--;
        }
      }
      for (int j = 0; j < snake.size; j++) {
        // matching items. Check if it is changed or not
        final int oldItemPos = snake.x + j;
        final int newItemPos = snake.y + j;
        final bool theSame =
            mCallback.areContentsTheSame(oldItemPos, newItemPos);
        final int changeFlag = theSame ? FLAG_NOT_CHANGED : FLAG_CHANGED;
        mOldItemStatuses[oldItemPos] = (newItemPos << FLAG_OFFSET) | changeFlag;
        mNewItemStatuses[newItemPos] = (oldItemPos << FLAG_OFFSET) | changeFlag;
      }
      posOld = snake.x;
      posNew = snake.y;
    }
  }

  void _findAddition(int x, int y, int snakeIndex) {
    if (mOldItemStatuses[x - 1] != 0) {
      return; // already set by a latter item
    }
    _findMatchingItem(x, y, snakeIndex, false);
  }

  void _findRemoval(int x, int y, int snakeIndex) {
    if (mNewItemStatuses[y - 1] != 0) {
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
      final int x, final int y, final int snakeIndex, final bool removal) {
    int myItemPos;
    int curX;
    int curY;
    if (removal) {
      myItemPos = y - 1;
      curX = x;
      curY = y - 1;
    } else {
      myItemPos = x - 1;
      curX = x - 1;
      curY = y;
    }
    for (int i = snakeIndex; i >= 0; i--) {
      final _Snake snake = mSnakes[i];
      final int endX = snake.x + snake.size;
      final int endY = snake.y + snake.size;
      if (removal) {
        // check removals for a match
        for (int pos = curX - 1; pos >= endX; pos--) {
          if (mCallback.areItemsTheSame(pos, myItemPos)) {
            // found!
            final bool theSame = mCallback.areContentsTheSame(pos, myItemPos);
            final int changeFlag =
                theSame ? FLAG_MOVED_NOT_CHANGED : FLAG_MOVED_CHANGED;
            mNewItemStatuses[myItemPos] = (pos << FLAG_OFFSET) | FLAG_IGNORE;
            mOldItemStatuses[pos] = (myItemPos << FLAG_OFFSET) | changeFlag;
            return true;
          }
        }
      } else {
        // check for additions for a match
        for (int pos = curY - 1; pos >= endY; pos--) {
          if (mCallback.areItemsTheSame(myItemPos, pos)) {
            // found
            final bool theSame = mCallback.areContentsTheSame(myItemPos, pos);
            final int changeFlag =
                theSame ? FLAG_MOVED_NOT_CHANGED : FLAG_MOVED_CHANGED;
            mOldItemStatuses[x - 1] = (pos << FLAG_OFFSET) | FLAG_IGNORE;
            mNewItemStatuses[pos] = ((x - 1) << FLAG_OFFSET) | changeFlag;
            return true;
          }
        }
      }
      curX = snake.x;
      curY = snake.y;
    }
    return false;
  }

  ///
  ///Dispatches update operations to the given Callback.
  ///<p>
  ///These updates are atomic such that the first update call effects every update call that
  ///comes after it (the same as RecyclerView).*

  ///@param updateCallback The callback to receive the update operations.
  ///@see #dispatchUpdatesTo(RecyclerView.Adapter)
  ///

  void dispatchUpdatesTo(ListUpdateCallback updateCallback) {
    BatchingListUpdateCallback batchingCallback;
    if (updateCallback is BatchingListUpdateCallback) {
      batchingCallback = updateCallback;
    } else {
      batchingCallback = BatchingListUpdateCallback(updateCallback);
      // replace updateCallback with a batching callback and override references to
      // updateCallback so that we don't call it directly by mistake
      //noinspection UnusedAssignment
      updateCallback = batchingCallback;
    }
    // These are add/remove ops that are converted to moves. We track their positions until
    // their respective update operations are processed.
    final List<_PostponedUpdate> postponedUpdates = [];
    int posOld = mOldListSize;
    int posNew = mNewListSize;
    for (int snakeIndex = mSnakes.length - 1; snakeIndex >= 0; snakeIndex--) {
      final _Snake snake = mSnakes[snakeIndex];
      final int snakeSize = snake.size;
      final int endX = snake.x + snakeSize;
      final int endY = snake.y + snakeSize;
      if (endX < posOld) {
        _dispatchRemovals(
            postponedUpdates, batchingCallback, endX, posOld - endX, endX);
      }
      if (endY < posNew) {
        _dispatchAdditions(
            postponedUpdates, batchingCallback, endX, posNew - endY, endY);
      }
      for (int i = snakeSize - 1; i >= 0; i--) {
        if ((mOldItemStatuses[snake.x + i] & FLAG_MASK) == FLAG_CHANGED) {
          batchingCallback.onChanged(snake.x + i, 1,
              mCallback.getChangePayload(snake.x + i, snake.y + i));
        }
      }
      posOld = snake.x;
      posNew = snake.y;
    }
    batchingCallback.dispatchLastEvent();
  }

  static _PostponedUpdate _removePostponedUpdate(
      List<_PostponedUpdate> updates, int pos, bool removal) {
    for (int i = updates.length - 1; i >= 0; i--) {
      final _PostponedUpdate update = updates[i];
      if (update.posInOwnerList == pos && update.removal == removal) {
        updates.remove(i);
        for (int j = i; j < updates.length; j++) {
          // offset other ops since they swapped positions
          updates[j].currentPos += removal ? 1 : -1;
        }
        return update;
      }
    }
    return null;
  }

  void _dispatchAdditions(
      List<_PostponedUpdate> postponedUpdates,
      ListUpdateCallback updateCallback,
      int start,
      int count,
      int globalIndex) {
    if (!mDetectMoves) {
      updateCallback.onInserted(start, count);
      return;
    }
    for (int i = count - 1; i >= 0; i--) {
      final int status = mNewItemStatuses[globalIndex + i] & FLAG_MASK;
      switch (status) {
        case 0: // real addition
          updateCallback.onInserted(start, 1);
          for (_PostponedUpdate update in postponedUpdates) {
            update.currentPos += 1;
          }
          break;
        case FLAG_MOVED_CHANGED:
        case FLAG_MOVED_NOT_CHANGED:
          final int pos = mNewItemStatuses[globalIndex + i] >> FLAG_OFFSET;
          final _PostponedUpdate update =
              _removePostponedUpdate(postponedUpdates, pos, true);
          // the item was moved from that position
          //noinspection ConstantConditions
          updateCallback.onMoved(update.currentPos, start);
          if (status == FLAG_MOVED_CHANGED) {
            // also dispatch a change
            updateCallback.onChanged(
                start, 1, mCallback.getChangePayload(pos, globalIndex + i));
          }
          break;
        case FLAG_IGNORE: // ignoring this
          postponedUpdates.add(_PostponedUpdate(
              posInOwnerList: globalIndex + i,
              currentPos: start,
              removal: false));
          break;
        default:
          throw StateError("unknown flag for pos ${globalIndex + i}:  $status");
      }
    }
  }

  void _dispatchRemovals(
      List<_PostponedUpdate> postponedUpdates,
      ListUpdateCallback updateCallback,
      int start,
      int count,
      int globalIndex) {
    if (!mDetectMoves) {
      updateCallback.onRemoved(start, count);
      return;
    }
    for (int i = count - 1; i >= 0; i--) {
      final int status = mOldItemStatuses[globalIndex + i] & FLAG_MASK;
      switch (status) {
        case 0: // real removal
          updateCallback.onRemoved(start + i, 1);
          for (_PostponedUpdate update in postponedUpdates) {
            update.currentPos -= 1;
          }
          break;
        case FLAG_MOVED_CHANGED:
        case FLAG_MOVED_NOT_CHANGED:
          final int pos = mOldItemStatuses[globalIndex + i] >> FLAG_OFFSET;
          final _PostponedUpdate update =
              _removePostponedUpdate(postponedUpdates, pos, false);
          // the item was moved to that position. we do -1 because this is a move not
          // add and removing current item offsets the target move by 1
          //noinspection ConstantConditions
          updateCallback.onMoved(start + i, update.currentPos - 1);
          if (status == FLAG_MOVED_CHANGED) {
            // also dispatch a change
            updateCallback.onChanged(update.currentPos - 1, 1,
                mCallback.getChangePayload(globalIndex + i, pos));
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
              "unknown flag for pos  ${globalIndex + i}:  $status");
      }
    }
  }

  @override
  String toString() {
    return 'DiffResult{mSnakes: $mSnakes}, ';
  }
}



class _PostponedUpdate {
  final int posInOwnerList;
  int currentPos;
  final bool removal;

  _PostponedUpdate({this.posInOwnerList, this.currentPos, this.removal});
}

abstract class ListUpdateCallback {
  ///
  ///Called when {@code count} number of items are inserted at the given position.
  ///
  ///@param position The position of the new item.
  ///@param count    The number of items that have been added.
  ///
  void onInserted(int position, int count);

  ///
  ///Called when {@code count} number of items are removed from the given position.
  ///
  ///@param position The position of the item which has been removed.
  ///@param count    The number of items which have been removed.
  ///
  void onRemoved(int position, int count);

  ///
  ///Called when an item changes its position in the list.
  ///
  ///@param fromPosition The previous position of the item before the move.
  ///@param toPosition   The new position of the item.
  ///
  void onMoved(int fromPosition, int toPosition);

  ///
  ///Called when {@code count} number of items are updated at the given position.
  ///
  ///@param position The position of the item which has been updated.
  ///@param count    The number of items which has changed.
  ///
  void onChanged(int position, int count, Object payload);
}

///
///Wraps a [ListUpdateCallback] callback and batches operations that can be merged.
///<p>
///For instance, when 2 add operations comes that adds 2 consecutive elements,
///BatchingListUpdateCallback merges them and calls the wrapped callback only once.
///<p>
///If you use this class to batch updates, you must call dispatchLastEvent() when the
///stream of update events drain.
///

class BatchingListUpdateCallback implements ListUpdateCallback {
  static const int TYPE_NONE = 0;
  static const int TYPE_ADD = 1;
  static const int TYPE_REMOVE = 2;
  static const int TYPE_CHANGE = 3;
  final ListUpdateCallback mWrapped;
  int mLastEventType = TYPE_NONE;
  int mLastEventPosition = -1;
  int mLastEventCount = -1;
  Object mLastEventPayload;

  BatchingListUpdateCallback(this.mWrapped);

  ///BatchingListUpdateCallback holds onto the last event to see if it can be merged with the
  ///next one. When stream of events finish, you should call this method to dispatch the last
  ///event.
  ///
  void dispatchLastEvent() {
    if (mLastEventType == TYPE_NONE) {
      return;
    }
    switch (mLastEventType) {
      case TYPE_ADD:
        mWrapped.onInserted(mLastEventPosition, mLastEventCount);
        break;
      case TYPE_REMOVE:
        mWrapped.onRemoved(mLastEventPosition, mLastEventCount);
        break;
      case TYPE_CHANGE:
        mWrapped.onChanged(
            mLastEventPosition, mLastEventCount, mLastEventPayload);
        break;
    }
    mLastEventPayload = null;
    mLastEventType = TYPE_NONE;
  }

  void onInserted(int position, int count) {
    if (mLastEventType == TYPE_ADD &&
        position >= mLastEventPosition &&
        position <= mLastEventPosition + mLastEventCount) {
      mLastEventCount += count;
      mLastEventPosition = math.min(position, mLastEventPosition);
      return;
    }
    dispatchLastEvent();
    mLastEventPosition = position;
    mLastEventCount = count;
    mLastEventType = TYPE_ADD;
  }

  void onRemoved(int position, int count) {
    if (mLastEventType == TYPE_REMOVE &&
        mLastEventPosition >= position &&
        mLastEventPosition <= position + count) {
      mLastEventCount += count;
      mLastEventPosition = position;
      return;
    }
    dispatchLastEvent();
    mLastEventPosition = position;
    mLastEventCount = count;
    mLastEventType = TYPE_REMOVE;
  }

  void onMoved(int fromPosition, int toPosition) {
    dispatchLastEvent(); // moves are not merged
    mWrapped.onMoved(fromPosition, toPosition);
  }

  void onChanged(int position, int count, Object payload) {
    if (mLastEventType == TYPE_CHANGE &&
        !(position > mLastEventPosition + mLastEventCount ||
            position + count < mLastEventPosition ||
            mLastEventPayload != payload)) {
      // take potential overlap into account
      final int previousEnd = mLastEventPosition + mLastEventCount;
      mLastEventPosition = math.min(position, mLastEventPosition);
      mLastEventCount =
          math.max(previousEnd, position + count) - mLastEventPosition;
      return;
    }
    dispatchLastEvent();
    mLastEventPosition = position;
    mLastEventCount = count;
    mLastEventPayload = payload;
    mLastEventType = TYPE_CHANGE;
  }
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
DiffResult calculateDiff(DiffDelegate cb, {bool detectMoves = true}) {
  final int oldSize = cb.getOldListSize();
  final int newSize = cb.getNewListSize();
  final List<_Snake> snakes = [];
  // instead of a recursive implementation, we keep our own stack to avoid potential stack
  // overflow exceptions
  final List<_Range> stack = [];
  stack.add(_Range(
      oldListStart: 0,
      oldListEnd: oldSize,
      newListStart: 0,
      newListEnd: newSize));
  final int max = oldSize + newSize + (oldSize - newSize).abs();
  // allocate forward and backward k-lines. K lines are diagonal lines in the matrix. (see the
  // paper for details)
  // These arrays lines keep the max reachable position for each k-line.
  final List<int> forward = Int32List(max * 2);
  final List<int> backward = Int32List(max * 2);
  // We pool the ranges to avoid allocations for each recursive call.
  final List<_Range> rangePool = [];
  while (stack.isNotEmpty) {
    final _Range range = stack.removeLast();
    final _Snake snake = _diffPartial(cb, range.oldListStart, range.oldListEnd,
        range.newListStart, range.newListEnd, forward, backward, max);
    if (snake != null) {
      if (snake.size > 0) {
        snakes.add(snake);
      }
      // offset the snake to convert its coordinates from the Range's area to global
      snake.x += range.oldListStart;
      snake.y += range.newListStart;
      // add new ranges for left and right
      final _Range left = rangePool.isEmpty ? _Range() : rangePool.removeLast();
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
      final _Range right = range;
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

_Snake _diffPartial(DiffDelegate cb, int startOld, int endOld, int startNew,
    int endNew, List<int> forward, List<int> backward, int kOffset) {
  final int oldSize = endOld - startOld;
  final int newSize = endNew - startNew;
  if (endOld - startOld < 1 || endNew - startNew < 1) {
    return null;
  }
  final int delta = oldSize - newSize;
  final int dLimit = (oldSize + newSize + 1) ~/ 2;
  forward.fillRange(kOffset - dLimit - 1, kOffset + dLimit + 1, 0);
  // Arrays.fill(forward, kOffset - dLimit - 1, kOffset + dLimit + 1, 0);
  backward.fillRange(
      kOffset - dLimit - 1 + delta, kOffset + dLimit + 1 + delta, oldSize);
  final bool checkInFwd = delta % 2 != 0;
  for (int d = 0; d <= dLimit; d++) {
    for (int k = -d; k <= d; k += 2) {
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
      int y = x - k;
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
          final _Snake outSnake = _Snake();
          outSnake.x = backward[kOffset + k];
          outSnake.y = outSnake.x - k;
          outSnake.size = forward[kOffset + k] - backward[kOffset + k];
          outSnake.removal = removal;
          outSnake.reverse = false;
          return outSnake;
        }
      }
    }
    for (int k = -d; k <= d; k += 2) {
// find reverse path at k + delta, in reverse
      final int backwardK = k + delta;
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
      int y = x - backwardK;
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
          final outSnake = _Snake();
          outSnake.x = backward[kOffset + backwardK];
          outSnake.y = outSnake.x - backwardK;
          outSnake.size =
              forward[kOffset + backwardK] - backward[kOffset + backwardK];
          outSnake.removal = removal;
          outSnake.reverse = true;
          return outSnake;
        }
      }
    }
  }
  throw StateError("DiffUtil hit an unexpected case while trying to calculate" +
      " the optimal path. Please make sure your data is not changing during the" +
      " diff calculation.");
}

/// calculate the difference between the two given lists.
///
/// @param oldList the old list
/// @param newList the new list
/// @param detectMoves wheter move detection should be enabled
/// @param equalityChecker use this if you don't want to use the equality as defined by the == operator
DiffResult calculateListDiff<T>(List<T> oldList, List<T> newList,
    {bool detectMoves = true, bool Function(T,T) equalityChecker}) {
  return calculateDiff(ListDiffDelegate(oldList, newList, equalityChecker),
      detectMoves: detectMoves);
}
