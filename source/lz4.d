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
    uint flags;

    bool hasBlockIndependence;
    bool hasBlockChecksum;
    bool hasContentChecksum;

    ulong contentSize;

    this(const ubyte[] data) pure
    {
        immutable data0 = data[0];

        assert(((data0 >> 6) & 0b11) == 0b01, "Format can not be read");

        hasBlockIndependence = ((data0 >> 5) & 0b1);
        hasBlockChecksum = ((data0 >> 4) & 0b1);

        bool hasContentSize = ((data0 >> 3) & 0b1);

        hasContentChecksum = ((data0 >> 2) & 0b1);

        if (hasContentSize)
        {
            contentSize = fromBytes!ulong(data[2 .. 2 + ulong.sizeof]);
            assert(contentSize > 0);
            end = end + cast(uint) ulong.sizeof;
        }
    }
}


ubyte[] decodeLZ4File(const ubyte[] data, uint size) pure {
    ubyte[] output;
    output.length = size;
    return decodeLZ4File(data, output, size);
}
ubyte[] decodeLZ4File(const ubyte[] data, ubyte[] output, uint outLength) pure
in
{
    assert(data.length > 11, "Any valid LZ4 File has to be longer then 11 bytes");
}
body
{
    ubyte[] result = output[0 .. outLength];
    bool validFile = data[0 .. 4] == [0x04, 0x22, 0x4d, 0x18];
    assert(validFile, "not a valid LZ4 file");
    auto lz4Header = LZ4Header(data[5 .. $]);
    uint decodedBytes = lz4Header.end;
    uint offset;
    while (true)
    {
        uint blockLength = fromBytes!uint(data[decodedBytes .. decodedBytes + cast(uint)uint.sizeof]);
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


ubyte[] decodeLZ4Block(const ubyte[] input, uint blockLength, ubyte[] output) pure
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

        if (/*unlikely*/(highBits == 0xF))
        {
            while (/*unlikely*/(input[coffset++] == 0xFF))
            {
                literalsLength += 0xFF;
            }

            literalsLength += input[coffset - 1];
        }
        uint until_d = dlen + literalsLength;
        uint until_c = coffset + literalsLength;
        output[dlen .. until_d] = input[coffset .. until_c];
        coffset = until_c;
        dlen = until_d;

        if (coffset >= blockLength)
            return output[0 .. dlen];

        uint matchLength = lowBits + 4;
        immutable ushort offset = (input[coffset++] | (input[coffset++] << 8));

        if (/*unlikely*/(lowBits == 0xF))
        {
            while (input[coffset++] == 0xFF)
            {
                matchLength += 0xFF;
            }
            matchLength += input[coffset - 1];
        }

        if (/*unlikely*/(offset < matchLength))
        {
            uint done = matchLength;

            while (/*likely*/(offset < done))
            {
                //This is the point where er can speed up the copy significantly!
                const d_until = dlen + offset;
                const c_begin = dlen - offset;
                output[dlen .. d_until] = output[c_begin .. dlen];

                dlen = d_until;
                done -= offset;
            }
            const until = dlen + done;
            const c_begin = dlen - offset;
            const c_end = until - offset;

            output[dlen .. until] = output[c_begin .. c_end];
            dlen = until;
        }
        else
        {
            const until = dlen + matchLength;
            const c_begin = dlen - offset;
            const c_end = until - offset;

            output[dlen .. until] = output[c_begin .. c_end];
            dlen = until;
        }
    }
}
