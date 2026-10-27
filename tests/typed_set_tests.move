// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module typed_set::typed_set_tests;

use std::unit_test::assert_eq;
// Aliased so the bare `typed_set` name stays free for `location = …` below.
use typed_set::typed_set as set;

/// A stand-in key for exercising the generic storage.
public struct FooKey() has copy, drop, store;

#[test]
fun add_contains_keys_remove_clear() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);

    assert!(!set::exists<FooKey>(&uid, FooKey()));
    assert!(set::keys<FooKey, u64>(&uid, FooKey()).is_empty());
    assert!(!set::contains<FooKey, u64>(&uid, FooKey(), &1));

    set::add(&mut uid, FooKey(), 1u64, 3);
    set::add(&mut uid, FooKey(), 2u64, 3);
    assert!(set::exists<FooKey>(&uid, FooKey()));
    assert!(set::contains<FooKey, u64>(&uid, FooKey(), &1));
    assert!(!set::contains<FooKey, u64>(&uid, FooKey(), &9));
    // Insertion order is preserved.
    assert_eq!(set::keys<FooKey, u64>(&uid, FooKey()), vector[1, 2]);

    set::remove(&mut uid, FooKey(), 1u64);
    assert!(!set::contains<FooKey, u64>(&uid, FooKey(), &1));
    assert_eq!(set::keys<FooKey, u64>(&uid, FooKey()).length(), 1);

    set::clear<FooKey, u64>(&mut uid, FooKey());
    assert!(!set::exists<FooKey>(&uid, FooKey()));
    set::clear<FooKey, u64>(&mut uid, FooKey()); // absent — no-op

    uid.delete();
}

#[test]
fun remove_drops_the_field_when_emptied() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);

    set::add(&mut uid, FooKey(), 1u64, 3);
    set::remove(&mut uid, FooKey(), 1u64);
    // The last removal reclaims the field: no empty set lingers.
    assert!(!set::exists<FooKey>(&uid, FooKey()));

    uid.delete();
}

#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)] // EDuplicateItem
fun add_duplicate_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    set::add(&mut uid, FooKey(), 1u64, 3);
    set::add(&mut uid, FooKey(), 1u64, 3);
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_absent_item_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    set::add(&mut uid, FooKey(), 1u64, 3);
    set::remove(&mut uid, FooKey(), 2u64);
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_without_set_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    set::remove(&mut uid, FooKey(), 1u64);
    abort
}

#[test, expected_failure(abort_code = 2, location = typed_set::typed_set)] // EMaxItemsExceeded
fun add_over_max_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    3u64.do!(|i| set::add(&mut uid, FooKey(), i, 3));
    set::add(&mut uid, FooKey(), 3u64, 3); // the 4th trips max = 3
    abort
}
