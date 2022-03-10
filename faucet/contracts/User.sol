pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;


contract User {
    uint256 static owner_pubkey;
    address static faucet_address;

    struct Op{
        uint claim_id;
        string op_hash;
    }

    Op[] m_claim_ops;

    constructor() public {
        tvm.accept();
    }

    function OnClaimSuccess(uint claim_id, string op_hash) public {
        require(msg.sender == faucet_address, 100);
        tvm.rawReserve(address(this).balance - msg.value, 2);
        m_claim_ops.push(Op(claim_id, op_hash));
        msg.sender.transfer({ value: 0, flag: 128 });
    }

    /*
        Request the list of last 'number' operations.
        If number is 0 or greater than the total number fo claims,
        the entire list of claims is returned.
    */
    function GetLastOps(uint number) external view returns(Op[]) {
        if(number > m_claim_ops.length || number == 0)
            number = m_claim_ops.length;
        Op[] claims = new Op[](number);
        for(uint i = 0; i < number; i++) {
            claims[i] = m_claim_ops[m_claim_ops.length - i - 1];
        }
        return claims;
    }

}
