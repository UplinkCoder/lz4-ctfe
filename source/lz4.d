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
	static if (endianess == Endianess.LittleEndian) {
		static if (T.sizeof == 4) {
			result = (
				_data[0] |
				(_data[1] << 8) |
				(_data[2] << 16) |
				(_data[3] << 24)
			); 
		} else static if (T.sizeof == 8) {
			result = (
				_data[0] |
				(_data[1] << 8) |
				(_data[2] << 16) |
				(_data[3] << 24) |
				(cast(ulong)_data[4] << 32UL) |
				(cast(ulong)_data[5] << 40UL) |
				(cast(ulong)_data[6] << 48UL) |
				(cast(ulong)_data[7] << 56UL)
			); 
		} else 
			static assert(0, "only int and long are supported");
	} else 
		static assert(0, "Big Endian currently not supported");

/*	foreach (i; 0 .. T.sizeof)
	{
		static if (endianess == Endianess.LittleEndian)
		{
			result |= (_data[i] << i * 8);
		}
		else
		{
			result |= (_data[i] << (T.sizeof - 1 - i) * 8);
		}
	} */
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
	ubyte[] output;
	
	while (true)
	{
		immutable bitfield = input[coffset++];
		immutable highBits = (bitfield >> 4);
		immutable lowBits = bitfield & 0xF;
		
		uint literalsLength = highBits;

		if (highBits == 0xF)
		{
			while (input[coffset++] == 0xFF)
			{
				literalsLength += 0xFF;
			}
			literalsLength += input[coffset - 1];
		}

		output ~= input[coffset .. coffset + literalsLength];
		coffset += literalsLength;
		

		if (coffset >= blockLength)
			return output;

		uint matchLength = lowBits + 4;
		ushort offset = (input[coffset++] | (input[coffset++] << 8));

		if (lowBits == 0xF)
		{
			while (input[coffset++] == 0xFF)
			{
				matchLength += 0xFF;
			}
			matchLength += input[coffset - 1];
		}

		if (unlikely(offset < matchLength))
		{
			uint startMatch = cast(uint) output.length - offset;

			// this works for now. Maybe it's even more complicated...
			// e.g. lz4 widens the offset as the match gets longer
			// but the docs seem to suggest that the following code is indeed correct

			while (unlikely(offset < matchLength))
			{ // TODO: IS IT REALLY _unlikely_ or could be _likely_ ?
				output ~= output[startMatch .. startMatch + offset];
				matchLength -= offset;
			}

			output ~= output[startMatch .. startMatch + matchLength];
		}
		else
		{
			output ~= output[$ - offset .. ($ - offset) + matchLength];
		}
	}
}
