# Internals Guide

This document describes the implementation of the RebSM Storage Manager.

## Table object

The RebSM table object is fairly simple.

	>> test: db-make [integer! string! date!]
	== make object! [
		types: [integer! string! date!]
		key-cols: 1
		idx-size: 2
		bytes-free: 0
		idx: #{}
		dat: #{}
	]

Property   | Datatype!           | Explanation
---------- | ------------------- | ------------------------------------------------------------------
types      | block! of datatype! | Column datatypes.
key-cols   | integer!            | Number of columns in the key (0 or more, defaults to 1).
idx-size   | integer!            | Number of bytes in each index entry (1 to 4 bytes, defaults to 2).
bytes-free | integer!            | Reclaimable space from remove and change operations.
idx        | binary!             | Index of row offsets.
dat        | binary!             | Table row data.

The `idx-size` determines the maximum offset that may be stored (effectively the maximum file size in bytes) as follows:

Value | Bytes         | Size
:---: | ------------: | --------:
1     |           256 | 256 bytes
2     |        65,535 |     64 KB
3     |    16,777,215 |     16 MB
4     | 4,294,967,295 |      4 GB

## Binary structures

### Index

The index is a binary! with each `idx-size` bytes (default 2) representing on offset into the data `binary!` (i.e. start of row). The index is sorted by / with a number of columns (left to right) equal to the `key-cols` value (1 if `key-cols` is zero).

Appends and changes that break this order set a reindex flag which `lookup` and `seek` check prior to searching the index `binary!` using a binary search.

A `lookup` (where number of values = `key-cols`) attempts to return a single row while `seek` (where number of values <> `key-cols`) uses `lookup` to return a range of values and then does a linear match on each row.

After appending our rows:

	>> db-append test [1 "Bob Brown" 12-Feb-1973]
	>> db-append test [2 "John Citizen" 3-Mar-1982]
	>> db-append test [3 "Jane Doe" 28-Nov-1978]

we end up with an index like so:

	#{000000110025}

The `idx-size` is **2** bytes so this index contains three offsets into the dat file as follows:

	#{0000} ; 0
	#{0011} ; 17
	#{0025} ; 37

### Data

The structure of the first record is:

	#{010109426F622042726F776E0407B5020C}

		#{01}                 ; Bytes (1)
		#{01}                 ; Value (1)
		#{09}                 ; Bytes (9)
		#{426F622042726F776E} ; Value ("Bob Brown")
		#{04}                 ; Bytes (4)
		#{07B5020C}           ; Value (12-Feb-1973)
			#{07B5}           ; 1973
			#{02}             ; 2
			#{0C}             ; 12

## Value encoding

Rebol values are binary encoded according to the following rules:

1. `none!`, `zero?` (apart from `tuple!`) or `empty?` values are encoded with a byte size of `#{00}`.
2. `scalar!` values have all leading `#{00}` bytes removed.
3. `series!` values are encoded one byte per character.
4. `date!` values are encoded as year (2 bytes), month (1 byte) and day (1 byte).
5. Other datatypes are encoded in as few bytes as possible.

All encoded values have a byte length indicator (1 byte) preceding them.

!note All Rebol values are encoded and decoded without loss of information.

## Search methods

The `db-remove`, `db-select` and `db-change` functions can all be passed values or conditions to retrieve rows in one of three ways.

### Lookup

	db-select animals [] ["Dog" "Siberian Husky"]

A lookup is undertaken when the number of search values matches the table `key-cols` value. A lookup is a [binary search](http://en.wikipedia.org/wiki/Binary_search_algorithm) that will either retrieve the matching unique row or not. It is very fast.

### Seek

	db-select animals [] ["Dog"]

A seek is undertaken when the number of values provided is less than `key-cols`, or `key-cols` is 0. Seek will use a binary search to provide a range of rows to scan, then perform a linear scan. A seek will return zero or more rows and is typically only slightly slower than a lookup.

### Fetch

	db-select animals [] [find ["Dog" "Cat"] c1]

A fetch is undertaken when conditions are provided. A linear scan is performed against each row. This is a very slow operation as each search column must be retrieved and decoded into a Rebol value.

## Table fragmentation

### Row deletion

When `db-remove` removes a row it does so by removing the row's offset entry from the table's index and incrementing the table's `bytes-free` count by the number of bytes 'orphaned'.

### Row change

When `db-change` changes a row it compares the size of the new row against that of the old ... if it's less than or equal then the new row overwrites the old (potentially leaving a "hole" if the old row was larger), otherwise the new row is appended and the index offset reset (which will orphan the old row as above).

### Compact

The `db-compact` function defragments a table by serially reading the data binary and rebuilding both it and the index binary from scratch. This may take a long time for a large number of values.

## Index sort

By default the index binary is sorted by its key columns (minimum 1). Whenever an `append` or `remove` occurs that would disrupt the sort order (e.g. by appending a small value or changing a key column) a flag is set to trigger an index sort the next time a lookup or seek is performed.