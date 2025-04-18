package bencode

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"

Value :: union {
	string,
	int,
	[]Value,
	map[string]Value,
}

// TODO: proc overloading instead of switch statement?
encode1 :: proc(val: Value, allocator := context.allocator) -> []u8 {
	bcode := make([]u8, 0, allocator = allocator)
	switch v in val {
	case string:
		bcode = encode_string(v, allocator)
	case int:
		bcode = encode_int(v, allocator)
	case []Value:
		bcode = encode_list(v, allocator)
	case map[string]Value:
		bcode = encode_dict(v, allocator)
	}
	return bcode
}

decode :: proc(data: []byte, allocator := context.allocator) -> Value {
	reader := bytes.Reader {
		s         = data,
		i         = 0,
		prev_rune = -1,
	}
	return decode1(&reader, allocator)
}

decode1 :: proc(input: ^bytes.Reader, allocator := context.allocator) -> Value {
	val: Value
	next := input.s[input.i]
	switch next {
	case 'd':
		val = decode_dict(input, allocator)
	case 'l':
		val = decode_list(input, allocator)
	case '0' ..= '9':
		val = decode_string(input, allocator)
	case 'i':
		val = decode_int(input, allocator)
	case:
		fmt.println("invalid bencode: ", next)
		return nil
	}

	return val
}

encode_dict :: proc(d: map[string]Value, allocator := context.allocator) -> []u8 {
	data := make([dynamic]u8, allocator = allocator)

	keys, err := slice.map_keys(d, allocator)
	slice.sort(keys)

	append(&data, 'd')

	for key in keys {
		k := encode_string(key, allocator)
		append(&data, ..k)
		v := encode1(d[key], allocator)
		append(&data, ..v)
	}

	append(&data, 'e')

	return data[:]
}

decode_dict :: proc(input: ^bytes.Reader, allocator := context.allocator) -> map[string]Value {
	dict := make(map[string]Value, allocator = allocator)

	d, err := bytes.reader_read_byte(input)
	if err != .None || d != 'd' {
		fmt.println("dict decode error: ", err, ", d = ", d)
		return nil
	}

	key: string
	val: Value

	for input.s[input.i] != 'e' {
		key = decode_string(input, allocator)
		val = decode1(input, allocator)
		dict[key] = val
	}

	e: u8
	e, err = bytes.reader_read_byte(input)
	if err != .None || e != 'e' {
		fmt.println("dict decode error: ", err, ", e = ", e)
		return nil
	}

	return dict
}

encode_list :: proc(list: []Value, allocator := context.allocator) -> []u8 {
	data := make([dynamic]u8, allocator = allocator)

	append(&data, 'l')

	for value in list {
		v := encode1(value, allocator)
		append(&data, ..v)
	}

	append(&data, 'e')

	return data[:]
}

decode_list :: proc(input: ^bytes.Reader, allocator := context.allocator) -> []Value {
	list := make([dynamic]Value, allocator = allocator)

	l, err := bytes.reader_read_byte(input)
	if err != .None || l != 'l' {
		fmt.println("dict decode error: ", err, ", l = ", l)
		delete(list)
		return nil
	}

	val: Value
	for input.s[input.i] != 'e' {
		val = decode1(input, allocator)
		append(&list, val)
	}

	e: u8
	e, err = bytes.reader_read_byte(input)
	if err != .None || e != 'e' {
		fmt.println("dict decode error: ", err, ", e = ", e)
		delete(list)
		return nil
	}

	return list[:]
}

encode_string :: proc(str: string, allocator := context.allocator) -> []u8 {
	data := make([dynamic]u8, allocator = allocator)

	length := len(str)
	ldata: [20]u8
	len_str := strconv.itoa(ldata[:], length)
	append(&data, ..transmute([]u8)len_str[:])

	append(&data, ':')

	append(&data, ..transmute([]u8)str)

	return data[:]
}

decode_string :: proc(input: ^bytes.Reader, allocator := context.allocator) -> string {
	length_str: [dynamic]u8
	defer delete(length_str)

	next, err := bytes.reader_read_byte(input)
	if err != .None {
		fmt.println("string length read error: ", err)
		return ""
	}
	for next != ':' {
		append(&length_str, next)
		next, err = bytes.reader_read_byte(input)
		if err != .None {
			fmt.println("string length read error: ", err)
			return ""
		}
	}
	length := strconv.atoi(transmute(string)length_str[:])
	str := make([]u8, length, allocator = allocator)

	n: int
	n, err = bytes.reader_read(input, str)
	if n != length || err != .None {
		fmt.println("string read error: ", err, ", n: ", n, ", length: ", length)
		return ""
	}

	return transmute(string)str
}

encode_int :: proc(i: int, allocator := context.allocator) -> []u8 {
	data := make([dynamic]u8, allocator = allocator)

	append(&data, 'i')

	idata: [20]u8
	i_str := strconv.itoa(idata[:], i)
	append(&data, ..transmute([]u8)i_str[:])

	append(&data, 'e')

	return data[:]
}

decode_int :: proc(input: ^bytes.Reader, allocator := context.allocator) -> int {
	i, err := bytes.reader_read_byte(input)
	if err != .None || i != 'i' {
		fmt.println("dict decode error: ", err, ", i = ", i)
		return -1
	}

	digits := make([dynamic]u8, allocator = allocator)
	for input.s[input.i] != 'e' {
		digit, err := bytes.reader_read_byte(input)
		append(&digits, digit)
	}
	n := strconv.atoi(transmute(string)digits[:])

	e: u8
	e, err = bytes.reader_read_byte(input)
	if err != .None || e != 'e' {
		fmt.println("dict decode error: ", err, ", e = ", e)
		return -1
	}

	return n
}
