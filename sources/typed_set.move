// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// `typed_set` — one bounded set of `T` per key type, stored as a dynamic field
/// on any object's `UID`.
///
/// A protocol-agnostic primitive in the spirit of `platform_link`: it knows
/// nothing about parties or any other consumer object. A consumer package
/// defines a unit key type (`TagsKey`, `GenresKey`, …) and gets a `VecSet<T>`
/// under that key with the mechanics every small set extension needs —
/// init-on-add, duplicate and capacity checks, removal that reclaims the field
/// once the set empties, and a no-op clear. What may *enter* the set (length
/// limits, vocabulary proofs) and which events a change announces stay with the
/// consumer: it validates before calling `add` and emits after.
///
/// The set lives under the consumer's own key type, so two consumers never
/// collide on the same `UID`, and a stored set is exactly a `VecSet<T>` — no
/// wrapper struct to migrate if the consumer evolves.
module typed_set::typed_set;

use sui::dynamic_field as df;
use sui::vec_set::{Self, VecSet};

// === Errors ===

/// The item is already in the set.
const EDuplicateItem: u64 = 0;
/// The item is not in the set (or there is no set).
const EItemNotPresent: u64 = 1;
/// Adding this item would exceed `max`.
const EMaxItemsExceeded: u64 = 2;

// === Write ===

/// Adds `item` to the set under `key`, creating the set on first use. Aborts if
/// the item is already present or the set has reached `max`.
public fun add<K: copy + drop + store, T: copy + drop + store>(
    uid: &mut UID,
    key: K,
    item: T,
    max: u64,
) {
    if (!df::exists(uid, copy key)) {
        df::add(uid, copy key, vec_set::empty<T>());
    };
    let items = borrow_mut<K, T>(uid, key);
    // Deliberately redundant with `vec_set::insert`'s own `EKeyAlreadyExists`
    // check below. Both are code 0, so what this pins is the *location*: the
    // abort is attributed to `typed_set::typed_set` rather than `0x2::vec_set`,
    // which is what every consumer's `location = typed_set::typed_set` test
    // assertion matches on.
    assert!(!items.contains(&item), EDuplicateItem);
    assert!(items.length() < max, EMaxItemsExceeded);
    items.insert(item);
}

/// Removes `item` from the set under `key`. Aborts if the set or the item is
/// absent. Drops the whole field once the last item leaves: an empty set is
/// indistinguishable from none, and the storage rebate goes back to the payer.
public fun remove<K: copy + drop + store, T: copy + drop + store>(
    uid: &mut UID,
    key: K,
    item: T,
) {
    assert!(df::exists(uid, copy key), EItemNotPresent);
    let empty = {
        let items = borrow_mut<K, T>(uid, copy key);
        assert!(items.contains(&item), EItemNotPresent);
        items.remove(&item);
        items.is_empty()
    };
    if (empty) {
        let _: VecSet<T> = df::remove(uid, key);
    };
}

/// Removes the set under `key`, discarding it. No-op if absent.
public fun clear<K: copy + drop + store, T: copy + drop + store>(uid: &mut UID, key: K) {
    if (df::exists(uid, copy key)) {
        let _: VecSet<T> = df::remove(uid, key);
    };
}

// === Views ===

/// Whether a set is stored under `key`. Never true for an empty set — `remove`
/// drops the field when the last item leaves.
public fun exists<K: copy + drop + store>(uid: &UID, key: K): bool {
    df::exists(uid, key)
}

/// Whether `item` is in the set under `key`.
public fun contains<K: copy + drop + store, T: copy + drop + store>(
    uid: &UID,
    key: K,
    item: &T,
): bool {
    if (!df::exists(uid, copy key)) return false;
    borrow<K, T>(uid, key).contains(item)
}

/// The items in the set under `key`, in insertion order (empty if absent).
public fun keys<K: copy + drop + store, T: copy + drop + store>(uid: &UID, key: K): vector<T> {
    if (!df::exists(uid, copy key)) return vector[];
    *borrow<K, T>(uid, key).keys()
}

// === Private ===

fun borrow<K: copy + drop + store, T: copy + drop + store>(uid: &UID, key: K): &VecSet<T> {
    df::borrow(uid, key)
}

fun borrow_mut<K: copy + drop + store, T: copy + drop + store>(
    uid: &mut UID,
    key: K,
): &mut VecSet<T> {
    df::borrow_mut(uid, key)
}
