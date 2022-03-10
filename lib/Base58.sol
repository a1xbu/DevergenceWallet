pragma ton-solidity >=0.50.0;

library Base58 {
    uint8 constant PREFIX_edsig = 0;
    uint8 constant PREFIX_tz1 = 1;
    uint8 constant PREFIX_tz2 = 2;
    uint8 constant PREFIX_tz3 = 3;
    uint8 constant PREFIX_edpk = 4;

    function encode(bytes source) internal pure returns (bytes) {
        if (source.length == 0)
            return "";
        uint8[] digits = new uint8[](source.length * 6);
        digits[0] = 0;
        uint8 digitlength = 1;
        for (uint256 i = 0; i<source.length; ++i) {
            uint carry = uint8(source[i]);
            for (uint256 j = 0; j<digitlength; ++j) {
                carry += uint(digits[j]) * 256;
                digits[j] = uint8(carry % 58);
                carry = carry / 58;
            }

            while (carry > 0) {
                digits[digitlength] = uint8(carry % 58);
                digitlength++;
                carry = carry / 58;
            }
        }
        return _toAlphabet(_reverse(_truncate(digits, digitlength)));
    }

    function encode_check(bytes source) internal pure returns (bytes) {
        bytes result;
        bytes src_data = source;
        uint256 hash = sha256(source);

        bytes digest = "" + bytes32(sha256("" + bytes32(hash)));

        src_data.append(digest[:4]);
        return encode(src_data);
    }

    function b58encode(bytes source, uint8 prefix) internal pure returns (string) {
        bytes src = "";
        // https://pytezos.baking-bad.org/tutorials/01.html#base58-encoding
        if (prefix == PREFIX_edsig) src = "\t\xf5\xcd\x86\x12"; // ed25519 signature
        else if (prefix == PREFIX_tz1) src = "\x06\xa1\x9f"; // ed25519 public key hash
        else if (prefix == PREFIX_tz2) src = "\x06\xa1\xa1"; // secp256k1 public key hash
        else if (prefix == PREFIX_tz3) src = "\x06\xa1\xa4"; // p256 public key hash
        else if (prefix == PREFIX_edpk) src = "\r\x0f%\xd9"; // ed25519 public key

        src.append(source);
        return string(encode_check(src));
    }

    function _truncate(uint8[] array, uint8 length) internal pure returns (uint8[]) {
        uint8[] output = new uint8[](length);
        for (uint256 i = 0; i<length; i++) {
            output[i] = array[i];
        }
        return output;
    }

    function _reverse(uint8[] input) internal pure returns (uint8[]) {
        uint8[] output = new uint8[](input.length);
        for (uint256 i = 0; i<input.length; i++) {
            output[i] = input[input.length-1-i];
        }
        return output;
    }

    function _toAlphabet(uint8[] indices) internal pure returns (bytes) {
        bytes ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
        bytes output = "";
        for (uint256 i = 0; i<indices.length; i++) {
            output.append(ALPHABET[indices[i]:indices[i]+1]);
        }
        return output;
    }
}

library Bytes {
    function fromUint256(uint256 x) internal inline returns (bytes out) {
        out = "" + bytes32(x);
    }
}