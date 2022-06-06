pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

// Testnet address: 0:c36c8a6edd7d446ada4f3de43c2fa20c101c7223f17c56d16ba39a30dcea6f54

import "./interfaces/Debot.sol";
import "./interfaces/Menu.sol";
import "./interfaces/Terminal.sol";
import "./interfaces/Media.sol";
import "./interfaces/AddressInput.sol";
import "./interfaces/ConfirmInput.sol";
import "./interfaces/AmountInput.sol";
import "./interfaces/NumberInput.sol";
import "./interfaces/QRCode.sol";

import "./lib/TezosRPC.sol";
import "./lib/TezosClient.sol";


library MenuId {
    uint32 constant FAUCET = 0;
    uint32 constant BALANCE = 1;
    uint32 constant TRANSFER = 2;
    uint32 constant TOKENS = 3;
    uint32 constant SETTINGS = 4;

    uint32 constant TOKENS_UPDATE = 0;
    uint32 constant TOKENS_TRANSFER = 1;
    uint32 constant TOKENS_BACK = 2;

    uint32 constant ADDRESS_ENTER = 0;
    uint32 constant ADDRESS_SCAN = 1;
    uint32 constant ADDRESS_PREDEFINED = 2;
    uint32 constant ADDRESS_CANCEL = 3;

    uint32 constant SETTINGS_FEE = 0;
    uint32 constant SETTINGS_NETWORK = 1;
    uint32 constant SETTINGS_FAUCET = 2;
}

library Reason {
    uint32 constant UPDATE_BALANCE = 0;
    uint32 constant TRANSFER = 1;
    uint32 constant CHANGE_NETWORK = 2;
}

interface IFaucet {
     function start() external;
}

contract Bot is Debot, TezosClient {

    struct NetworkInfo {
        string name;
        string shell;
        string helper_name;
        string api;
    }

    NetworkInfo[] m_networks;
    uint32 private m_selected_network_id = 0;

    string private m_icon;
    string private m_logo;

    address m_faucet_address;

    // is set to true if we transfer tokens
    bool private m_transfer_tokens = false;
    string constant menu_faucet = "🚰 Faucet (Hangzhou only)";

    uint8 constant DEFAULT_DIGITS = 6;

    constructor() public {
        tvm.accept();

        NetworkInfo ep;
        ep.name = "ithacanet @smartpy.io";
        ep.shell = "https://ithacanet.smartpy.io";
        ep.api = "https://api.ithacanet.tzkt.io";
        ep.helper_name = "ithacanet";
        m_networks.push(ep);

        ep.name = "hangzhou @testnets.xyz";
        ep.shell = "https://rpc.hangzhounet.teztnets.xyz";
        ep.api = "https://api.hangzhou2net.tzkt.io";
        ep.helper_name = "hangzhou2net";
        m_networks.push(ep);
    }

    function setIcon(string icon) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        m_icon = icon;
    }

    function setLogo(string logo) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        m_logo = logo;
    }

    function setFaucetAddress(address faucet) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        m_faucet_address = faucet;
    }

    function start() public override {
        debug = false;
        NetworkInfo n = m_networks[0];
        SetNetwork(n.shell, n.api, n.helper_name);

        Media.output(0, "", m_logo);

        InitClient();
    }

    function CallFaucet() internal {
        if(m_faucet_address != address(0) && m_selected_network_id <= 1)
            IFaucet(m_faucet_address).start();
        else {
            // No faucet
            Continue(0);
        }
    }

    function OnFaucetExit() public {
        UpdateBalance(Reason.UPDATE_BALANCE);
    }

    function SelectNetwork(NetworkInfo network) internal {
        shell = network.shell;
        helper_netname = network.name;
    }

    function OnInitClient() internal override {
        UpdateBalance(Reason.UPDATE_BALANCE);
    }

    bool m_faucet_enabled = false;
    function ShowMainMenu() internal {
        m_faucet_enabled = false;
        Terminal.print(0, format("📶 Network: {}", m_networks[m_selected_network_id].name));
        Terminal.print(0, "Your ꜩ wallet:");
        QRCode.draw(0, "", GetAddress());
        Terminal.print(0, GetAddress());
        string message = format("💰 Balance: {} ꜩ", toFractional(GetBalance(), DEFAULT_DIGITS));

        MenuItem[] menuItems;
        if(m_faucet_address != address(0) && GetBalance() == 0 && !IsRevealed() && m_selected_network_id <= 1) {
            m_faucet_enabled = true;
            menuItems.push(MenuItem(menu_faucet, "", tvm.functionId(MainMenuHandler)));
            message += "\nYou don't have any ꜩ.\nUse 🚰 Faucet to replenish you account.";
        }
        menuItems.push(MenuItem("🔄 Update balance", "", tvm.functionId(MainMenuHandler)));
        menuItems.push(MenuItem("📤 Transfer ꜩ", "", tvm.functionId(MainMenuHandler)));
        menuItems.push(MenuItem("🏷️ Tokens", "", tvm.functionId(MainMenuHandler)));
        menuItems.push(MenuItem("⚙️ Options", "", tvm.functionId(MainMenuHandler)));
        Menu.select(message, "", menuItems);
    }

    function ShowSettingsMenu() internal {
        Terminal.print(0, "You can view the transaction log here:");
        Terminal.print(0, format("https://{}.tzkt.io/{}", helper_netname, GetAddress()));
        Menu.select(
            "Settings",
            "",
            [
                MenuItem(format("⚙ Transaction Fee: {}", toFractional(m_fee, DEFAULT_DIGITS)), "", tvm.functionId(SettingsMenuHandler)),
                MenuItem("🌐 Network", "", tvm.functionId(SettingsMenuHandler)),
                MenuItem(menu_faucet, "", tvm.functionId(SettingsMenuHandler)),
                MenuItem("Back", "", tvm.functionId(Continue))
            ]
        );
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

    function Continue(uint32 index) public {
        UpdateBalance(Reason.UPDATE_BALANCE);
    }

    function ShowChoseNetworkMenu() internal {
        MenuItem[] items;
        for(uint32 i = 0; i < m_networks.length; i++) {
            items.push(MenuItem(m_networks[i].name, "", tvm.functionId(ChooseNetwork)));
        }
        Menu.select("Choose network:", "", items);
    }

    function ChooseNetwork(uint32 index) public {
        if(index > m_networks.length) {
            ShowMainMenu();
            return;
        }

        m_selected_network_id = index;
        NetworkInfo n = m_networks[index];
        SetNetwork(n.shell, n.api, n.helper_name);
        UpdateBalance(Reason.UPDATE_BALANCE);
    }

    function MainMenuHandler(uint32 index) public {
        if(!m_faucet_enabled)
            index ++;

        if(index == MenuId.FAUCET) {
            CallFaucet();
        }
        else if(index == MenuId.BALANCE) {
            UpdateBalance(Reason.UPDATE_BALANCE);
        }
        else if(index == MenuId.TRANSFER) {
            m_transfer_tokens = false;
            UpdateBalance(Reason.TRANSFER);
        }
        else if(index == MenuId.TOKENS) {
            UpdateTokens();
        }
        else if(index == MenuId.SETTINGS) {
            ShowSettingsMenu();
        }
    }

    function SettingsMenuHandler(uint32 index) public {
        if(index == MenuId.SETTINGS_FEE) {
            AmountInput.get(tvm.functionId(setFee), "Enter amount:",  DEFAULT_DIGITS, 0, 1000000);
        }
        else if(index == MenuId.SETTINGS_NETWORK) {
            ShowChoseNetworkMenu();
        }
        else if(index == MenuId.SETTINGS_FAUCET) {
            CallFaucet();
        }
    }

    function setFee(uint128 value) public {
        m_fee = value;
        Continue(0);
    }

    function transferAskAmount(uint8 decimals, uint128 max_balance) internal {
        AmountInput.get(tvm.functionId(transferSetAmount), "Enter amount:",  decimals, 1, max_balance);
    }

    uint128 private m_transfer_amount;
    function transferSetAmount(uint128 value) public {
        m_transfer_amount = value;

        Menu.select(
            "Choose destination address:",
            "",
            [
                MenuItem("📝 Enter manually", "", tvm.functionId(AddressMenuHandler)),
                MenuItem("📷 Scan QR-code", "", tvm.functionId(AddressMenuHandler)),
                MenuItem("Predefined address (for test)", "", tvm.functionId(AddressMenuHandler)),
                MenuItem("Cancel", "", tvm.functionId(AddressMenuHandler))
            ]
        );
    }

    function AddressMenuHandler(uint32 index) public {
        if(index == MenuId.ADDRESS_ENTER) {
            Terminal.input(tvm.functionId(transferSetAddress), "Enter address:", false);
        }
        if(index == MenuId.ADDRESS_SCAN) {
            QRCode.read(tvm.functionId(onScanQR), "");
        }
        if(index == MenuId.ADDRESS_PREDEFINED) {
            transferSetAddress("tz1QyBtJr8dPLQBaCLBYKTYQ56CWzSi9s5PL");
        }
        if(index == MenuId.ADDRESS_CANCEL)
            ShowMainMenu();
    }

    function onScanQR(string value, QRStatus result) public {
        if (result != QRStatus.Success) {
            Terminal.print(0, "Failed to scan QRCode.");
            ShowMainMenu();
            return;
        }

        transferSetAddress(value);
    }

    function transferSetAddress(string value) public {
        if(value.substr(0,2) == "tz" && value.byteLength() > 10) {
            Terminal.print(0, format("Transferring to {}", value));
            if(m_transfer_tokens)
                TransferTokens(m_chosen_token.token, value, m_transfer_amount);
            else
                Transfer(value, m_transfer_amount);
        }
        else {
            Terminal.print(0, "You have entered invalid Tezos address\nAddress should start with tz1, tz2 or tz3");
            ShowMainMenu();
        }
    }

    function OnUpdateBalance(uint32 reason) internal override {
        if(reason == Reason.UPDATE_BALANCE) {
            ShowMainMenu();
        }
        else if(reason == Reason.TRANSFER) {
            uint128 fee = CalcFee(Fee.TEZ_TRANSFER_FEE);
            if(GetBalance() > fee) {
                transferAskAmount(DEFAULT_DIGITS, GetBalance() - fee);
            }
            else {
                Terminal.print(0, "Too low balance, nothing to transfer");
                ShowMainMenu();
            }
        }
    }

    function OnTransferSuccess(string tx_hash) internal override {
        Terminal.print(0, format("https://{}.tzkt.io/{}", helper_netname, tx_hash));
        ShowTxSuccessMenu("💸 Transaction sent!");
    }

    function OnTransferFailed(uint32 step, int32 code) internal override {
        string[] errors = [
            "Address calculation failed",
            "Update balance failed",
            "Get head block failed",
            "Get contract counter failed",
            "Forge failed",
            "Signing failed",
            "Transaction verification (preapply) failed",
            "Inject failed"
        ];
        string error = "Unknown";
        if (step < errors.length)
            error = errors[step];

        string message = format("Transaction failed with error:\n{}\nCode: {}", error, code);
        ShowButtonContinue(message);
    }

    function OnUpdateTokens() internal override {
        Token[] tokens = GetTokens();

        for(uint32 i=0;i<tokens.length;i++) {
            Terminal.print(0, format("🏷️Token [{}]: {}\nBalance: {}", i+1,
                tokens[i].token, toFractional(tokens[i].balance, DEFAULT_DIGITS)));
        }
        string message = "Notice: We don't request token metadata, therefore we use 6 digits after the decimal point as a default value.";
        if(tokens.length == 0)
            message = "You don't have any FA tokens";

        Menu.select(
            message,
            "",
            [
                MenuItem("🔄 Update", "", tvm.functionId(TokensMenuHandler)),
                MenuItem("📤 Transfer tokens", "", tvm.functionId(TokensMenuHandler)),
                MenuItem("Back", "", tvm.functionId(Continue))
            ]
        );
    }

    function TokensMenuHandler(uint32 index) public {
        if(index == MenuId.TOKENS_UPDATE) {
            UpdateTokens();
        }
        else if(index == MenuId.TOKENS_TRANSFER) {
            if(GetBalance() < CalcFee(Fee.TOKEN_TRANSFER_FEE)) {
                ShowButtonContinue("Too low TEZ balance");
                return;
            }
            Token[] tokens = GetTokens();
            if(tokens.length > 0) {
                MenuItem[] items;
                for(uint32 i=0;i<tokens.length;i++) {
                    items.push(MenuItem(format("Token [{}] - {}", i+1, toFractional(tokens[i].balance, DEFAULT_DIGITS)),
                                "", tvm.functionId(ChooseToken)) );
                }
                Menu.select("Choose token", "", items);
            }
            else {
                Terminal.print(0, "You don't have any tokens");
                UpdateTokens();
            }
        }
    }

    Token m_chosen_token;
    function ChooseToken(uint32 index) public {
        Token[] tokens = GetTokens();
        m_transfer_tokens = true;
        m_chosen_token = GetTokens()[index];
        if(m_chosen_token.balance > 0)
            transferAskAmount(DEFAULT_DIGITS, m_chosen_token.balance);
        else {
            Terminal.print(0, "You balance is 0, nothing to transfer");
            UpdateTokens();
        }
    }

    function CalcFee(uint128 op_fee) internal returns(uint128){
        return (IsRevealed() ? 0 : Fee.REVEAL_FEE + m_fee) + op_fee + m_fee;
    }

    function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Hex.ID, SigningBoxInput.ID, UserInfo.ID ];
    }

    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Devergence Wallet";
        version = "0.1.0";
        publisher = "DEvergence team";
        key = "For Tezos DeFi hackathon 2022";
        author = "DEvergence team";
        support = address.makeAddrStd(0, 0);
        hello = "This DeBot enables you to control your Tezos wallet";
        language = "en";
        dabi = m_debotAbi.get();
        icon = m_icon;
    }

    function toFractional(uint128 balance, uint8 decimals) internal view returns (string) {
        uint256 pow = uint256(10) ** decimals;
        uint left_part = balance / pow;
        uint right_part = pow + balance % pow;
        bytes low_part = format("{}", right_part)[1:];
        return format("{}.{}", left_part, low_part);
    }

}
