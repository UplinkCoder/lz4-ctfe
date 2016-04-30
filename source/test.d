import lz4;

void static_unittest()
{
	static immutable ubyte[] compressed = [
		0x04, 0x22, 0x4d, 0x18, 0x64, 0x40, 0xa7, 0x38, 0x00, 0x00, 0x00, 0xf1,
		0x05, 0x74, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20, 0x61, 0x20, 0x4c,
		0x5a, 0x34, 0x20, 0x74, 0x65, 0x73, 0x74, 0x0a, 0x61, 0x07, 0x00, 0x40,
		0x20, 0x66, 0x6f, 0x72, 0x14, 0x00, 0x11, 0x0a, 0x22, 0x00, 0x04, 0x1d,
		0x00, 0x0d, 0x2b, 0x00, 0x05, 0x19, 0x00, 0x01, 0x27, 0x00, 0x80, 0x74,
		0x65, 0x73, 0x74, 0x20, 0x69, 0x73, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x3e,
		0xc6, 0x99, 0xe6
	];

	static immutable char[] uncompressed =
		"this is a LZ4 test\n"
		"a test for LZ4\n"
		"this LZ4 test is a LZ4 test\n"
		"a LZ4 test this test is\n"
	;

	static assert(decodeLZ4File(compressed) == uncompressed);
	pragma(msg, decodeLZ4File(cast(ubyte[]) import("lz4.d.lz4")));
}