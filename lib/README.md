# Tezos client abstract contracts and libraries

Contents:
1. [Overview](#overview)
    * [Sending a transaction](#sending-a-transaction)
    * [Reveal a public key](#reveal-a-public-key)
    * [Transfer tokens](#transfer-tokens)
2. [TezosRPC](#tezosrpc)
    * [TezosJson library](#tezosjson-library)
    * [TezosRPC abstract contract](#tezosrpc-abstract-contract)
3. [TezosClient](#tezosclient)
    * [TezosClient abstract contract](#tezosrpc-abstract-contract)
4. [References](#references)

## Overview

Tezos nodes support JSON RPC protocol to work with the blockchain. The libraries and contracts
in this folder implement interaction with several Tezos RPC endpoints that are required to send
transactions and get transaction results.
We also implemented interaction with [tzkt.io API](https://api.tzkt.io/) to simplify some operations.

### Sending a transaction

In order to send a transaction, the following steps should be performed:

#### 1. Obtain the hash of the most recent block and the protocol

API: `/chains/main/blocks/head`

Result example (partial):
```python
{
    "protocol": "PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx",
    "hash": "BL4ipq36umtZDJ64Z1TrcazzNW2iAmfwpkC84iNsJRRvXS9Gwow",
    # ...
}
```

#### 2. Obtain the counter value for the source address
Every operation includes a counter value as a protection mechanism against replay-attacks. 
The current counter value can be fetched from the RPC and incremented by one when creating a new operation.

API: `/chains/main/blocks/head/context/contracts/{address}/counter`

#### 3. Prepare operation

A transaction operation looks as follows:
```json
{
    "kind": "transaction",
    "source": "tz1RTwGzB5FZ3zsn...",
    "fee": "417",
    "counter": "3235570",
    "gas_limit": "1620",
    "storage_limit": "257",
    "amount": "123456",
    "destination": "tz1LUMF951YtT9F7..."
}
```

The operation has the following fields:
* `kind` - in our case it is a `transaction` operation. There are also `reveal`, `origination`, and `delegaction`
operations kinds.
* `source` - the address we want to transfer the funds from.
* `fee` -  operation fee (1 TEZ = 10^6).
* `counter` - the counter value obtained on the previous step + 1.
* `gas_limit` and `storage_limit` - upper limit on how much gas and storage the operation is allowed to use.
* `amount` - transfer operation amount (1 TEZ = 10^6).
* `destination` - address of the recipient.

> Notice: `gas_limit` and `storage_limit` can be adjusted after simulating the operation 
> with `/chains/main/blocks/head/helpers/scripts/run_operation`. This is not implemented yet in the DeBot.

#### 4. Wrap operation into a shell

Before sending operation it should be wrapped into a shell. The sell may contain several operations - operation
group. At this step we don't sign the operation yet.

```json
{
    "branch": "BMGLQmxzH14ypS2nQAekGf1zQ...",
    "contents": [
        {
            "kind": "transaction",
            "source": "tz1RTwGzB5FZ3zsn...",
            "fee": "417",
            "counter": "3235570",
            "gas_limit": "1620",
            "storage_limit": "257",
            "amount": "123456",
            "destination": "tz1LUMF951YtT9F7..."
        }
    ]
}
```

The operation shell contains the following fields:
* `branch` - the hash of the most recent block obtained on the 1st step. 
If a branch is older than 50 blocks (minutes) the operations will be rejected by the nodes.
* `contents` - the list of operations.

#### 5. Forge operation

Forging means encoding the operation into its binary representations. We can use the following API
to perform forge remotely:

API: `/chains/main/blocks/{block_hash}/helpers/forge/operations`

It returns a HEX-string containing the forged operation, for example: 

```
df5b9aba99602bd01392bb4c977ace2e2c42fd3dcabb3608f1063f9909e4f3ff6c003fe812efa3c6f1ef9c99379f23224d2f5ea04426a103ecbdc501d40c810280ad4b0000092373e1c82e744579c79a1cb645773dff0a8ba600
```

#### 6. Signing

Before signing the operation bytes a watermark prefix must be appended. 
For regular operations used in a wallet this prefix will be 0x03. Operations associated to 
baking will have a different prefix. 

After the watermark have been added, Everscale DeBot calculates 32-byte `blake2b` hash.
Then the hash can be signed with the private key using Sdk.

```solidity
    // ...
    function _transfer() {
        // ...
        bytes forged = "\x03";
        forged.append(forged_binary);
        Blake2b.digest(tvm.functionId(OnTxHash), forged, 32);
    }

    function OnTxHash(uint256 hash) public {
        Sdk.signHash(tvm.functionId(setSignature), m_sbHandle, hash);
    }
```

#### 7. Pre-apply

In order to validate if the signed operation is correct and the signature is valid we do pre-apply.
This function simulates the prepared and signed operation.

API: `/chains/main/blocks/head/helpers/preapply/operations`

We should send the data in the following form:
```json
{
    "branch": "BMGLQmxzH14ypS2nQAekGf1zQ...",
    "contents": [
        {
            "kind": "transaction",
            "source": "tz1RTwGzB5FZ3zsn...",
            "fee": "417",
            "counter": "3235570",
            "gas_limit": "1620",
            "storage_limit": "257",
            "amount": "123456",
            "destination": "tz1LUMF951YtT9F7..."
        }
    ],
    "signature": "edsigtiQk75FA6EsGm5KghyiL...",
    "protocol": "PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx"
}
```

Except the fields we had on the step 4, the 2 new fields are added:
* `signature` - base58-encoded signature obtained on the previous step.
* `protocol` - obtained on the step 1.

#### 8. Inject

Finally we can inject the operation. To do this we use binary representation of the signed operation (forged operation).
The binary signature is appended to the operation. The result is then hex-encoded and is sent to the API endpoint.

API: `/injection/operation`


### Reveal a public key

Tezos address is a base-58 encoded public key of the wallet.
If the Tezos address was never used, the corresponding public key for this address in unknown.
Therefore, prior sending a transaction we should reveal the public key. We can reveal the public
key in the same operation group in which we send a transaction:

```json
{
    "branch":"BLq7KK9murEQzKQaD5NTeghcQh7R4hm3Qos2...",
    "contents":[
        {
            "kind":"reveal",
            "source":"tz1RTwGzB5FZ3zsn...",
            "fee":"980",
            "counter":"3442962",
            "gas_limit":"1100",
            "storage_limit":"0",
            "public_key":"edpktvTb8qhiajeAb7LfhiZ19Y6srKycjE48..."
        },
        {
            "kind":"transaction",
            "source":"tz1RTwGzB5FZ3zsn...",
            "fee":"606",
            "counter":"3442963",
            "gas_limit":"1520",
            "storage_limit":"0",
            "amount":"1000000",
            "destination":"tz1LUMF951YtT9F7..."
        }
    ]
}
```


### Transfer tokens

The token transfer is an operation of the `transaction` kind.
The `destination` field is set to the token contract address.
A new field `parameters` is added, which contains the function name to call (`transfer` in the example below)
and the arguments: from, to, value.

```json
{
    "kind": "transaction",
    "source": "tz1RTwGzB5FZ3zsn...",
    "fee": "987",
    "counter": "3235596",
    "gas_limit": "3943",
    "storage_limit": "75",
    "amount": "0",
    "destination": "KT1DGQQWWBiVrnowx...",
    "parameters": {
        "entrypoint": "transfer",
        "value": {
            "prim": "Pair",
            "args": [
                {
                    "string": "tz1RTwGzB5FZ3zsn..."
                },
                {
                    "prim": "Pair",
                    "args": [
                        {
                            "string": "tz1LUMF951YtT9F7ap..."
                        },
                        {
                            "int": "100"
                        }
                    ]
                }
            ]
        }
    }
}
```


### TezosRPC

[TezosRPC.sol](TezosRPC.sol)

#### TezosJson library
Implements wrapping of Tezos operations into JSON format.

##### Structures:

```solidity
struct OperationShell {
    string branch;
    string[] contents;
    string signature;
    string protocol;
}
```
Fields:
* `branch` - hash of the most recent block
* `signature` - (*optional*) base58-encoded signature of the operations 
* `protocol` - (*optional*) protocol string obtained through `/chains/main/blocks/head`
* `contents` - the list of operations in Json format


```solidity
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
```

Fields:
* `source` - source Tezos address
* `destination` - destination Tezos address
* `amount` - amount to transfer
* `counter` - counter for the replay protection
* `fee` - transaction fee
* `gas_limit` - upper limit on how much gas is allowed to use
* `storage_limit` - upper limit on how much and storage is allowed to used
* `parameters` - (*optional*) list of parameters in Json format (used for calling a smart contract)


```solidity
struct Reveal {
    string source;
    int counter;
    string public_key;
    uint128 fee;
    uint128 gas_limit;
    uint128 storage_limit;
}
```

Fields:
* `source` - source Tezos address
* `counter` - counter for the replay protection
* `public_key` - base58-encoded public key (example: `edpktvTb8qhiajeAb7LfhiZ19Y6srKycjE48...`)
* `fee` - transaction fee
* `gas_limit` - upper limit on how much gas is allowed to use
* `storage_limit` - upper limit on how much and storage is allowed to used



##### Functions:

* `wrap_operation` - wraps one or several operations into a shell

arguments:

    op: OperationShell - structure containing the list of operations

returns:

    string - the wrapped operations in Json format
     
     
     
* `wrap_transaction` - produces Json string from the `Transaction` structure

arguments:

    t: Transaction - structure containing the transaction data

returns:

    string - transaction operation in Json format


* `wrap_reveal` - produces Json string from the `Reveal` structure

arguments:

    r: Reveal - structure containing the transaction data

returns:

    string - reveal operation in Json format
    

#### TezosRPC abstract contract
Implements interaction with a Tezos node and helpers though Json RPC API.
Each function is asynchronous. The result is returned to one of the callbacks: `OnCallSuccess`, `OnCallError`
The `hangzhou` network is used by default.

##### Functions:

* `SetNetwork(string _shell, string _api, string _helper_netname)`

    Description: set network configuration
    
    arguments:
    
        _shell: string - node RPC endpoint
        _api: string - tzkt.io helper API RPC endpoint, for example "https://api.hangzhou2net.tzkt.io"
        _helper_netname: string - network name used in some API calls, for example "hangzhou2net"

* `rpc_blocks_hash()`

    API: `/chains/main/blocks/head`

    Description: get the recent block hash and the protocol


* `rpc_contract_counter(string source_address)`

    API: `/chains/main/blocks/head/context/contracts/{}/counter`

    Description: get the last counter value for replay protection


* `rpc_contract_balance(string source_address)`
    
    API: `/chains/main/blocks/head/context/contracts/{}/balance"`

    Description: get account balance
    

* `rpc_contract_key(string source_address)`

    API: `/chains/main/blocks/head/context/contracts/{}/manager_key"`
        
    Description: get account public key (to check if the public key should be revealed)


* `rpc_helpers_forge(string block_hash, string operation)`

    API: `/chains/main/blocks/{}/helpers/forge/operations`
    
    Description: forge operation (convert from Json to binary form)
    

* `rpc_preapply(string signed_operations)`
 
    API: `/chains/main/blocks/head/helpers/preapply/operations`
    
    Description: simulate signed operations


* `rpc_inject(string hex_string)`

    API: `/injection/operation`
    
    Description: inject operations
    

##### Callbacks:

In order to receive API call results you should implement the following callback functions in your contract:

```solidity
function OnCallSuccess() internal override {
    //...
}
```

```solidity
function OnCallError(int32 status_code, int32 error_code) internal override {
    // ...
}
```
    

### TezosClient

[TezosClient.sol](TezosClient.sol)

#### TezosClient abstract contract

The `TezosClient` abstract contract extends the `TezosRPC` contract and implements sequences of actions
that are required to send a transaction, reveal operation, and transfer tokens.

Inheriting this contract enables your DeBot to easily communicate with the Tezos blockchain.

##### Functions

*Asynchronous functions*:


* `InitClient()` - obtain the default public key and calculates Tezos address

    Callback: `function OnInitClient() internal override {}`

* `UpdateBalance(uint32 reason)` - update Tezos wallet balance. You should call this function after `InitClient()`.
Arguments: `reason` - the value returned to the callback function when the balance is updated.

    Callback: `function OnUpdateBalance(uint32 reason) internal override {}`

* `UpdateTokens()` - updates the list of tokens that belongs to this wallet

    Callback: `function OnUpdateTokens() internal override {}`
    
* `UpdateTxResult()` - check last operation group results

    Callback: `function OnUpdateTxResult(TxResult[] opg) internal override{}`


The next 2 functions have common callback functions for success and failure cases:

* `Transfer(string destination, uint128 amount)` - transfer `amount` of TEZ to `destination`
* `TransferTokens(string token_address, string destination, uint128 amount)` - transfer `amount` of 
token with `token_address` to `destination`

    Success Callback: `function OnTransferSuccess(string tx_hash) internal override {}`
    Failure Callback: `function OnTransferFailed(uint32 step, int32 code) internal override {}`


*Synchronous functions*:

The functions below just return the values obtained by the asynchronous functions described above.

* `function GetAddress() internal view inline returns (string)` - get your Tezos address
* `function GetBalance() internal view inline returns (uint128)` - get your Tezos balance
* `function GetTokens() internal view returns(Token[] tokens)` - get your token contract addresses
* `function GetLastTxHash() internal view inline returns (string)` - get last operation hash
* `function GetLastOpg() internal view inline returns (TxResult[])` - get last operation results
* `function IsRevealed() internal view inline returns (bool)` - returns `true` if the public key have been revealed


#### Examples

```solidity

contract Bot is Debot, TezosClient {

    function start() public override {
        InitClient(); // get your public key and Tezos address
    }
    
    function OnInitClient() internal override {
        UpdateBalance(0); // update balance
    }
    
    function OnUpdateBalance(uint32 reason) internal override {
        Terminal.print(0, format("Your Tezos address: {}", GetAddress()));
        Terminal.print(0, format("Your Tezos balance: {}", GetBalance()));

        // transfer tokens 1 TEZ
        Transfer("tz1QyBtJr8dPLQBaCLBYKTYQ56CWzSi9s5PL", 1000000);
    }
    
    function OnTransferSuccess(string tx_hash) internal override {
        Terminal.print(0, format("https://hangzhou2net.tzkt.io/{}", tx_hash));
        ShowTxSuccessMenu("💸 Transaction sent!");
    }

}
```


## References:

* https://tezosguides.com/wallet_integration/

