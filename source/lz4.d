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
/// JUST TO DEMONSTRATE THAT IT IS LIKEY :)
auto likely(T)(T expressionValue)
{
    return expressionValue;
}

void fastCopy(ubyte* dst, const (ubyte)* src, size_t length) pure nothrow @trusted
{
    if (length == 0)
        return;
    static if (__VERSION__ <= 2068)
    {
        if (__ctfe)
        {
            foreach(i;0 .. length)
                dst[i] = src[i];
        }
    } else

    dst[0 .. length] = src[0 .. length];

    return;

}

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
        } else {
            static assert(0, "only int and long are supported");
        }
    } else {
        static assert(0, "Big Endian currently not supported");
    }

    return result;

}

struct LZ4Header
{
    //TODO: finish this! ("parsing" LZ4 Frame format header)
    uint end = 7;
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
//    return decodeLZ4Block(input[0 .. blockLength], blockLength, output[0 .. outLength]).ptr;
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

        if (unlikely(highBits == 0xF))
        {
            while (unlikely(input[coffset++] == 0xFF))
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
        immutable ushort offset = (input[coffset++] | (input[coffset++] << 8));

        if (unlikely(lowBits == 0xF))
        {
            while (input[coffset++] == 0xFF)
            {
                matchLength += 0xFF;
            }
            matchLength += input[coffset - 1];
        }

        if (unlikely(offset < matchLength))
        {
            uint done = matchLength;

            while (likely(offset < done))
            {
                //This is the point where er can speed up the copy significantly!
                fastCopy(output.ptr + dlen, output.ptr + dlen - offset, offset);

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
