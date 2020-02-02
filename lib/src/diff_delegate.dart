
abstract class DiffDelegate {
  ///
  ///Returns the size of the old list.
  ///

  ///@return The size of the old list.
  ///
  int getOldListSize();

  ///
  ///Returns the size of the new list.
  ///
  ///@return The size of the new list.
  ///
  int getNewListSize();

  ///
  ///Called by the DiffUtil to decide whether two object represent the same Item.
  ///<p>
  ///For example, if your items have unique ids, this method should check their id equality.
  ///
  ///@param oldItemPosition The position of the item in the old list
  ///@param newItemPosition The position of the item in the new list
  ///@return True if the two items represent the same object or false if they are different.
  ///
  bool areItemsTheSame(int oldItemPosition, int newItemPosition);

  ///
  ///Called by the DiffUtil when it wants to check whether two items have the same data.
  ///DiffUtil uses this information to detect if the contents of an item has changed.
  ///<p>
  ///DiffUtil uses this method to check equality instead of ==
  ///so that you can change its behavior depending on your UI.
  ///This method is called only if areItemsTheSame returns
  ///true for these items.
  ///
  ///@param oldItemPosition The position of the item in the old list
  ///@param newItemPosition The position of the item in the new list which replaces the
  ///oldItem
  ///@return True if the contents of the items are the same or false if they are different.
  ///
  bool areContentsTheSame(int oldItemPosition, int newItemPosition);

  ///
  ///When areItemsTheSame(int, int) returns true for two items and
  ///areContentsTheSame(int, int) returns false for them, DiffUtil
  ///calls this method to get a payload about the change.
  ///<p>
  ///Default implementation returns {@code null}.
  ///
  ///@param oldItemPosition The position of the item in the old list
  ///@param newItemPosition The position of the item in the new list
  ///
  ///@return A payload object that represents the change between the two items.
  ///

  Object getChangePayload(int oldItemPosition, int newItemPosition) {
    return null;
  }
}


class ListDiffDelegate<T> implements DiffDelegate {
  final List<T> oldList;
  final List<T> newList;
  final bool Function(T, T) equalityChecker;

  ListDiffDelegate(this.oldList, this.newList,
      [bool Function(T, T) equalityChecker])
      : equalityChecker = equalityChecker ?? ((a, b) => a == b);

  @override
  bool areContentsTheSame(int oldItemPosition, int newItemPosition) {
    return true;
  }

  @override
  bool areItemsTheSame(int oldItemPosition, int newItemPosition) {
    return equalityChecker(oldList[oldItemPosition], newList[newItemPosition]);
  }

  @override
  Object getChangePayload(int oldItemPosition, int newItemPosition) {
    return null;
  }

  @override
  int getNewListSize() => newList.length;

  @override
  int getOldListSize() => oldList.length;
}