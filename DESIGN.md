# Design Guide
This document describes the design of the RebSM Storage Manager.

## Introduction

RebSM began as a rewrite of RebDB and had several design goals:

- Traditional Record & Field model.
- Support for most Rebol datatypes.
- RAM-based, but using memory as efficiently as possible.
- Typed columns with support for zero length values.
- No arbitrary limits on table structure.

Unlike RebDB, which partially implemented a [relational model](http://en.wikipedia.org/wiki/Relational_model), this version is more akin to what RIF promised to be ... a storage model for records and fields. The intent is that developers can use RebSM to implement other data models (such as the [key-value model](https://en.wikipedia.org/wiki/Key-value_database) for example).

The reasons for choosing a record and field model were:

- It is easily understood by both developers and users.
- Other data models are often implemented using simple table structures.
- Rebol has many refinements (e.g. `/skip`) that specifically support a record structure.

Having decided upon a record and field structure, I now had to consider how best to represent this.

## Rebol block values

RebDB simply used Rebol's versatile `block!` structure to represent tables.

	[
	    1 "Bob Brown" 12-Feb-1973
	    2 "John Citizen" 3-Mar-1982
	    3 "Jane Doe" 28-Nov-1978
	]

This has the advantage of being fast as there is no conversion to / from other values, but it is memory intensive. In addition to the space required to store each value, each value requires an extra 16 bytes or so to track `datatype!` and `context!` information. This isn't a problem for large `series!` but is not very efficient for `scalar!` values.

## Delimited fields

Another approach, favoured by spreadsheet programs and UNIX text files, is to delimit fields with a special character and have each record appear on a separate line.

	1,"Bob Brown",12-Feb-1973
	2,"John Citizen",3-Mar-1982
	3,"Jane Doe",28-Nov-1978

Typically this data would be loaded into a Rebol `string!` or `binary!` and accessed via a parse of some description. Whilst this is certainly more memory efficient than Rebol blocks, the overhead of dynamically managing delimiters is rather large.

## Fixed width fields

Fixed width fields are easy to implement and understand.

	001Bob Brown   12-Feb-1973
	002John Citizen03-Mar-1982
	003Jane Doe    28-Nov-1978

They work well when the data is not sparse (i.e. lots of null values) and there is not significant variation in record sizes.

## Variable width fields

A variable width structure seeks to overcome the limitations of delimited and fixed width structures by using a length delimiter.

	1:19:Bob Brown11:12-Feb-1973
	1:212:John Citizen10:3-Mar-1982
	1:38:Jane Doe11:28-Nov-1978

This approach is faster than delimiters (as the field lengths are encoded allowing easy traversal of records) and avoids the potential space wastage of fixed structures. RebSM uses an enhanced version of variable width fields.
