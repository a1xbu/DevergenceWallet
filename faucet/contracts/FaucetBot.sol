pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "./../../interfaces/Debot.sol";
import "./../../interfaces/Menu.sol";
import "./../../interfaces/Terminal.sol";
import "./../../interfaces/AddressInput.sol";
import "./../../interfaces/AddressInput.sol";

import "./../../lib/TezosRPC.sol";
import "./../../lib/TezosClient.sol";

import "./Faucet.sol";
import "./User.sol";

interface IWalletBot {
    function OnFaucetExit() external;
}

contract Bot is Debot, TezosClient {

    address m_faucet;
    uint128 m_faucet_balance;
    uint128 m_faucet_contract_balance;
    address m_user_address;
    address m_surf_address;
    bool m_is_deployed;

    uint m_last_op_id;

    address parent;

    constructor() public {
        tvm.accept();
    }

    function setFaucetAddress(address faucet) public {
        tvm.accept();
        m_faucet = faucet;
    }

    function start() public override {
        parent = msg.sender;
        UserInfo.getAccount(tvm.functionId(Init_Account));
        //AddressInput.get(tvm.functionId(Init_Account), "Please provide wallet address");
    }

    function Init_Account(address value) public {
        m_surf_address = value;
        UserInfo.getPublicKey(tvm.functionId(Init_Pubkey));
    }

    function Init_Pubkey(uint256 value) public {
        m_pubkey = value;
        _getUserAddress(tvm.functionId(Init_UserAddress));
    }

    function Init_UserAddress(address user_address, uint128 tezos_faucet_balance, uint128 contract_balance) public {
        m_user_address = user_address;
        m_faucet_balance = tezos_faucet_balance;
        m_faucet_contract_balance = contract_balance;
        Sdk.getAccountType(tvm.functionId(Init_IsDeployed), user_address);
    }

    function Init_IsDeployed(int8 acc_type) public {
        if ((acc_type==-1)||(acc_type==0))
            m_is_deployed = false;
        else
            m_is_deployed = true;
        Terminal.print(0, format("💰 Faucet balance:\nEVER: {}\nTEZ: {}",
            toFractional(m_faucet_contract_balance, 9), toFractional(m_faucet_balance, 6)));
        if(m_faucet_balance < 10000000 || m_faucet_contract_balance < 2 ton) {
            ShowButtonContinue("Sorry, we can't continue because the faucet is almost empty.");
            return;
        }
        Terminal.print(tvm.functionId(claim_tokens), "Now we will ask you to sign a message. "+
            "This is a cross-chain operation that may take up to 60 seconds. Please be patient.");
    }

    function claim_tokens() public {
        optional(uint256) pubkey = 0;
        TezosFaucet(m_faucet).claim{
            sign: true,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setLastOpId),
            onErrorId: tvm.functionId(onError)
        }(!m_is_deployed, m_surf_address).extMsg;
    }

    function setLastOpId(uint op_id) public {
        m_last_op_id = op_id;
        timestamp = now;
        waitDeploy();
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        sdkError;
        exitCode;
        ShowButtonContinue("Aborted");
    }

    uint64 timestamp;
    function waitDeploy() public  {
        Sdk.getAccountType(tvm.functionId(checkIfStatusIs0), m_user_address);
    }

    uint32 m_wait_attempts;
    function checkIfStatusIs0(int8 acc_type) public {
        if ((acc_type==-1)||(acc_type==0)) {
            if(now - timestamp > 30) {
                ShowButtonContinue("Timeout. The faucet contract is likely out of gas, sorry :(");
                return;
            }
            else
                waitDeploy();
        } else {
            m_wait_attempts = 0;
            timestamp = now;
            Terminal.print(tvm.functionId(waitTokens), "Tokens requested. Waiting for the Ever-Tezos faucet relay...");
        }
    }

    function waitTokens() public {
        m_wait_attempts ++;
        _getLastOps(tvm.functionId(OnGetLastOp));
    }

    function OnGetLastOp(User.Op[] claims) public {
        if(now - timestamp > 40) {
            ShowButtonContinue("Wait timeout. The relay is likely offline. We are sorry :(");
            return;
        }

        if(claims.empty()) {
            waitTokens();
            return;
        }
        else {
            User.Op claim = claims[0];
            if(claim.claim_id != m_last_op_id) {
                waitTokens();
                return;
            }
            else {
                m_tx_hash = claim.op_hash;
                Terminal.print(0, format("https://hangzhou2net.tzkt.io/{}", m_tx_hash));
                UpdateTxResult();
            }
        }
    }

    function OnUpdateTxResult(TxResult[] opg) internal override {
        if(opg.length == 0) {
            ShowTxSuccessMenu("⏳ Transaction has not been accepted yet, please wait!");
            return;
        }

        bool is_success = true;
        for(uint32 i = 0; i < opg.length; i++) {
            TxResult tx_result = opg[i];
            is_success = is_success && tx_result.is_success;
            string status = tx_result.is_success ? "✅" : "❌";
            Terminal.print(0, format("Operation: {}\n{} Status: {}", tx_result.op_type, status, tx_result.status));
        }

        ShowButtonContinue(is_success ? "✅ Success!" : "❌ One or more operations have not been applied");
    }

    function ShowButtonContinue(string message) internal {
        Menu.select(message, "", [MenuItem("Continue", "", tvm.functionId(Continue))]);
    }

    function ShowTxSuccessMenu(string message) internal {
        Menu.select(message, "", [
            MenuItem("🔄 Check transaction result", "", tvm.functionId(CheckTxResult)),
            MenuItem("Continue", "", tvm.functionId(Continue))
        ]);
    }

    function CheckTxResult(uint32 index) public {
        UpdateTxResult();
    }

    function Continue(uint32 index) public {
        IWalletBot(parent).OnFaucetExit();
    }

    function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Hex.ID, SigningBoxInput.ID, UserInfo.ID, AddressInput.ID ];
    }

    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "DEvergence ꜩ Faucet";
        version = "0.1.0";
        publisher = "DEvergence";
        key = "";
        author = "DEvergence";
        support = address.makeAddrStd(0, 0);
        hello = "Tezos faucet gateway DeBot";
        language = "en";
        dabi = m_debotAbi.get();
        icon = "";
    }

    function _getUserAddress(uint32 function_id) private {
        optional(uint256) pubkey;
        TezosFaucet(m_faucet).GetFaucetInfo{
            abiVer: 2,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: function_id,
            onErrorId: 0
        }(m_pubkey).extMsg;
    }

    function _getLastOps(uint32 function_id) private {
        optional(uint256) pubkey;
        User(m_user_address).GetLastOps{
            abiVer: 2,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: function_id,
            onErrorId: 0
        }(1).extMsg;
    }

    function OnTransferFailed(uint32, int32) internal override {}
    function OnTransferSuccess(string) internal override {}
    function OnInitClient() internal override {}
    function OnUpdateBalance(uint32) internal override {}
    function OnUpdateTokens() internal override {}

    function toFractional(uint128 balance, uint8 decimals) internal view returns (string) {
        uint256 pow = uint256(10) ** decimals;
        uint left_part = balance / pow;
        uint right_part = pow + balance % pow;
        bytes low_part = format("{}", right_part)[1:];
        return format("{}.{}", left_part, low_part);
    }
}
