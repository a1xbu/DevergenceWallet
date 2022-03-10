# Blake2b hash contract

Testnet address: 0:438bae75507a67b40169e0b366490c9d22298e44ef7b98cd3c4bf215e2d4103b

## Description

This contract can be used in DeBots to calculate Blake2b hash of a `bytes` array.
Blake2b is widely used in Tezos blockchain.

## Functions

`digest` - calculate blake2b hash and return digest of the bytes array.

arguments:

    answerId: uint32 - function id of result callback. 
                       Callback function should have one input parameter: "hash" of type uint256.

    input: bytes - the data to be hashed.

    digest_size: uint32  - size of output digest in bytes, must be <= 32

returns:

     hash: uint256 - resulting hash. If the digest_size is less than 32, you should truncate the resulting hash
     

## Examples

```solidity
import "./blake2b/IBlake2b.sol";

contract A {
    // Signing 32-byte blake2b hash of data
    function calc_hash32(bytes data) internal {
        Blake2b.digest(tvm.functionId(getHash), data, 32);
    }

    function getHash(uint256 hash) public {
        Sdk.signHash(tvm.functionId(setSignature), m_sbHandle, hash);
    }
}
```

```solidity
import "./blake2b/IBlake2b.sol";

contract B {
    // Calculating 20-byte blake2b hash of public key (used in Tezos to derive address from public key)
    function hash_pubkey(bytes pubkey) internal {
        Blake2b.digest(tvm.functionId(pubKeyHashToAddress), pubkey, 20);
    }

    function pubKeyHashToAddress(uint256 hash) public {
        // Convert uint256 to bytes
        //bytes pubKey_hash = Bytes.fromUint256(hash);
        // Base58-encode truncated bytes
        //string tezos_address = Base58.b58encode(pubKey_hash[:20], PREFIX_tz1);
    }
}
```
