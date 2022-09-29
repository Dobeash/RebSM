# Rebol Storage Manager

RebSM is a small but highly efficient storage manager with a SQL-like interface.

## Features

- **Works out of the box** - Just add `do %rebsm.r` to your script and you are ready to go. No marathon installation / configuration / tuning sessions required!
- **Native Rebol storage** - Your data is stored and accessed as Rebol values which means that you have the full range of Rebol data-types at your fingertips!
- **Plays well** - The 10 functions that drive the database behave like any other Rebol function, accepting and returning Rebol values as you would expect.
- **Lean and mean** - The entire script weighs in at about 20Kb of highly optimized and tuned R2 / R3 syntax. It can blaze through millions of rows a second!

## Quick Start

From a Rebol console:

	do http://www.dobeash.com/RebSM/rebsm.r
	help db-
	test: db-load http://www.dobeash.com/RebSM/test.bin
	help test
	db-select test [] [1]
	db-select test [] [all [c1 = 1 odd? c2]]

## Documentation

> Updated 3-Jan-2014

- **DESIGN.md** describes the design of the Storage Manager.
- **INTERNALS.md*** describes the implementation of the Storage Manager.
- **OPERATION.md** describes the operation of the Storage Manager.