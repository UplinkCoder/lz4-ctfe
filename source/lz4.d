module lz4;
/**
 * CTFEable LZ4 decompressor
 * Copyright © 2016 Stefan Koch
 * All rights reserved
 */
enum Endianess
{
	BigEndian,
	LittleEndian
}
/// JUST TO DEMONSTRATE THAT IT IS UNLIKELY :)
auto unlikely(T)(T expressionValue)
{
	return expressionValue;
}

T fromBytes(T, Endianess endianess = Endianess.LittleEndian)(const ubyte[] _data)
{
	static assert(is(T : long)); // poor man's isIntegral
	T result;

	foreach (i; 0 .. T.sizeof)
	{
		static if (endianess == Endianess.LittleEndian)
		{
			result |= (_data[i] << i * 8);
		}
		else
		{
			result |= (_data[i] << (T.sizeof - 1 - i) * 8);
		}
	}
	return result;
}

struct LZ4Header
{
	//TODO: finish this! ("parsing" LZ4 Frame format header)
	int end = 7;
	ubyte flags;

	bool hasBlockIndependence;
	bool hasBlockChecksum;
	bool hasContentChecksum;

	ulong contentSize;

	this(const ubyte[] data) pure
	{
		assert(((data[0] >> 6) & 0b11) == 0b01, "Format can not be read");

		hasBlockIndependence = ((data[0] >> 5) & 0b1);
		hasBlockChecksum = ((data[0] >> 4) & 0b1);

		bool hasContentSize = ((data[0] >> 3) & 0b1);

		hasContentChecksum = ((data[0] >> 2) & 0b1);

		if (hasContentSize)
		{
			contentSize = fromBytes!ulong(data[2 .. 2 + ulong.sizeof]);
			assert(contentSize);
			end = end + cast(uint)ulong.sizeof;
		}
	}
}

ubyte[] decodeLZ4File(const ubyte[] data) pure in {
	assert(data.length > 11, "Any valid LZ4 File has ti be longer then 11 bytes");
} body {
	ubyte[] result;
	assert(data[0 .. 4] == [0x04, 0x22, 0x4d, 0x18], "not a valid LZ4 file");
	auto lz4Header = LZ4Header(data[5 .. $]);
	size_t decodedBytes = lz4Header.end;


	while(true) {
		uint length = fromBytes!uint(data[decodedBytes .. decodedBytes + uint.sizeof]);
		if (length == 0) { 
			return result;
		}
		result ~= decodeLZ4Block(data[decodedBytes + uint.sizeof ..  $], length);
		decodedBytes += length + uint.sizeof;
	}
	assert(0); // "We can never get here"
}

ubyte[] decodeLZ4Block(const ubyte[] input, uint blockLength) pure in {
	assert(input.length > 5, "empty or too short input passed to decodeLZ4Block");
} body {
	uint coffset;
	uint dlen;

//	ubyte[] output;
	ubyte[64000] output;
	import core.stdc.string;
	import core.stdc.stdlib;

//	ubyte* bfr = malloc(6881280); 
	while (true)
	{
		auto bitfield = input[coffset++];
		auto highBits = (bitfield >> 4);
		auto lowBits = bitfield & 0xF;

		if (highBits)
		{
			uint literalsLength = 0xF;

			if (highBits != 0xF)
			{
				literalsLength = highBits;
			}
			else
			{
				while (input[coffset++] == 0xFF)
				{
					literalsLength += 0xFF;
				}
				literalsLength += input[coffset - 1];
			}

			output[dlen .. dlen + literalsLength] = input[coffset .. coffset + literalsLength];
			coffset += literalsLength;
			dlen += literalsLength;
		}

		if (coffset >= blockLength)
			return output[0 .. dlen].dup;

		uint matchLength = 0xF + 4;
		ushort offset = (input[coffset++] | (input[coffset++] << 8));

		if (lowBits != 0xF)
		{
			matchLength = lowBits + 4;
		}
		else
		{
			while (input[coffset++] == 0xFF)
			{
				matchLength += 0xFF;
			}
			matchLength += input[coffset - 1];
		}

		if (unlikely(offset < matchLength))
		{

			// this works for now. Maybe it's even more complicated...
			// e.g. lz4 widens the offset as the match gets longer
			// but the docs seem to suggest that the following code is indeed correct
			uint done = matchLength;

			while (unlikely(offset < done))
			{ // TODO: IS IT REALLY _unlikely_ or could be _likely_ ?
				if (__ctfe) {
					foreach(i;0 .. offset) {
						output[i + dlen] = output[i + dlen - offset];
					}
				//	output[dlen .. dlen + offset] = output[dlen - offset .. dlen];
				} else {
					memcpy(output.ptr + dlen, output.ptr + dlen - offset, offset);
				}
				//output ~= output[dlen - offset .. dlen];
		
			
				dlen += offset;
				done -= offset;
			}

			if (__ctfe) {
				foreach(i;0 .. done) {
					output[i + dlen] = output[i + dlen - offset];
				}
			//output[dlen .. dlen + done] = output[dlen - offset .. (dlen - offset) + done];
			} else {
				memcpy(output.ptr + dlen, output.ptr + dlen - offset, done);
			}
			dlen += done;
		}
		else
		{
			if (__ctfe) {
				foreach(i;0 .. matchLength) {
					output[i + dlen] = output[i + dlen - offset];
				}
			//	output[dlen .. dlen + matchLength] = output[dlen - offset .. (dlen - offset) + matchLength];
			} else {
				memcpy(output.ptr + dlen, output.ptr + dlen - offset, matchLength);
			}
			//output ~= output[dlen - offset .. (dlen - offset) + matchLength];
			dlen += matchLength;
		}
	}
}
