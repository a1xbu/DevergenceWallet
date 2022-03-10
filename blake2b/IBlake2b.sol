pragma ton-solidity >=0.44.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

interface IBlake2b {
    function digest(bytes input, uint32 digest_size) external view returns (uint256 hash);
}


library Blake2b {

	uint256 constant ID = 0x438bae75507a67b40169e0b366490c9d22298e44ef7b98cd3c4bf215e2d4103b;
	int8 constant WC = 0;

	function digest(uint32 answerId, bytes input, uint32 digest_size) public {
		address addr = address.makeAddrStd(WC, ID);
        optional(uint256) pubkey;
		IBlake2b(addr).digest{
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: answerId,
            onErrorId: 0
        }(input, digest_size).extMsg;
	}
}
