extends Node

## Caches the list o items that have been "visited" (i.e., short text visualized)
## Acts as a set.
## Key=item_id: int, Value=always true: bool
var _visited_items: Dictionary[int, bool] = {}


## Insert the specified item in the set of visited items
func mark_as_visited(item_id: int):
    _visited_items[item_id] = true

    # DEBUG - print the listof all visited items
    print("Visited items: ", _visited_items.keys())


## Returns true if all of the items in the provided list are in the cache of visited items
func have_been_visited(ids: Array[int]) -> bool:
    for id in ids:
        if not _visited_items.has(id):
            return false
    return true
