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
			end = 11;
		}
	}
}

ubyte[] decodeLZ4File(const ubyte[] data) pure in {
	assert(data.length > 11, "Any valid LZ4 File has ti be longer then 11 bytes");
} body {
	assert(data[0 .. 4] == [0x04, 0x22, 0x4d, 0x18], "not a valid LZ4 file");
	auto lz4Header = LZ4Header(data[5 .. $]);
	uint length = fromBytes!uint(data[lz4Header.end .. lz4Header.end + uint.sizeof]);

	return decodeLZ4Block(data[lz4Header.end + uint.sizeof .. $], length);
}

ubyte[] decodeLZ4Block(const ubyte[] input, uint blockLength) pure in {
	assert(input.length > 5, "empty or too short input passed to decodeLZ4Block");
} body {
	uint coffset;
	ubyte[] output;
	
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

			output ~= input[coffset .. coffset + literalsLength];
			coffset += literalsLength;
		}

		if (coffset >= blockLength)
			return output;

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
