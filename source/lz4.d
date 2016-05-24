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

void Copy8(bool faster)(ubyte* dst, const (ubyte)* src, size_t length) pure nothrow @trusted
{
    if (length == 0)
        return;
    if (__ctfe)
    {
        foreach (i; 0 .. length)
        {
            dst[i] = src[i];
        }
        return;
    }
    static if (faster)
    {
        pragma(msg, "I hope you know what you are doing\n" "This function may override by 7 bytes");

        length += length % 8;
    }
    else
    {
        immutable stillToGo = length % 8;
        length -= length % 8;
    }

    while (length != 0)
    {
        *(cast(ulong*) dst) = *(cast(ulong*) src);
        length -= 8;
        dst += 8;
        src += 8;
    }
    static if (!faster)
    {
        switch (stillToGo)
        {
        case 7:
            *(cast(ushort*) dst + 7) = *(cast(ushort*) src + 7);
            *(cast(ubyte*) dst + 5) = *(cast(ubyte*) src + 5);
            goto case 4;
        case 4:
            *(cast(uint*) dst) = *(cast(uint*) src);
            break;
        case 3:
            *(cast(ubyte*) dst + 3) = *(cast(ubyte*) src + 3);
            goto case 2;
        case 2:
            *(cast(ushort*) dst) = *(cast(ushort*) src);
            break;
        case 1:
            *(cast(ubyte*) dst) = *(cast(ubyte*) src);
            break;
        default:
            break;
        }
    }

    return;

}
alias fastCopy = Copy8!false;
T fromBytes(T, Endianess endianess = Endianess.LittleEndian) (const ubyte[] _data)
pure {
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
            end = end + cast(uint) ulong.sizeof;
        }
    }
}


ubyte[] decodeLZ4File(const ubyte[] data, uint size) pure {
	ubyte[] output;
	output.length = size;
	return decodeLZ4File(data, output.ptr, size);
}
ubyte[] decodeLZ4File(const ubyte[] data, ubyte* output, uint outLength) pure
in
{
    assert(data.length > 11, "Any valid LZ4 File has to be longer then 11 bytes");
}
body
{
    ubyte[] result = output[0 .. outLength];
    assert(data[0 .. 4] == [0x04, 0x22, 0x4d, 0x18], "not a valid LZ4 file");
    auto lz4Header = LZ4Header(data[5 .. $]);
    size_t decodedBytes = lz4Header.end;
    uint offset;
    while (true)
    {
        uint blockLength = fromBytes!uint(data[decodedBytes .. decodedBytes + uint.sizeof]);
        if (blockLength == 0)
        {
            return result;
        }
        decodeLZ4Block(data[decodedBytes + uint.sizeof .. $], blockLength, result);
        decodedBytes += blockLength + uint.sizeof;
    }
    assert(0); // "We can never get here"
}

//extern(C) ubyte* decodeLZ4Block(const(ubyte)* input, uint blockLength, ubyte* output, uint outLength) pure {
//	return decodeLZ4Block(input[0 .. blockLength], blockLength, output[0 .. outLength]).ptr;
//}


ubyte[] decodeLZ4Block(const ubyte[] input, uint blockLength, ref ubyte[] output) pure
in
{
    assert(input.length > 5, "empty or too short input passed to decodeLZ4Block");
}
body
{
    uint coffset;
    uint dlen;

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

        fastCopy(output.ptr + dlen,  input.ptr + coffset, literalsLength);
        coffset += literalsLength;
        dlen += literalsLength;

        if (coffset >= blockLength)
            return output[0 .. dlen];

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

            // this works for now. Maybe it's even more complicated...
            // e.g. lz4 widens the offset as the match gets longer
            // but the docs seem to suggest that the following code is indeed correct
            uint done = matchLength;

            while (unlikely(offset < done))
            { // TODO: IS IT REALLY _unlikely_ or could be _likely_ ?
                Copy8!true(output.ptr + dlen, output.ptr + dlen - offset, offset);
                //output ~= output[dlen - offset .. dlen];

                dlen += offset;
                done -= offset;
            }

            fastCopy(output.ptr + dlen, output.ptr + dlen - offset, done);
            dlen += done;
        }
        else
        {
            fastCopy(output.ptr + dlen, output.ptr + dlen - offset, matchLength);
            dlen += matchLength;
        }
    }
}
