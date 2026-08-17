# typed_set

One bounded set of `T` per key type, stored as a dynamic field on any
object's `UID`. A protocol-agnostic primitive in the spirit of
`platform_link`: it knows nothing about parties or any other consumer, so
anything in the ecosystem can depend on it. A consumer package defines a
unit key type (`TagsKey`, `GenresKey`, …) and gets the mechanics every
small set extension needs — init-on-add, duplicate and capacity checks,
removal that reclaims the field once the set empties, and a no-op clear.

What may *enter* the set (length limits, vocabulary proofs) and which
events a change announces stay with the consumer: it validates before
calling `add` and emits after.

## What it stores

- Key: the consumer's own key type `K` (`copy + drop + store`), passed by
  value — one set per key type per `UID`, so two consumers never collide
  on the same object.
- Value: a bare `VecSet<T>` (`T: copy + drop + store`) — no wrapper
  struct, so a stored set is exactly a `VecSet<T>` and there is nothing to
  migrate if the consumer evolves.
- Capacity is not stored: `max` is an argument to `add`, checked on every
  insert, so the set holds at most `max` items under the consumer's
  current policy.
- Reclamation: `remove` drops the whole dynamic field when the last item
  leaves — an empty set is indistinguishable from none, and the storage
  rebate goes back to the payer. `exists` is never true for an empty set.

## API

All functions take the host object's `UID` directly; authorization is the
consumer's concern (the `party_*` extensions gate with `PartyAdminCap`
through `party::uid_mut(cap)`).

### Writes

| Function | Description | Aborts |
|---|---|---|
| `add<K, T>(&mut uid, key, item, max)` | Add `item`, creating the set on first use | `EDuplicateItem` (0) if already present; `EMaxItemsExceeded` (2) when the set already holds `max` items |
| `remove<K, T>(&mut uid, key, item)` | Remove `item`; drops the field once the set empties | `EItemNotPresent` (1) when the set or the item is absent |
| `clear<K, T>(&mut uid, key)` | Remove the whole set | — (no-op when absent) |

### Views

| Function | Returns |
|---|---|
| `exists<K>(&uid, key)` | Whether a set is stored — never true for an empty set |
| `contains<K, T>(&uid, key, &item)` | Whether `item` is in the set |
| `keys<K, T>(&uid, key)` | The items in insertion order (empty vector when absent) |

## Events

None — this primitive is storage only. Consumers emit their own typed
events after the mutation (`party_genre` emits `GenreAddedEvent` /
`GenreRemovedEvent` / `GenresClearedEvent`).

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EDuplicateItem` | `add` with an item already in the set |
| 1 | `EItemNotPresent` | `remove` with no set stored, or the item absent |
| 2 | `EMaxItemsExceeded` | `add` when the set already holds `max` items |

These abort at `location = typed_set::typed_set`; consumers do not
re-declare them.

## Dependencies

None beyond the Sui framework (`sui::dynamic_field`, `sui::vec_set`) —
`Move.toml` declares no `[dependencies]` section.

## Integrator notes

- The consumer recipe: define a unit key type (`copy + drop + store`),
  validate what may enter the set (length limits, vocabulary proofs)
  *before* calling `add`, pass your capacity constant as `max` on every
  `add`, and emit your own typed events *after* the mutation. Gate writes
  yourself — the extensions take `&PartyAdminCap` and go through
  `party::uid_mut(cap)` before touching the set.
- Key types are namespaced by the defining package, so consumers never
  collide on the same `UID`. `VecSet` preserves insertion order, so
  `keys` is a stable display order.
- `max` is per-call, not stored: raising or lowering a capacity needs no
  migration, and items already in the set are unaffected.
- Built on it: `party_genre`, `party_roles`, `party_tags`. Their tests
  assert these abort codes at `location = typed_set::typed_set`, and
  their READMEs list them as primitive-sourced rather than local errors.
