pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "./User.sol";

library MsgFlag {
    uint8 constant SENDER_PAYS_FEES     = 1;
    uint8 constant IGNORE_ERRORS        = 2;
    uint8 constant DESTROY_IF_ZERO      = 32;
    uint8 constant REMAINING_GAS        = 64;
    uint8 constant ALL_NOT_RESERVED     = 128;
}

contract TezosFaucet {

    TvmCell m_userCode;
    uint m_op_id = 0;

    uint128 m_tezos_faucet_balance = 100000000;

    struct ClaimInfo {
        uint256 pubkey;
        address surf_address;
    }
    mapping(uint => ClaimInfo) m_queued_claims;

    event ClaimEvent(
        uint256 claim_id,
        uint256 pubkey,
        address surf_address
    );

    event ClaimSuccessEvent(
        uint256 claim_id,
        uint256 pubkey,
        string op_hash
    );

    constructor() public {
        tvm.accept();
    }

    /*
        @notice Emit tokens claim request
        @param deploy Indicates if we need to deploy User's contract
        @param surf_address Surf wallet contract address
    */
    function claim(bool deploy, address surf_address) public returns (uint op_id){
        tvm.accept();
        uint256 pubkey = msg.pubkey();

        address user;
        if (deploy) {
            user = new User{
                value: 0.2 ton,
                flag: MsgFlag.SENDER_PAYS_FEES,
                code: m_userCode,
                pubkey: 0,
                varInit: {
                    faucet_address: address(this),
                    owner_pubkey: pubkey
                }
            }();
        }

        m_op_id ++;
        m_queued_claims[m_op_id] = ClaimInfo(pubkey, surf_address);
        emit ClaimEvent(m_op_id, pubkey, surf_address);
        return m_op_id;
    }

    function query_queue() public returns(uint claim_id, uint256 pubkey, address surf_address) {
        optional(uint, ClaimInfo) val = m_queued_claims.min();
        if(!val.hasValue())
            return (0, 0, address(0));
        ClaimInfo info;
        (claim_id, info) = val.get();
        pubkey = info.pubkey;
        surf_address = info.surf_address;
    }

    /*
        @notice Get last known faucet balance, EVER giver balance, and calculate User's contract address
        @param pubkey Public key of the user
    */
    function GetFaucetInfo(uint256 pubkey)
        external
        view
        returns
    (address user_address, uint128 tezos_faucet_balance, uint128 contract_balance) {
        user_address = getExpectedUserAddress(pubkey);
        tezos_faucet_balance = m_tezos_faucet_balance;
        contract_balance = address(this).balance;
    }

    /*
        @notice The relay call this function after successfully transferring Tezos to the recipient.
                ClaimSuccess updates the claim request at the user's contract, updates the faucet balance,
                and sends 0.1 EVER to the user.
        @param user_pubkey Public key of the claimer
        @param claim_id Claim operation id
        @param op_hash Tezos operation group hash
        @param surf_address Surf wallet of the user, we send EVER to this address
        @param faucet_balance The last known faucet TEZ balance
    */
    function ClaimSuccess(
        uint256 user_pubkey,
        uint claim_id,
        string op_hash,
        address surf_address,
        uint128 faucet_balance
    )
        public
    {
        require(msg.pubkey() == tvm.pubkey(), 100);
        require(m_queued_claims.exists(claim_id), 101);
        tvm.accept();

        address user = getExpectedUserAddress(user_pubkey);
        m_tezos_faucet_balance = faucet_balance;

        User(user).OnClaimSuccess{value: 0.2 ton, flag: MsgFlag.SENDER_PAYS_FEES}(
            claim_id,
            op_hash
        );

        delete m_queued_claims[claim_id];
        emit ClaimSuccessEvent(claim_id, user_pubkey, op_hash);
        if(address(this).balance > 2 ton)
            surf_address.transfer({value: 0.1 ton, bounce: false});
    }

    /*
        @notice Derive User address from the owner's pubkey
        @param owner_address_ Token wallet owner address
    */
    function getExpectedUserAddress(
        uint256 owner_pubkey_
    )
        internal
        inline
        view
    returns (
        address
    ) {
        TvmCell stateInit = tvm.buildStateInit({
            contr: User,
            varInit: {
                faucet_address: address(this),
                owner_pubkey: owner_pubkey_
            },
            pubkey: 0,
            code: m_userCode
        });

        return address(tvm.hash(stateInit));
    }

    function setUserCode(TvmCell code)
        public
    {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        m_userCode = code;
    }
}