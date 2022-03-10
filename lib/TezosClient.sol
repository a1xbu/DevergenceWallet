pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;


import "./../interfaces/Hex.sol";
import "./../interfaces/SigningBoxInput.sol";
import "./../interfaces/Sdk.sol";

import "./TezosRPC.sol";

abstract contract State {
    uint32 private m_action = 0;
    uint32 private m_step = 0;

    function action() internal returns(uint32) {
        return m_action;
    }

    function step() internal returns(uint32) {
        return m_step;
    }

    function next_step() internal returns(uint32) {
        m_step ++;
        return m_step;
    }

    function set_action(uint32 action_id) internal {
        m_action = action_id;
        m_step = 0;
    }
}

library Action {
    uint32 constant INIT = 100;
    uint32 constant BALANCE = 200;
    uint32 constant TRANSFER = 300;
    uint32 constant TOKENS = 400;
    uint32 constant TX_RESULT = 500;

    uint32 constant STEP_INIT = 0;
    uint32 constant STEP_INIT_ADDRESS = 1;

    uint32 constant STEP_CHECK_REVEALED = 0;
    uint32 constant STEP_UPDATE_BALANCE = 1;

    uint32 constant STEP_TRANSFER_INIT = 0;
    uint32 constant STEP_TRANSFER_UPDATE_ADDRESS = 1;
    uint32 constant STEP_TRANSFER_GET_HEAD = 2;
    uint32 constant STEP_TRANSFER_GET_COUNTER = 3;
    uint32 constant STEP_TRANSFER_CREATE_FORGE = 4;
    uint32 constant STEP_TRANSFER_DECODE_FORGED = 5;
    uint32 constant STEP_TRANSFER_SIGN = 6;
    uint32 constant STEP_TRANSFER_PREAPPLY = 7;
    uint32 constant STEP_TRANSFER_INJECT = 8;
}

library Fee {
    // TODO: use /chains/main/blocks/head/helpers/scripts/run_operation to calculate real fees and used gas
    // This will require to split DeBot into several DeBots because we are currently
    // limited with 16383 bytes for the DeBot code size

    uint128 constant REVEAL_FEE = 1300;
    uint128 constant TEZ_TRANSFER_FEE = 1100;
    uint128 constant TOKEN_TRANSFER_FEE = 5000;
    uint128 constant DEFAULT_STORAGE_LIMIT = 257;
    uint128 constant DEFAULT_GAS_LIMIT = 5000;

    uint128 constant DEAFULT_EXTRA_FEE = 500;
}


abstract contract TezosClient is TezosRPC, State {

    string internal m_tezos_address;
    uint256 internal m_pubkey;
    bytes internal m_pubkey_hash;
    uint128 internal m_balance;
    uint32 internal m_sbHandle;

    TezosJson.Transaction internal m_reveal_tx;
    TezosJson.Transaction internal m_last_tx;
    TezosJson.OperationShell internal m_last_op;
    bytes internal m_signature;
    string internal m_signature_base58;
    string internal m_signature_hex;
    bytes internal m_forged_binary;

    uint32 private m_last_reason;
    uint128 m_fee = Fee.DEAFULT_EXTRA_FEE;

    //--------------------------------------
    function InitClient() internal {
        set_action(Action.INIT);
        run();
    }
    function _init(uint32 step) private {
        if(step == Action.STEP_INIT) {
            UserInfo.getPublicKey(tvm.functionId(OnGetPublicKey));
        }
        else if(step == Action.STEP_INIT_ADDRESS) {
            Blake2b.digest(tvm.functionId(_pubKeyHashToAddress), Bytes.fromUint256(m_pubkey), 20);
        }
    }
    function OnInitClient() internal virtual;

    //--------------------------------------
    function UpdateBalance(uint32 reason) internal {
        set_action(Action.BALANCE);
        m_last_reason = reason;
        run();
    }
    function _balance(uint32 step) private {
        if(step == Action.STEP_CHECK_REVEALED) {
            if(!IsRevealed())
                rpc_contract_key(m_tezos_address);
            else
                step = next_step();
        }
        if(step == Action.STEP_UPDATE_BALANCE)
            rpc_contract_balance(m_tezos_address);
    }
    function OnUpdateBalance(uint32 reason) internal virtual;

    //--------------------------------------
    function UpdateTokens() internal {
        set_action(Action.TOKENS);
        run();
    }
    function _tokens(uint32 step) private {
        rpc_account_tokens(m_tezos_address);
    }
    function OnUpdateTokens() internal virtual;

    //--------------------------------------
    function UpdateTxResult() internal {
        set_action(Action.TX_RESULT);
        run();
    }
    function _tx_result(uint32 step) private {
        rpc_explorer_op(m_tx_hash);
    }
    function OnUpdateTxResult(TxResult[] opg) internal virtual;

    //--------------------------------------

    function Transfer(string destination, uint128 amount) internal {
        set_action(Action.TRANSFER);

        TezosJson.Transaction t;
        t.source = m_tezos_address;
        t.destination = destination;
        t.amount = amount;
        t.fee = Fee.TEZ_TRANSFER_FEE + m_fee;  // TODO: implement fee calculation
        t.gas_limit = Fee.DEFAULT_GAS_LIMIT;
        t.storage_limit = Fee.DEFAULT_STORAGE_LIMIT;
        t.counter = m_contract_counter + 1;
        m_last_tx = t;

        run();
    }

    function TransferTokens(string token_address, string destination, uint128 amount) internal {
        set_action(Action.TRANSFER);

        TezosJson.Transaction t;
        t.source = m_tezos_address;
        t.destination = token_address;
        t.amount = 0; // We transfer FA1.2 tokens, not TEZ!
        t.fee = Fee.TOKEN_TRANSFER_FEE + m_fee;  // TODO: implement fee calculation
        t.gas_limit = Fee.DEFAULT_GAS_LIMIT;
        t.storage_limit = Fee.DEFAULT_STORAGE_LIMIT;
        t.parameters = TezosJson.wrap_fa1_token_transfer(m_tezos_address, destination, amount);

        m_last_tx = t;

        run();
    }

    function PrepareReveal() internal returns(string){
        string pubkey_b58 = Base58.b58encode(Bytes.fromUint256(m_pubkey), Base58.PREFIX_edpk);
        TezosJson.Reveal r;
        r.source = m_tezos_address;
        r.counter = m_contract_counter + 1;
        r.public_key = pubkey_b58;
        r.fee = Fee.REVEAL_FEE + m_fee;
        r.gas_limit = Fee.DEFAULT_GAS_LIMIT;
        r.storage_limit = 0;
        m_contract_counter++;

        return TezosJson.wrap_reveal(r);
    }

    function _transfer(uint32 step) private {
        // Send tokens
        if(step == Action.STEP_TRANSFER_INIT)
            SigningBoxInput.get(tvm.functionId(_onGetSigningBox), "How would you like to sign?", [m_pubkey]);
        else if(step == Action.STEP_TRANSFER_UPDATE_ADDRESS)
            Blake2b.digest(tvm.functionId(_pubKeyHashToAddress), Bytes.fromUint256(m_pubkey), 20);
        else if(step == Action.STEP_TRANSFER_GET_HEAD)
            rpc_blocks_hash();
        else if(step == Action.STEP_TRANSFER_GET_COUNTER)
            rpc_contract_counter(m_tezos_address);
        else if(step == Action.STEP_TRANSFER_CREATE_FORGE) {
            string[] tx_list;
            if(!IsRevealed())
                tx_list.push(PrepareReveal());

            m_last_tx.counter = m_contract_counter + 1;
            tx_list.push(TezosJson.wrap_transaction(m_last_tx));

            TezosJson.OperationShell op;
            op.contents = tx_list;
            op.branch = m_last_block_hash;
            m_last_op = op;

            string op_str = TezosJson.wrap_operation(m_last_op);
            rpc_helpers_forge(m_last_block_hash, op_str);
        }
        else if(step == Action.STEP_TRANSFER_DECODE_FORGED) {
            Hex.decode(tvm.functionId(OnHexDecode), m_forged_hex);
        }
        else if(step == Action.STEP_TRANSFER_SIGN) {
            bytes forged = "\x03";
            forged.append(m_forged_binary);
            Blake2b.digest(tvm.functionId(OnTxHash), forged, 32);
        }
        else if(step == Action.STEP_TRANSFER_PREAPPLY) {
            m_last_op.protocol = m_protocol;
            string op_str = TezosJson.wrap_operation(m_last_op);
            DbgPrint(op_str);
            rpc_preapply("[" + op_str + "]");
        }
        else if(step == Action.STEP_TRANSFER_INJECT) {
            string tx_hex = '"' + m_forged_hex + m_signature_hex + '"';
            rpc_inject(tx_hex);
        }
    }
    function OnTransferSuccess(string tx_hash) internal virtual;
    function OnTransferFailed(uint32 step, int32 code) internal virtual;

    function next() private { next_step(); run(); }
    function run() private {
        DbgPrint(format("ACTION: {}:{}", action(), step()));
        if(action() == Action.INIT) _init(step());
        else if(action() == Action.BALANCE) _balance(step());
        else if(action() == Action.TRANSFER) _transfer(step());
        else if(action() == Action.TOKENS) _tokens(step());
        else if(action() == Action.TX_RESULT) _tx_result(step());
    }

    //-------------- internal callbacks ----------------
    function OnGetPublicKey(uint256 value) public {
        m_pubkey = value;
        next();
    }

    function _onGetSigningBox(uint32 handle) public {
        m_sbHandle = handle;
        Sdk.getSigningBoxInfo(tvm.functionId(checkSingingBoxInfo), handle);
    }

    function checkSingingBoxInfo(uint32 result, uint256 key) public {
        require(result == 0);
        m_pubkey = key;
        next();
    }

    function OnHexDecode(bytes data) public {
        m_forged_binary = data;
        next();
    }

    function OnTxHash(uint256 hash) public {
        Sdk.signHash(tvm.functionId(setSignature), m_sbHandle, hash);
    }

    function setSignature(bytes signature) public {
        m_signature = signature;
        m_last_op.signature = Base58.b58encode(signature, Base58.PREFIX_edsig);
        DbgPrint(format("Signature: {} {}", m_last_op.signature, signature.length));
        Hex.encode(tvm.functionId(encodeSignature), signature);
	}

    function encodeSignature(string hexstr) public {
        m_signature_hex = hexstr;
        next();
    }

    function _pubKeyHashToAddress(uint256 hash) public {
        bytes pubKey_hash = Bytes.fromUint256(hash);
        m_tezos_address = Base58.b58encode(pubKey_hash[:20], Base58.PREFIX_tz1);

        if(action() == Action.INIT)
            OnInitClient();
        else
            next();
    }


    function OnCallSuccess() internal override {
        DbgPrint(format("OnCallSuccess {}:{}", action(), step()));
        if(action() == Action.BALANCE && step() == Action.STEP_UPDATE_BALANCE) {
            m_balance = m_contract_balance > 0 ? uint128(m_contract_balance) : 0;
            OnUpdateBalance(m_last_reason);
        }
        else if(action() == Action.TRANSFER && step() == Action.STEP_TRANSFER_INJECT) {
            OnTransferSuccess(m_tx_hash);
        }
        else if(action() == Action.TOKENS) {
            OnUpdateTokens();
        }
        else if(action() == Action.TX_RESULT) {
            OnUpdateTxResult(m_opg);
        }
        else
            next();
    }

    function OnCallError(int32 status_code, int32 error_code) internal override {
        if(action() == Action.TRANSFER) {
            OnTransferFailed(step(), status_code);
        }
    }

    // ----------------- getters ------------------
    function GetAddress() internal view inline returns (string) {
        return m_tezos_address;
    }

    function GetBalance() internal view inline returns (uint128) {
        return m_balance;
    }

    function GetTokens() internal view returns(Token[] tokens) {
        tokens = m_tokens;
    }

    function GetLastTxHash() internal view inline returns (string) {
        return m_tx_hash;
    }

    function GetLastOpg() internal view inline returns (TxResult[]) {
        return m_opg;
    }

    function IsRevealed() internal view inline returns (bool) {
        return m_is_reveled;
    }
}
