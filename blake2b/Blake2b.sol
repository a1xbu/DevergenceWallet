// ton-solidity adapted version of https://github.com/blitslabs/filecoin-blake2b-solidity
pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;


contract Blake2b {
    uint64[8] constant IV = [
        uint64(0x6a09e667f3bcc908),
        uint64(0xbb67ae8584caa73b),
        uint64(0x3c6ef372fe94f82b),
        uint64(0xa54ff53a5f1d36f1),
        uint64(0x510e527fade682d1),
        uint64(0x9b05688c2b3e6c1f),
        uint64(0x1f83d9abfb41bd6b),
        uint64(0x5be0cd19137e2179)
    ];

    uint64 constant MASK_0 = 0xFF00000000000000;
    uint64 constant MASK_1 = 0x00FF000000000000;
    uint64 constant MASK_2 = 0x0000FF0000000000;
    uint64 constant MASK_3 = 0x000000FF00000000;
    uint64 constant MASK_4 = 0x00000000FF000000;
    uint64 constant MASK_5 = 0x0000000000FF0000;
    uint64 constant MASK_6 = 0x000000000000FF00;
    uint64 constant MASK_7 = 0x00000000000000FF;

    uint64 constant SHIFT_0 = 0x0100000000000000;
    uint64 constant SHIFT_1 = 0x0000010000000000;
    uint64 constant SHIFT_2 = 0x0000000001000000;
    uint64 constant SHIFT_3 = 0x0000000000000100;

    uint64 constant MASK_64 = 0xFFFFFFFFFFFFFFFF;

    uint8[][] internal sigma;

    constructor() public {
        tvm.accept();
        sigma = new uint8[][](0);
        sigma.push([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
        sigma.push([14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3]);
        sigma.push([11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4]);
        sigma.push([7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8]);
        sigma.push([9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13]);
        sigma.push([2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9]);
        sigma.push([12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11]);
        sigma.push([13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10]);
        sigma.push([6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5]);
        sigma.push([10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]);
        sigma.push([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
        sigma.push([14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3]);
    }

    struct BLAKE2b_ctx {
        uint8[128] b; //input buffer
        uint64[8] h; //chained state
        uint128 t; //total bytes
        uint64 c; //Size of b
        uint256 outlen; //diigest output size
    }

    // Mixing Function
    function G(
        uint64[16] v,
        uint8 a,
        uint8 b,
        uint8 c,
        uint8 d,
        uint64 x,
        uint64 y
    ) internal pure returns(uint64[16]){
        // Dereference to decrease reads
        uint64 va = v[a];
        uint64 vb = v[b];
        uint64 vc = v[c];
        uint64 vd = v[d];
        uint64 w;
        uint64[] res = v;

        va = uint64((uint256(va) + uint256(vb) + uint256(x)) & MASK_64);
        w = vd ^ va;
        vd = uint64(w >> 32) | uint64((w & 0xFFFFFFFF) << 32);
        vc = uint64((uint256(vc) + uint256(vd)) & MASK_64);
        w = vb ^ vc;
        vb = uint64(w >> 24) | uint64((w & 0xFFFFFF) << 40);
        va = uint64((uint256(va) + uint256(vb) + uint256(y)) & MASK_64);
        w = (vd ^ va);
        vd = uint64(w >> 16) | uint64((w & 0xFFFF) << 48);
        vc = uint64((uint256(vc) + uint256(vd)) & MASK_64);
        w = (vb ^ vc);
        vb = uint64(w >> 63) | uint64((w & 0x7fffffffffffffff) << 1 );

        res[a] = va;
        res[b] = vb;
        res[c] = vc;
        res[d] = vd;
        return res;
    }

    //Flips endianness of words
    function getWords(uint64 a) internal pure returns (uint64 b) {
        return
            ((a & MASK_0) / SHIFT_0) ^
            ((a & MASK_1) / SHIFT_1) ^
            ((a & MASK_2) / SHIFT_2) ^
            ((a & MASK_3) / SHIFT_3) ^
            ((a & MASK_4) * SHIFT_3) ^
            ((a & MASK_5) * SHIFT_2) ^
            ((a & MASK_6) * SHIFT_1) ^
            ((a & MASK_7) * SHIFT_0);
    }

    function G_group(uint64[16] v, uint64[16] m, uint8[16] s) internal pure returns(uint64[16]) {
        v = G(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
        v = G(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
        v = G(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
        v = G(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
        v = G(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
        v = G(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
        v = G(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
        v = G(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);

        return v;
    }

    function compress(BLAKE2b_ctx ctx, bool last) internal view returns(BLAKE2b_ctx){
        uint64[16] v = new uint64[](16);
        uint64[16] m = new uint64[](16);

        for (uint256 i = 0; i < 8; i++) {
            v[i] = ctx.h[i];
            v[i + 8] = IV[i];
        }

        v[12] = v[12] ^ uint64(ctx.t & MASK_64); //Lower word of t
        v[13] = v[13] ^ uint64(ctx.t >> 64);

        if (last) v[14] = ~v[14]; //Finalization flag

        uint64 mi; //Temporary stack variable to decrease ops
        uint256 b; // Input buffer

        for (uint32 i = 0; i < 16; i++) {
            mi = 0;
            for(uint32 k = 0; k < 8; k++) {
                mi = mi << 8;
                mi |= ctx.b[i*8 + k];
            }
            m[i] = getWords(mi);
        }

        for(uint32 i = 0; i < sigma.length; i++)
            v = G_group(v, m, sigma[i]);

        //XOR current state with both halves of v
        for (uint256 i = 0; i < 8; ++i) {
            ctx.h[i] = ctx.h[i] ^ v[i] ^ v[i + 8];
        }

        return ctx;
    }

    function init(
        BLAKE2b_ctx ctx,
        uint64 outlen,
        bytes key,
        uint64[2] salt,
        uint64[2] person
    ) internal view returns(BLAKE2b_ctx){
        ctx.h = new uint64[](8);
        ctx.b = new uint8[](128);

        //Initialize chained-state to IV
        for (uint8 i = 0; i < 8; i++) {
            ctx.h[i] = IV[i];
        }

        // Set up parameter block
        ctx.h[0] =
            ctx.h[0] ^
            0x01010000 ^
            shift_left(uint64(key.length), 8) ^
            outlen;
        ctx.h[4] = ctx.h[4] ^ salt[0];
        ctx.h[5] = ctx.h[5] ^ salt[1];
        ctx.h[6] = ctx.h[6] ^ person[0];
        ctx.h[7] = ctx.h[7] ^ person[1];

        ctx.outlen = outlen;

        //Run hash once with key as input
        if (key.length > 0) {
            ctx = update(ctx, key);
            ctx.c = 128;
        }
        return ctx;
    }

    function update(BLAKE2b_ctx ctx, bytes input) internal view returns(BLAKE2b_ctx){
        for (uint256 i = 0; i < input.length; i++) {
            //If buffer is full, update byte counters and compress
            if (ctx.c == 128) {
                ctx.t += ctx.c;
                ctx = compress(ctx, false);
                ctx.c = 0;
                ctx.b = new uint8[](128);
            }

            ctx.b[ctx.c] = uint8(input[i]);
            ctx.c ++;
        }
        return ctx;
    }

    function finalize(BLAKE2b_ctx ctx)
        internal
        view
        returns(uint64[4])
    {
        uint64[4] out = new uint64[](4);

        // Add any uncounted bytes
        ctx.t += ctx.c;

        // Compress with finalization flag
        ctx = compress(ctx, true);

        //Flip little to big endian and store in output buffer
        for (uint256 i = 0; i < 4; i++) {
            out[i] = getWords(ctx.h[i]);
        }

        return out;
    }

    //Helper function for full hash function
    function _blake2b(
        bytes input,
        bytes key,
        uint64[2] salt,
        uint64[2] personalization,
        uint64 outlen
    ) internal view returns (uint64[4]) {
        BLAKE2b_ctx ctx;
        uint64[4] out;

        ctx = init(ctx, outlen, key, salt, personalization);
        ctx = update(ctx, input);

        out = finalize(ctx);
        return out;
    }

    function digest(bytes input, uint32 digest_size) external view returns (uint256) {
        require(digest_size <= 32);

        uint64[2] slt = [uint64(0), uint64(0)]; // TODO: implement
        uint64[2] pers = [uint64(0), uint64(0)]; // TODO: implement

        uint64[4] result = _blake2b(input, "", slt, pers, digest_size);
        return uint256(sum256(result));
    }

    function sum256(uint64[4] array) private pure returns (bytes32) {
        bytes16 a = bytes16((uint128(array[0]) << 64) | array[1]);
        bytes16 b = bytes16((uint128(array[2]) << 64) | array[3]);
        bytes32 c = bytes32((uint256(uint128(a)) << 128) | uint128(b));
        return c;
    }

    function shift_right(uint64 a, uint256 shift) internal pure inline returns (uint64 b){
        return uint64(a >> shift);
    }

    function shift_left(uint64 a, uint256 shift) internal pure inline returns (uint64) {
        return uint64((uint256(a) << shift) & 0xFFFFFFFFFFFFFFFF);
    }
}
