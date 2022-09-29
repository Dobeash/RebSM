REBOL [
	title:		"RebSM Storage Manager"
	version:	3.0.4
	date:		4-Jan-2014
	funcs: [
		db-append	;	Appends a row of values to a table (returns row count).
		db-change	;	Changes row values in a table (returns rows changed).
		db-compact	;	Reclaims fragmented space in a table (returns bytes compacted).
		db-import	;	Imports rows of values into a table (returns row import count).
		db-load		;	Load db file.
		db-make		;	Makes a new table object.
		db-remove	;	Removes rows from a table (returns rows removed).
		db-save		;	Save db file.
		db-select	;	Returns columns and rows from a table.
		db-trace?	;	Flag to turn debug on/off.
	]
	history: {
		3.0.0	3rd generation R3 specific release
		3.0.1	Performance improvements
		3.0.2	Renamed db-create to db-make
				Renamed db-delete to db-remove
				Renamed db-insert to db-append
				Renamed db-update to db-change
				Improved db-append and sort-idx speed and added /nocheck
				General bug fixes and performance improvements
		3.0.3	Replaced some repeat loops with forskip
		3.0.4	R2 port
				Removed sql
				Removed object! support
				Added db-import
				db-make now uses single byte field length indicators by default
	}
	license: {
		Copyright 2014 Dobeash Software

		Permission is hereby granted, free of charge, to any person obtaining
		a copy of this software and associated documentation files
		(the "Software"), to deal in the Software without restriction, including
		without limitation the rights to use, copy, modify, merge, publish,
		distribute, sublicense, and/or sell copies of the Software, and to
		permit persons to whom the Software is furnished to do so, subject
		to the following conditions:

		The above copyright notice and this permission notice shall be included
		in all copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
		OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
		FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
		THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
		OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
		ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
		OTHER DEALINGS IN THE SOFTWARE.
	}
]

;	----------------------------------------
;		R2/R3 binary translation handlers
;	----------------------------------------

context [
	either 8 = length? to binary! 0 [
		set 'db-load func ["Load db file." file [file! url!]][do load file]
		set 'db-save func ["Save db file." file [file! url!] table [object!]][write file mold/only/all table]
		int-to-bin: :to-binary
		trim-bin: func [v][v: to binary! v while [zero? first v][remove v] v]
		to-raw: func [type v /local x y][
			switch/default type reduce [
				binary!		[v]
				block!		[to binary! mold/flat v]
				datatype!	[to binary! head remove back tail form v]
				date!		[rejoin [skip to binary! v/year 6 back tail to binary! v/month back tail to binary! v/day]]
				decimal!	[trim-bin to integer! v * 100]
				integer!	[trim-bin v]
				issue!		[to binary! remove form v]
				logic!		[either v [#{01}][#{}]]
				money!		[trim-bin to integer! v * 100]
				pair!		[x: to binary! to integer! v/x y: to binary! to integer! v/y while [all [zero? first x zero? first y]][remove x remove y] head insert tail x y]
				percent!	[trim-bin to integer! v * 10000]
				time!		[trim-bin to integer! v]
				word!		[to binary! form v]
			] [to binary! v]
		]
		to-rebol: func [type v][
			switch/default type reduce [
				binary!		[v]
				block!		[load v]
				char!		[to char! v]
				datatype!	[to datatype! to word! join to string! v "!"]
				date!		[to date! reduce [last v pick v 3 to integer! copy/part v 2]]
				decimal!	[divide to integer! v 100]
				integer!	[to integer! v]
				logic!		[true]
				money!		[to money! divide to integer! v 100]
				pair!		[to pair! reduce [to integer! take/part v (length? v) / 2 to integer! v]]
				percent!	[to percent! divide to integer! v 10000]
				string!		[to string! v]
				tag!		[to tag! v]
				time!		[to time! to integer! v]
				tuple!		[to tuple! v]
			] [to type to string! v]
		]
	][
		set 'db-load func ["Load db file." file [file! url!]][load file]
		set 'db-save func ["Save db file." file [file! url!] table [object!]][save/all file table]
		int-to-bin: func [v][load make string! reduce ["#{" to-hex v "}"]]
		percent!: :decimal!
		to-raw: func [type v /local x y][
			switch/default type reduce [
				binary!		[v]
				block!		[to binary! mold/flat v]
				datatype!	[to binary! v]
				date!		[load make string! rejoin ["#{" skip to-hex v/year 4 skip to-hex v/month 6 skip to-hex v/day 6 "}"]]
				decimal!	[trim/head int-to-bin to integer! v * 100]
				integer!	[trim/head int-to-bin v]
				logic!		[either v [#{01}][#{}]]
				money!		[trim/head int-to-bin to integer! v/2 * 100]
				pair!		[x: int-to-bin v/x y: int-to-bin v/y while [all [zero? first x zero? first y]][remove x remove y] head insert tail x y]
				time!		[trim/head int-to-bin to integer! v]
			] [to binary! v]
		]
		to-rebol: func [type v][
			switch/default type reduce [
				binary!		[v]
				block!		[load as-string v]
				char!		[to char! to integer! v]
				datatype!	[to datatype! to word! join as-string v "!"]
				date!		[to date! reduce [last v pick v 3 to integer! copy/part v 2]]
				decimal!	[divide to integer! v 100]
				integer!	[to integer! v]
				logic!		[true]
				money!		[to money! divide to integer! v 100]
				pair!		[to pair! reduce [to integer! take/part v (length? v) / 2 to integer! v]]
				string!		[to string! v]
				tag!		[to tag! v]
				time!		[to time! to integer! v]
				tuple!		[to tuple! v]
			] [to type as-string v]
		]
	]

	;	----------------------------------------
	;		Shared words
	;	----------------------------------------

	set 'db-trace?	none				;	debug mode
	db-time:		none				;	used by db-print-trace
	db-idx-sort?:	none				;	sort required
	db-table:		none				;	current table object
	db-idx:			none				;	table index
	db-dat:			none				;	table data
	db-idx-size:	none				;	index width in bytes
	db-bin-size:	length? int-to-bin 0;	4/8 bytes for R2/R3
	db-skip:		db-bin-size - 1		;	?
	db-idx-skip:	none				;	db-bin-size - db-idx-size
	db-types:		none				;	column datatypes
	db-cols:		none				;	number of columns
	db-max-offset:	none				;	max byte offset into db-dat

	db-offsets:		make block! 1024	;	db-dat row offsets
	db-buffer:		make block! 4096	;	results buffer
	db-rowbuf:		make block! 32		;	raw values buffer
	db-keybuf:		make binary! 32		;	concatenated binary values
	db-columns:		make block! 32		;	column numbers
	db-predicate:	make block! 32		;	predicate words

	db-rows:		func [][divide length? db-idx db-idx-size]
	db-print-trace:	func [
		step [string!]
		stat [integer!]
		/local line s
	][
		line: reduce [
			copy/part make string! reduce [step " ....."] 10
			head insert/dup tail s: form now/time/precise - db-time " " 11 - length? s
			"seconds" stat "rows"
		]
		either file? db-trace? [write/append db-trace? head insert tail line newline] [print line]
		db-time: now/time/precise
	]

	;	----------------------------------------
	;		Init function
	;	----------------------------------------

	prepare: func [
		table [object!]
	][
		clear db-offsets
		clear db-buffer
		unless db-table = table [
			all [db-idx-sort? sort-idx]
			db-table:		table
			db-types:		table/types
			db-cols:		length? db-types
			db-idx:			table/idx
			db-dat:			table/dat
			db-idx-sort?:	none
			db-idx-skip:	db-bin-size - db-idx-size: table/idx-size
			db-max-offset:	power 2 db-idx-size * 8
			clear db-columns
			clear db-predicate
			repeat i db-cols [
				insert tail db-columns i
				insert tail db-predicate to word! make string! reduce ['c i]
			]
		]
		db-time: now/time/precise
	]

	;	----------------------------------------
	;		Conversion functions
	;	----------------------------------------

	to-raw-value: func [
		"Returns a binary! with leading length indicator."
		column [integer!]
		value [any-type!]
	][
		either any [
			none? value
			all [scalar? value zero? value not tuple? value]
			all [series? value empty? value]
		][#{00}][
			head insert value: to-raw pick db-types column value skip int-to-bin length? value db-skip
		]
	]

	get-raw-values: func [
		"Populates db-rowbuf with raw values of a row."
		offset [integer!]
		/local length
	][
		clear db-rowbuf
		loop db-cols [
			insert tail db-rowbuf copy/part skip db-dat offset length: 1 + first skip db-dat offset
			offset: offset + length
		]
	]

	get-raw-key-values: func [
		"Populates db-rowbuf with raw key value(s) of a row."
		offset [integer!]
		/local length
	][
		clear db-rowbuf
		loop max 1 db-table/key-cols [
			insert tail db-rowbuf copy/part skip db-dat offset length: 1 + first skip db-dat offset
			offset: offset + length
		]
	]

	to-rebol-value: func [
		"Converts raw value into REBOL value and prefixes with size byte(s)."
		column [integer!]
		/binary value
	][
		any [
			binary
			remove value: pick db-rowbuf column
		]
		either empty? value [
			switch pick db-types column reduce [
				binary!		[#{}]			; series	no conversion
				block!		[[]]			; series	1 byte per molded character
				char!		[#"^@"]			; scalar	1 byte
				datatype!	[none]			;			1 byte per formed character
				date!		[none]			;			4 bytes
				decimal!	[0.0]			; scalar	0 or 8 bytes
				email!		[none]			; series	1 byte per character
				file!		[none]			; series	1 byte per delimited character
				integer!	[0]				; scalar	0 to 8 bytes
				issue!		[#]				; series	1 byte per delimited character
				logic!		[false]			;			0 or 1 byte
				money!		[$0]			; scalar	0-8 bytes
				pair!		[0x0]			; scalar	0-16 byes
				percent!	[to percent! 0]	; scalar	0-8 bytes (R3 only)
				string!		[""]			; series	1 byte per character
				tag!		[none]			; series	1 byte per delimited character
				time!		[0:00]			; scalar	0-3 bytes
				tuple!		[none]			; scalar	1 byte per part
				url!		[none]			; series	1 byte per character
				word!		[none]			;			1 byte per character
			]
		][to-rebol pick db-types column value]
	]

	get-rebol-values: func [
		"Populates db-rowbuf with REBOL value(s) of a row."
		offset [integer!]
		columns [block!]
		/local length i
	][
		clear db-rowbuf
		i: 1
		loop db-cols [
			length: first skip db-dat offset
			insert tail db-rowbuf either find columns i [to-rebol-value/binary i copy/part skip db-dat offset + 1 length] [none]
			offset: offset + 1 + length
			++ i
		]
	]

	to-offset: func [
		"Converts a row number into an idx offset."
		row [integer!]
	][
		to integer! copy/part skip db-idx row - 1 * db-idx-size db-idx-size
	]

	to-idx-offset: func [
		"Converts a dat offset into an idx offset."
		offset [integer!]
	][
		index? find/skip db-idx skip int-to-bin offset db-idx-skip db-idx-size
	]

	row-length?: func [
		"Returns number of bytes used by row."
		offset [integer!]
		/local bytes length
	][
		bytes: 0
		loop db-cols [
			bytes: bytes + length: 1 + first skip db-dat offset
			offset: offset + length
		]
		either offset < length? db-dat [bytes] [0]
	]

	;	----------------------------------------
	;		Search functions
	;	----------------------------------------

	sort-idx: func [
		"Sort idx required by lookup & seek."
		/local key offset
	][
		either db-table/key-cols < 2 [
			repeat i db-rows [
				offset: to integer! key: copy/part skip db-idx i - 1 * db-idx-size db-idx-size
				insert tail db-buffer copy/part skip db-dat offset 1 + first skip db-dat offset
				insert tail db-buffer key
			]
		][
			repeat i db-rows [
				get-raw-key-values to integer! key: copy/part skip db-idx i - 1 * db-idx-size db-idx-size
				insert tail db-buffer copy db-keybuf
				insert tail db-buffer key
			]
		]
		clear db-idx
		foreach [val entry] sort/skip db-buffer 2 [insert tail db-idx entry]
		clear db-buffer
		db-idx-sort?: none
		all [db-trace? db-print-trace "Sort" db-rows]
	]

	lookup: func [
		"Binary search with key value(s)."
		values [block!]
		/local length offset lo mid hi val scans
	][
		all [db-idx-sort? sort-idx]
		clear db-keybuf
		repeat i length? values [
			insert tail db-keybuf to-raw-value i pick values i
		]
		length: length? db-keybuf
		lo: 1
		hi: db-rows
		mid: to integer! hi + lo / 2
		scans: 1
		while [hi >= lo] [
			all [
				db-keybuf = val: copy/part skip db-dat offset: to-offset mid length
				insert tail db-offsets offset
				break
			]
			either db-keybuf > val [lo: mid + 1] [hi: mid - 1]
			mid: to integer! hi + lo / 2
			++ scans
		]
		all [db-trace? db-print-trace "Lookup" scans]
		if any [db-table/key-cols = length? values empty? db-offsets] [exit]
		clear db-offsets
		scans: 1
		while [lo <= hi] [
			either db-keybuf = copy/part skip db-dat offset: to-offset lo length [
				insert tail db-offsets offset
			][
				unless empty? db-offsets [break]
			]
			++ lo
			++ scans
		]
		all [db-trace? db-print-trace "Seek" scans]
	]

	fetch: func [
		"Linear search with a block of conditions."
		predicate [block!]
		/local offset cols f
	][
		f: parse form predicate "[]()"
		cols: make block! 32
		repeat i db-cols [
			all [find f make string! reduce ["c" i] insert tail cols i]
		]
		f: func db-predicate predicate
		forskip db-idx db-idx-size [
			get-rebol-values offset: to integer! copy/part db-idx db-idx-size cols
			all [apply :f db-rowbuf insert tail db-offsets offset]
		]
		all [db-trace? db-print-trace "Fetch" db-rows]
	]

	;	----------------------------------------
	;		Exported functions
	;	----------------------------------------

	set 'db-append func [
		"Appends a row of values to a table (returns row count)."
		table [object!]
		values [block!]
		/nocheck "Skip values checking"
	][
		prepare table
		unless nocheck [
			assert [db-max-offset >= length? db-dat db-cols = length? values]
			if find values 'next [
				unless zero? db-rows [get-raw-key-values to-offset db-rows]
				repeat i max 1 table/key-cols [
					all [
						'next = pick values i
						poke values i either zero? db-rows [to pick db-types i 0] [1 + to-rebol-value i]
					]
				]
			]
			repeat i db-cols [
				assert [(type? pick values i) = pick db-types i]
			]
			if table/key-cols > 0 [
				lookup copy/part values table/key-cols
				unless empty? db-offsets [return false]
				prepare table
			]
			unless db-idx-sort? [
				clear db-keybuf
				repeat i max 1 table/key-cols [insert tail db-keybuf to-raw-value i pick values i]
				all [db-keybuf < copy/part skip db-dat to-offset db-rows length? db-keybuf db-idx-sort?: true]
			]
		]
		insert tail db-idx skip int-to-bin length? db-dat db-idx-skip
		repeat i length? values [insert tail db-dat to-raw-value i pick values i]
		all [db-trace? db-print-trace "Append" 1]
		db-rows
	]

	set 'db-change func [
		"Changes row values in a table (returns rows changed)."
		table [object!]
		columns [block!] "Column (integer!) value (any-type!) pairs"
		values [block!] "Key value(s) or conditions"
		/local val len row-len old-len
	][
		prepare table
		foreach [col val] columns [
			assert [find db-columns col]
			assert [(type? val) = pick db-types col]
		]
		case [
			zero? db-rows [return 0]
			empty? values [forskip db-idx db-idx-size [insert tail db-offsets to integer! copy/part db-idx db-idx-size]]
			find values word! [fetch values]
			true [lookup values]
		]
		all [empty? db-offsets return 0]
		foreach [col val] columns [
			insert tail db-buffer col
			insert tail db-buffer to-raw-value col val
		]
		foreach offset reverse db-offsets [
			clear db-keybuf
			get-raw-values offset
			old-len: 0
			repeat col db-cols [
				old-len: old-len + length? pick db-rowbuf col
				insert tail db-keybuf either val: select db-buffer col [val] [pick db-rowbuf col]
			]
			row-len: row-length? offset
			either any [row-len >= len: length? db-keybuf zero? row-len] [
				change/part skip db-dat offset db-keybuf len
			][
				assert [db-max-offset >= length? db-dat]
				change/part at db-idx to-idx-offset offset skip int-to-bin length? db-dat db-idx-skip db-idx-size
				insert tail db-dat db-keybuf
				len: 0
			]
			unless zero? row-len [table/bytes-free: table/bytes-free + old-len - len]
		]
		repeat i max 1 table/key-cols [
			all [find db-buffer i db-idx-sort?: true]
		]
		all [db-trace? db-print-trace "Change" length? db-offsets]
		length? db-offsets
	]

	set 'db-compact func [
		"Reclaims fragmented space in a table (returns bytes compacted)."
		table [object!]
		/local bytes new-idx new-dat
	][
		prepare table
		all [zero? table/bytes-free return 0]
		all [db-idx-sort? sort-idx]
		new-idx: make binary! length? db-idx
		new-dat: make binary! (length? db-dat) - table/bytes-free
		forskip db-idx db-idx-size [
			get-raw-values to integer! copy/part db-idx db-idx-size
			insert tail new-idx skip int-to-bin length? new-dat db-idx-skip
			foreach val db-rowbuf [insert tail new-dat val]
		]
		bytes: length? db-dat
		table/idx: new-idx
		table/dat: new-dat
		table/bytes-free: 0
		new-idx: new-dat: none
		db-table: none
		recycle
		all [db-trace? db-print-trace "Compact" db-rows]
		bytes - length? table/dat
	]

	set 'db-import func [
		"Imports rows of values into a table (returns row import count)."
		table [object!]
		block [block!]
		/nocoerce "Don't coerce values"
		/local rows values blk
	][
		prepare table
		any [integer? rows: divide length? block db-cols return false]
		blk: copy []
		repeat i db-cols [
			insert tail blk compose/deep [insert tail db-dat to-raw-value (i) (either nocoerce [][compose [to (pick db-types i)]]) pick values (i)]
		]
		do compose/deep [
			loop (rows) [
				values: copy/part block (db-cols)
				insert tail db-idx skip int-to-bin length? db-dat (db-idx-skip)
				(blk)
				block: skip block (db-cols)
			]
		]
		block: head block
		all [db-trace? db-print-trace "Import" rows]
		rows
	]

	set 'db-make func [
		"Makes a new table object."
		spec [block!] "Datatype!s"
		/index bytes [integer!] "Index width in bytes"
		/keys columns [integer!] "Number of columns in key"
	][
		foreach type reduce spec [
			assert [find reduce [binary! block! char! datatype! date! decimal! email! file! integer! issue! logic! money! pair! percent! string! tag! time! tuple! url! word!] type]
		]
		make object! [
			types:		reduce spec
			key-cols:	1
			idx-size:	max 1 min 4 any [bytes 2]
			bytes-free:	0		
			idx:		make binary! to integer! power 2 idx-size * 5
			dat:		make binary! to integer! power 2 idx-size * 7
			all [columns key-cols: max 0 min length? types columns]
		]
	]

	set 'db-remove func [
		"Removes rows from a table (returns rows removed)."
		table [object!]
		values [block!] "Key value(s) or conditions"
		/local rows
	][
		prepare table
		all [zero? db-rows return 0]
		unless empty? values [
			either find values word! [fetch values] [lookup values]
			all [empty? db-offsets return 0]
		]
		rows: db-rows
		either any [empty? values db-rows = length? db-offsets] [
			clear db-idx
			clear db-dat
			table/bytes-free: 0
		][
			foreach offset db-offsets [
				table/bytes-free: table/bytes-free + row-length? offset
			]
			foreach offset reverse db-offsets [
				remove/part at db-idx to-idx-offset offset db-idx-size
			]
		]
		recycle
		all [db-trace? db-print-trace "Remove" rows - db-rows]
		rows - db-rows
	]

	set 'db-select func [
		"Returns columns and rows from a table."
		table [object!]
		columns [block!] "Column numbers"
		values [block!] "Key value(s) or conditions"
	][
		prepare table
		either empty? columns [columns: db-columns] [
			assert [db-cols >= length? columns]
			foreach col columns [assert [find db-columns col]]
		]
		case [
			zero? db-rows [return db-buffer]
			empty? values [forskip db-idx db-idx-size [insert tail db-offsets to integer! copy/part db-idx db-idx-size]]
			find values word! [fetch values]
			true [lookup values]
		]
		either empty? difference columns db-columns [
			foreach offset db-offsets [
				get-raw-values offset
				foreach col columns [insert tail db-buffer to-rebol-value col]
			]
		][
			foreach offset db-offsets [
				get-rebol-values offset columns
				foreach col columns [insert tail db-buffer pick db-rowbuf col]
			]
		]
		all [db-trace? db-print-trace "Select" (length? db-buffer) / length? columns]
		db-buffer
	]
]