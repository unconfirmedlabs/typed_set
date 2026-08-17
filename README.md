# typed_set

One bounded set of `T` per key type, stored as a dynamic field on any object's `UID`.

You define a key type. `typed_set` does the rest: creates the set on the first
`add`, rejects duplicates, enforces a cap, and deletes the field when the last
item leaves. It knows nothing about parties, music, or whatever your package
does, and it depends on nothing but the Sui framework, so anything in the
ecosystem can build on it.

## Using it

Add the dependency:

```toml
[dependencies]
typed_set = { git = "https://github.com/unconfirmedlabs/typed_set.git" }
```

Then define a key and wrap the calls in whatever rules your package needs:

```move
module my_package::host_tags;

use std::string::String;
use sui::event;
use typed_set::typed_set;

const MAX_TAGS: u64 = 16;
const ETagTooLong: u64 = 0;

/// The key. Namespaced by this package, so nobody else writes to this set.
public struct TagsKey() has copy, drop, store;

public struct TagAdded has copy, drop { host: ID, tag: String }

public fun add_tag(host: &mut Host, tag: String) {
    assert!(tag.length() <= 32, ETagTooLong);                 // validate first
    typed_set::add(&mut host.id, TagsKey(), tag, MAX_TAGS);
    event::emit(TagAdded { host: object::id(host), tag });    // announce after
}

public fun tags(host: &Host): vector<String> {
    typed_set::keys<TagsKey, String>(&host.id, TagsKey())
}
```

Vocabulary checks, length limits, and events stay in your module. This package
only stores things.

## What gets stored

Under your key sits a bare `VecSet<T>`. There is no wrapper struct, so if you
outgrow this package you can reach the field with `dynamic_field::borrow` and
nothing needs migrating.

Three things worth knowing:

**One set per key type per object.** Your key type carries your package address,
so two packages tagging the same object never collide.

**The cap is an argument, not state.** You pass `max` on every `add`. Change the
constant whenever you like; no migration, and items already in the set stay put.

**Empty means gone.** `remove` deletes the whole dynamic field when the last item
leaves, so the storage rebate returns to the payer and `exists` reports false. A
stored empty set cannot happen.

## API

Every function takes the host object's `UID` directly. Authorization is yours to
enforce before you call: the `party_*` extensions take a `&PartyAdminCap` and go
through `party::uid_mut(cap)`.

### Writes

| Function | Description | Aborts |
|---|---|---|
| `add<K, T>(&mut uid, key, item, max)` | Adds `item`, creating the set on first use | `EDuplicateItem` if `item` is already there, `EMaxItemsExceeded` if the set holds `max` items |
| `remove<K, T>(&mut uid, key, item)` | Removes `item`, dropping the field once the set empties | `EItemNotPresent` if the set or the item is missing |
| `clear<K, T>(&mut uid, key)` | Removes the whole set | Nothing. No-op when absent |

### Reads

| Function | Returns |
|---|---|
| `exists<K>(&uid, key)` | Whether a set is stored. False for an empty one, which cannot exist |
| `contains<K, T>(&uid, key, &item)` | Whether `item` is in the set |
| `keys<K, T>(&uid, key)` | The items in insertion order, or an empty vector when absent |

Keys are `copy + drop + store` and pass by value. Items are `copy + drop +
store` too.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EDuplicateItem` | `add` with an item already in the set |
| 1 | `EItemNotPresent` | `remove` with the item missing, or with no set at all |
| 2 | `EMaxItemsExceeded` | `add` when the set already holds `max` items |

Aborts carry `location = typed_set::typed_set`, so write your tests against this
package rather than re-declaring the constants in yours:

```move
#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)]
fun add_duplicate_aborts() { /* … */ }
```

## Events

None. Emit your own after the mutation, where you know what the change means.
`party_genre`, for one, emits `GenreAddedEvent`, `GenreRemovedEvent`, and
`GenresClearedEvent`.

## Dependencies

`sui::dynamic_field` and `sui::vec_set`. `Move.toml` declares no
`[dependencies]` section at all.

## Built on it

`party_genre`, `party_roles`, and `party_tags`.
