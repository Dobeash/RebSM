# Operation Guide

This document describes the operation of the RebSM Storage Manager.

## Supported Datatypes

RebSM supports the following Rebol datatypes:

- binary!
- block!
- char!
- datatype!
- date!
- decimal!
- email!
- file!
- integer!
- issue!
- logic!
- money!
- pair!
- percent!
- string!
- tag!
- time!
- tuple!
- url!
- word!

Note that `percent!` is mapped to `decimal!` in R2.

## Commands

### DB-TRACE?

	USAGE:
		DB-TRACE?: flag

	DESCRIPTION:
		Turns statement tracing on or off.
		DB-TRACE? is a word value.

	ARGUMENTS:
		flag (logic! file!)

	EXAMPLES:
		db-trace?: on                                   ; turn trace on (print to console)
		db-trace?: %trace.txt                           ; turn trace on (append to file)
		db-trace?: off                                  ; turn trace off

### DB-APPEND

	USAGE:
		DB-APPEND table values /nocheck

	DESCRIPTION:
		Appends a row of values to a table (returns row count).
		DB-APPEND is a function value.

	ARGUMENTS:
		table (object!)
		values (block!)
		
	REFINEMENTS:
		/nocheck -- Skip values checking

	EXAMPLES:
		db-append test [4 "Bob" 1-Jan-2010]             ; append a new row
		db-append/nocheck test [5 "Bob" 1-Jan-2010]     ; append a new row quickly (about 8x faster)
		db-append test [next "Bob" 1-Jan-2010]          ; append a new row with 1st column set to max + 1

The `next` keyword can be used in place of a `key-cols` value (first value only if `key-cols` is zero). It is substituted for the value of the last row plus one (in the same column position). For example:

	>> test: db-make/keys [integer! integer!] 2
	>> db-append test [10 next]
	>> db-select test [] []     
	== [10 0]
	>> db-append test [next next]
	>> db-select test [] []       
	== [10 0 11 1]

### DB-CHANGE

	USAGE:
		DB-CHANGE table columns values

	DESCRIPTION:
		Changes row values in a table (returns rows changed).
		DB-CHANGE is a function value.

	ARGUMENTS:
		table (object!)
		columns -- Column (integer!) value (any-type!) pairs (block!)
		values -- Key value(s) or conditions (block!)

	EXAMPLES:
		db-change test [1 0] []                         ; set all 1st column values to 0
		db-change test [1 0 2 "Test"] []                ; set 2 columns at once
		db-change test [1 0 2 "Test"] [1]               ; add a key condition
		db-change test [1 0 2 "Test"] [even? c1]        ; add a query condition

### DB-COMPACT

	USAGE:
		DB-COMPACT table

	DESCRIPTION:
		Reclaims fragmented space in a table (returns bytes compacted).
		DB-COMPACT is a function value.

	ARGUMENTS:
		table (object!)

	EXAMPLES:
		db-compact test                                 ; compact table

### DB-IMPORT

	USAGE:
		DB-IMPORT table block /nocoerce

	DESCRIPTION:
		Imports rows of values into a table (returns row import count).
		DB-IMPORT is a function value.

	ARGUMENTS:
		table (object!)
		block (block!)

	REFINEMENTS:
		/nocoerce -- Don't coerce values

### DB-LOAD

	USAGE:
		DB-LOAD source

	DESCRIPTION:
		Loads a table object.
		DB-LOAD is a function value.

	ARGUMENTS:
		source (port! file! url!)

	EXAMPLES:
		test: db-load %test.bin                         ; load table from file
		test: db-load http://www.site.com/test.bin      ; load table from URL

### DB-MAKE

	USAGE:
		DB-MAKE spec /index bytes /keys columns

	DESCRIPTION:
		Makes a table object.
		DB-MAKE is a function value.

	ARGUMENTS:
		spec -- Datatype!s (block!)

	REFINEMENTS:
		/index
			bytes -- Index width in bytes (integer!)
		/keys
			columns -- Number of columns in key (integer!)

	EXAMPLES:
		test: db-make [integer! string! date!]          ; make table with three columns

It's generally a bad idea to have negative and / or decimal values in a key column. This is due to their `binary!` representation (and hence sort order).

### DB-REMOVE

	USAGE:
		DB-REMOVE table values

	DESCRIPTION:
		Removes rows from a table (returns rows removed).
		DB-REMOVE is a function value.

	ARGUMENTS:
		table (object!)
		values -- Key value(s) or conditions (block!)

	EXAMPLES:
		db-remove test []                               ; removes all rows
		db-remove test [1]                              ; remove rows with a 1st column value of 1
		db-remove test [odd? c1]                        ; remove rows with an odd 1st column value

### DB-SAVE

	USAGE:
		DB-SAVE where 'table

	DESCRIPTION:
		Saves a table object.
		DB-SAVE is a function value.

	ARGUMENTS:
		where (port! file! url!)
		table (word!)

	EXAMPLES:
		db-save %test.bin test                          ; save table to file
		db-save http://www.site.com/test.bin test       ; save table to URL

### DB-SELECT

	USAGE:
		DB-SELECT table columns values

	DESCRIPTION:
		Returns columns and rows from a table.
		DB-SELECT is a function value.

	ARGUMENTS:
		table (object!)
		columns -- Column numbers (block!)
		values -- Key value(s) or conditions (block!)

	EXAMPLES:
		db-select test [] []                            ; select all columns and rows from table
		db-select test [1 2] []                         ; select 1st and 2nd columns from table
		db-select test [] [1]                           ; select rows with a 1st column value of 1
		db-select test [] [8 = length? c2]              ; select rows with a 2nd column length of 8

## Performance tuning

### Storage

Minimize memory use by:

- Having as few columns and rows as possible.
- Minimizing the number of `decimal!`, `percent!` and negative `integer!` values stored (as each takes 8 bytes).
- Trimming strings prior to appending where possible.
- Performing as few row deletions as possible (unless they occur at the *end* of the table).
- Avoiding changes that increase row length.
- Using the `/nocheck` refinement of `db-append` when importing data.
- Using the `/nocoerce` refinement of `db-import` when bulk importing data.

### Search Performance

For best performance:

- Always make tables with a primary key, preferably of one column.
- Use equality searches where possible (i.e. by providing values).
- If a fetch (Rebol condition) is required, reference as few columns as possible.

### Minimizing thrashing

Thrashing occurs when you alternate between operations that *unsort* the index and those that sort it. A small example:

	>> test: db-make/index/keys [integer!] 3 0
	>> repeat i 50000 [loop 20 [db-append/nocheck test reduce [i]]]
	>> db-trace?: on
	>> db-select test [] [1]
	Lookup ... 0:00:00.000288 seconds 16 rows
	Seek ..... 0:00:00.000204 seconds 21 rows
	Select ... 0:00:00.000327 seconds 20 rows
	>> db-append test [0]
	Append ... 0:00:00.000144 seconds 1 rows
	>> db-select test [] [1]
	Sort ..... 0:00:05.779172 seconds 1000001 rows
	Lookup ... 0:00:00.000177 seconds 16 rows
	Seek ..... 0:00:00.000145 seconds 22 rows
	Select ... 0:00:00.000245 seconds 20 rows

### Minimizing fragmentation

You can *peg* a change to a particular offset by using a pseudo-fixed column as follows:

	products: db-make [integer! string! string!]
	db-append products [1 "00AR1" "Description 1"]
	db-append products [2 "00AR2" "Description 2"]
	db-change products [2 "0AR10"] [1]
	db-change products [2 "AR100"] [1]

This will ensure the field / row does not change size when changed. Now try the following to see what happens when you don't do this:

	>> products/bytes-free
	== 0
	>> db-change products [2 ""] [1]  ; we lose 5 bytes due to row shrinkage
	== 1
	>> products/bytes-free       
	== 5
	>> db-change products [2 "x"] [1] ; we lose another 17 bytes as the row is orphaned
	== 1
	>> products/bytes-free
	== 22