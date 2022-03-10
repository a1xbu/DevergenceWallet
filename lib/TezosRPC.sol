pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;


import "./../interfaces/Terminal.sol";
import "./../interfaces/Network.sol";
import "./../interfaces/Json.sol";
import "./../interfaces/UserInfo.sol";
import "./../interfaces/JsonLib.sol";

import "./../blake2b/IBlake2b.sol";
import "./Base58.sol";


library TezosJson {

    struct Transaction {
        string source;
        string destination;
        uint128 amount;
        int counter;
        uint128 fee;
        uint128 gas_limit;
        uint128 storage_limit;
        string parameters;
    }

    struct OperationShell {
        string branch;
        string[] contents;
        string signature;
        string protocol;
    }

    struct Reveal {
        string source;
        int counter;
        string public_key;
        uint128 fee;
        uint128 gas_limit;
        uint128 storage_limit;
    }

    function wrap_operation(
        OperationShell op
    )
        internal
        pure
        returns(string)
    {
        if(op.contents.length == 0)
            return "";

        string sig = op.signature.empty() ? '':format(',"signature":"{}"', op.signature);
        string proto = op.protocol.empty() ? '':format(',"protocol":"{}"', op.protocol);

        string res = '{' + format('"branch":"{}"', op.branch) + sig + proto + ',"contents":[';
        for(uint i=0; i < op.contents.length; i++) {
            res += op.contents[i] + (i == op.contents.length-1 ? "": ",");
        }
        res += ']}';
        return res;
    }

    function wrap_transaction(
        Transaction t
    )
        internal
        pure
        returns(string)
    {
        // Default values if not set
        uint128 fee = (t.fee > 0) ? t.fee : 5000; // can't be 0
        uint128 gas_limit = (t.gas_limit > 0) ? t.gas_limit : 5000; // can't be 0
        uint128 storage_limit = (t.storage_limit > 0) ? t.storage_limit : 0; // can be 0

        string data = '{' +
            format('"kind":"transaction","source":"{}","fee":"{}","counter":"{}","gas_limit":"{}","storage_limit":"{}","amount":"{}","destination":"{}"',
                t.source, fee, t.counter, gas_limit, storage_limit, t.amount, t.destination);
        if (!t.parameters.empty())
            data += ',"parameters":' + t.parameters;
        return data  + '}';
    }

    function wrap_reveal(Reveal t)
        internal
        pure
        returns(string)
    {
        // Default values if not set
        uint128 fee = (t.fee > 0) ? t.fee : 1300;
        uint128 gas_limit = (t.gas_limit > 0) ? t.gas_limit : 5000;
        uint128 storage_limit = 0; // always 0 for Reveal

        return '{' +
            format('"kind":"reveal","source":"{}","fee":"{}","counter":"{}","gas_limit":"{}","storage_limit":"{}","public_key":"{}"',
                t.source, fee, t.counter, gas_limit, storage_limit, t.public_key) + '}';
    }

    function wrap_fa1_token_transfer(string from, string to, uint128 amount) internal pure returns (string){
        return '{"entrypoint":"transfer","value":{"prim": "Pair","args":[{"string":"' + from +
            '"},{"prim":"Pair","args":[{"string":"' + to + '"},{"int": "' + format("{}", amount) +'"}]}]}}';
    }

    function toFractional(uint128 balance, uint8 decimals) internal view returns (string) {
        uint left_part = balance / uint256(10) ** decimals;
        uint right_part = balance % uint256(10) ** decimals;
        return format("{}.{}", left_part, right_part);
    }

}

abstract contract TezosRPC {

    struct Token {
        string token;
        uint128 balance;
    }

    struct TxResult {
        string op_type; // reveal, transaction, etc.
        string status; // applied, failed
        bool is_success; // true or false
    }

    // default endpoints (can be overridden in the DeBot)
    string shell = "https://hangzhounet.smartpy.io"; // main RCP endpoint
    string api = "https://api.hangzhou2net.tzkt.io"; // required for querying operation status

    string helper_api = "https://api.better-call.dev"; // through this helper API we query the token list
    string helper_netname = "hangzhou2net"; // Network name, used for helper API

    function SetNetwork(string _shell, string _api, string _helper_netname) internal {
        shell = _shell;
        api = _api;
        helper_netname = _helper_netname;
    }

    string[] headers = [
        "Content-Type: application/json"
    ];

    int32 constant ERROR_TIMEOUT = 0;
    int32 constant ERROR_BAD_CODE = 1;
    int32 constant ERROR_INVALID_JSON = 2;
    int32 constant ERROR_UNEXPECTED_CONTENT = 3;

    uint8 constant RPC_BLOCKS_HEAD = 0;
    uint8 constant RPC_CONTRACTS_COUNTER = 1;
    uint8 constant RPC_CONTRACTS_BALANCE = 3;
    uint8 constant RPC_CONTRACTS_KEY = 4;
    uint8 constant RPC_HELPERS_FORGE = 5;
    uint8 constant RPC_PREAPPLY = 6;
    uint8 constant RPC_INJECTION = 7;

    uint8 constant RPC_ACCOUNT_TOKENS = 101;
    uint8 constant RPC_EXPLORER_OP = 201;

    uint8 internal m_request_type;

    string internal m_last_block_hash;
    string internal m_protocol;
    string internal m_forged_hex;
    string internal m_tx_hash;
    int internal m_contract_balance;
    int internal m_contract_counter;

    bool internal m_is_reveled;

    Token[] m_tokens;
    TxResult[] m_opg;

    bool debug = false;
    function DbgPrint(string data) internal { if(debug) Terminal.print(0, data); }

    function _get(uint8 request_type, string url) private {
        DbgPrint(url);
        m_request_type = request_type;
        Network.get(tvm.functionId(onRpcResponse), url, headers);
    }

    function _post(uint8 request_type, string url, string data) private {
        m_request_type = request_type;
        DbgPrint(url);
        DbgPrint(data);
        Network.post(tvm.functionId(onRpcResponse), url, headers, data);
    }

    // API
    function rpc_blocks_hash() internal {
        string url = shell + "/chains/main/blocks/head";
        _get(RPC_BLOCKS_HEAD, url);
    }

    function rpc_contract_counter(string source_address) internal {
        string url = shell + format("/chains/main/blocks/head/context/contracts/{}/counter", source_address);
        _get(RPC_CONTRACTS_COUNTER, url);
    }

    function rpc_contract_balance(string source_address) internal {
        string url = shell + format("/chains/main/blocks/head/context/contracts/{}/balance", source_address);
        _get(RPC_CONTRACTS_BALANCE, url);
    }

    function rpc_contract_key(string source_address) internal {
        string url = shell + format("/chains/main/blocks/head/context/contracts/{}/manager_key", source_address);
        _get(RPC_CONTRACTS_KEY, url);
    }

    function rpc_helpers_forge(string block_hash, string operation) internal {
        string url = shell + format("/chains/main/blocks/{}/helpers/forge/operations", block_hash);
        _post(RPC_HELPERS_FORGE, url, operation);
    }

    function rpc_preapply(string signed_operations) internal {
        string url = shell + "/chains/main/blocks/head/helpers/preapply/operations";
        _post(RPC_PREAPPLY, url, signed_operations);
    }

    function rpc_inject(string hex_string) internal {
        string url = shell + "/injection/operation";
        _post(RPC_INJECTION, url, hex_string);
    }

    // helpers
    function rpc_account_tokens(string source_address) internal {
        string url = helper_api + format("/v1/account/{}/{}/token_balances", helper_netname, source_address);
        _get(RPC_ACCOUNT_TOKENS, url);
    }

    function rpc_explorer_op(string opg_hash) internal {
        string url = api + format("/v1/operations/{}", opg_hash);
        _get(RPC_EXPLORER_OP, url);
    }

    // Callbacks
    function onRpcResponse(int32 statusCode, string[] retHeaders, string content) public {
        DbgPrint(format("onRpcResponse request type: {}, code: {}", m_request_type, statusCode));
        // for operation request the 404 response is also OK
        // It just means that the operation has not been processed yet
        if(statusCode == 404 && m_request_type == RPC_EXPLORER_OP) {
            m_opg = new TxResult[](0);
            DbgPrint("RPC_EXPLORER_OP result 404 (not processed yet)");
            OnCallSuccess();
            return;
        }
        if(statusCode != 200) {
            OnCallError(statusCode, ERROR_BAD_CODE);
            return;
        }

        Json.parse(tvm.functionId(onJsonParse), content);
    }

    function onJsonParse(bool result, JsonLib.Value obj) public {
        if (!result)
            return OnCallError(0, ERROR_INVALID_JSON);

        DbgPrint("Json parse success");

        mapping(uint256 => TvmCell) jsonObj;
        optional(JsonLib.Value) val;

        if (m_request_type == RPC_BLOCKS_HEAD) {
            jsonObj = JsonLib.as_object(obj).get();

            val = JsonLib.get(jsonObj, "hash");
            m_last_block_hash = val.hasValue() ? JsonLib.as_string(val.get()).get() : "";

            val = JsonLib.get(jsonObj, "protocol");
            m_protocol = val.hasValue() ? JsonLib.as_string(val.get()).get() : "";

            if(m_protocol.empty() || m_last_block_hash.empty()) {
                return OnCallError(0, ERROR_UNEXPECTED_CONTENT);
            }
            DbgPrint(format("Block hash: {}", m_last_block_hash));
        }

        else if (m_request_type == RPC_CONTRACTS_COUNTER) {
            optional(string) counter_str;
            counter_str = JsonLib.as_string(obj);
            m_contract_counter = -1;
            if(counter_str.hasValue()) {
                optional(int) counter = stoi(counter_str.get());
                m_contract_counter = counter.hasValue() ? counter.get() : -1;
                DbgPrint(format("Counter: {}", m_contract_counter + 1));
            }
            if(m_contract_counter == -1)
                return OnCallError(0, ERROR_UNEXPECTED_CONTENT);
        }

        else if (m_request_type == RPC_CONTRACTS_BALANCE) {
            optional(string) balance_str;
            balance_str = JsonLib.as_string(obj);
            m_contract_counter = -1;
            if(balance_str.hasValue()) {
                optional(int) balance = stoi(balance_str.get());
                m_contract_balance = balance.hasValue() ? balance.get() : -1;
                DbgPrint(format("Balance: {}", m_contract_balance));
            }
            if(m_contract_balance == -1)
                return OnCallError(0, ERROR_UNEXPECTED_CONTENT);
        }

        else if (m_request_type == RPC_CONTRACTS_KEY) {
            optional(string) manager_key;
            manager_key = JsonLib.as_string(obj);

            if(manager_key.hasValue()) {
                m_is_reveled = true;
                DbgPrint("PubKey is revealed");
            }
            else {
                m_is_reveled = false;
                DbgPrint("PubKey is not revealed");
            }
        }

        else if (m_request_type == RPC_HELPERS_FORGE) {
            optional(string) forged;
            forged = JsonLib.as_string(obj);
            m_forged_hex = forged.hasValue() ? forged.get() : "";
            DbgPrint("Forged: ");
            DbgPrint(m_forged_hex);
            if(m_forged_hex.empty())
                return OnCallError(0, ERROR_UNEXPECTED_CONTENT);
        }

        else if (m_request_type == RPC_INJECTION) {
            optional(string) tx_hash;
            tx_hash = JsonLib.as_string(obj);
            m_tx_hash = tx_hash.hasValue() ? tx_hash.get() : "";
            if(m_tx_hash.empty())
                return OnCallError(0, ERROR_UNEXPECTED_CONTENT);
        }

        else if (m_request_type == RPC_ACCOUNT_TOKENS) {
            //{"balances":[{"contract":"KT1DGQQWWBiVrnowxSBo9voDjDba9kSQng6W","network":"hangzhou2net","token_id":0,"balance":"222"}],"total":1}
            jsonObj = JsonLib.as_object(obj).get();
            JsonLib.Cell[] balances;

            string token_addr;
            string tmp;
            int balance;

            m_tokens = new Token[](0);

            val = JsonLib.get(jsonObj, "balances");
            if(val.hasValue()) {
                balances = JsonLib.as_array(val.get()).get();

                for(uint32 i = 0; i < balances.length; i++) {
                    DbgPrint(format("Entry {}" , i));
                    TvmCell cell = balances[i].cell;
                    optional(JsonLib.Value) entry = JsonLib.decodeArrayValue(cell);
                    if(!entry.hasValue()) {
                        DbgPrint("Error decoding array value");
                        break;
                    }

                    jsonObj = JsonLib.as_object(entry.get()).get();

                    val = JsonLib.get(jsonObj, "contract");
                    if(!val.hasValue()) {
                        DbgPrint("Error reading 'contract' value");
                        continue;
                    }
                    token_addr = JsonLib.as_string(val.get()).get();

                    val = JsonLib.get(jsonObj, "balance");
                    tmp = val.hasValue() ? JsonLib.as_string(val.get()).get() : "0";
                    optional(int) balance_val = stoi(tmp);
                    balance = balance_val.hasValue() ? balance_val.get() : 0;

                    DbgPrint(format("{}: {}", token_addr, balance));
                    if(balance < 0)
                        balance = 1; // TODO: fixme: if balance < 0 this means that the address is the contract
                                     // owner (minter) and has transferred the tokens.

                    m_tokens.push(Token(token_addr, uint128(balance)));
                }
            }
            else {
                OnCallError(0, ERROR_UNEXPECTED_CONTENT);
                return;
            }
        }

        else if(m_request_type == RPC_EXPLORER_OP) {
            // [{"type":"reveal","status":"applied","is_success":true}, ...],
            m_opg = new TxResult[](0);
            optional(JsonLib.Cell[]) tmp_ops;
            JsonLib.Cell[] ops;

            DbgPrint("RPC_EXPLORER_OP parsing object as array...");

            tmp_ops = JsonLib.as_array(obj).get();
            if(!tmp_ops.hasValue()) {
                OnCallError(0, ERROR_UNEXPECTED_CONTENT);
            }

            ops = tmp_ops.get();
            DbgPrint(format("Found {} operations", ops.length));

            for(uint32 i=0; i < ops.length; i++) {
                TvmCell cell = ops[i].cell;
                optional(JsonLib.Value) entry = JsonLib.decodeArrayValue(cell);
                if(!entry.hasValue()) {
                    DbgPrint("Error decoding array value");
                    break;
                }

                TxResult r;
                jsonObj = JsonLib.as_object(entry.get()).get();

                val = JsonLib.get(jsonObj, "type");
                r.op_type = val.hasValue() ? JsonLib.as_string(val.get()).get() : "";

                val = JsonLib.get(jsonObj, "status");
                r.status = val.hasValue() ? JsonLib.as_string(val.get()).get() : "";

                r.is_success = r.status == "applied" ? true : false;

                m_opg.push(r);
            }
        }

        OnCallSuccess();
    }

    function OnCallSuccess() internal virtual;
    function OnCallError(int32 status_code, int32 error_code) internal virtual;

}
