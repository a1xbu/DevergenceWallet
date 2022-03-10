import os
import base64
from tonclient.client import *
from tonclient.types import *
import ast
from tonclient.client import DEVNET_BASE_URLS, MAINNET_BASE_URLS

ZERO_PUBKEY = "0000000000000000000000000000000000000000000000000000000000000000"


class BaseContract:
    def __init__(self, keyfile=None, endpoints=DEVNET_BASE_URLS):
        config = ClientConfig()
        config.network.endpoints = endpoints
        self.client = TonClient(config=config)
        base_path = os.path.join(
            os.path.dirname(__file__), ".", "contracts", self.__class__.__name__
        )
        self.tvc_path = base_path + ".tvc"
        self.abi_path = self.tvc = base_path + ".abi.json"
        if keyfile:
            self.signer = self.load_signer(keyfile)

    @staticmethod
    def load_signer(keyfile):
        return Signer.Keys(KeyPair.load(keyfile, False))

    def get_abi(self):
        abi = Abi.from_path(path=self.abi_path)
        return abi

    def get_tvc(self):
        with open(self.tvc_path, "rb") as f:
            tvc = base64.b64encode(f.read()).decode()
            return tvc

    def get_code_from_tvc(self):
        tvc = self.get_tvc()
        tvc_code_params = ParamsOfGetCodeFromTvc(tvc=tvc)
        tvc_code_result = self.client.boc.get_code_from_tvc(params=tvc_code_params).code
        return tvc_code_result

    def get_address(self, pubkey=None, initial_data=None):
        if pubkey is None:
            pubkey = self.signer.keys.public
        if initial_data is None:
            initial_data = {}
        abi, tvc = self.get_abi(), self.get_tvc()
        deploy_set = DeploySet(
            tvc=tvc, initial_pubkey=pubkey, initial_data=initial_data
        )
        params = ParamsOfEncodeMessage(
            abi=abi, signer=self.signer, deploy_set=deploy_set
        )
        encoded = self.client.abi.encode_message(params=params)
        return encoded.address

    @staticmethod
    def get_values_from_exception(ton_exception):
        arg = ton_exception.args[0]
        error = arg[arg.find("(Data:") + 7 : -1]
        result = ast.literal_eval(error)

        try:
            error_code = result["exit_code"]
        except KeyError:
            try:
                error_code = result["local_error"]["data"]["exit_code"]
            except KeyError:
                error_code = ""

        try:
            error_desc = result["description"]
        except KeyError:
            error_desc = ""

        try:
            tx_id = result["transaction_id"]
        except KeyError:
            tx_id = ""

        try:
            message = result["message"]
        except KeyError:
            try:
                message = result["local_error"]["message"]
            except KeyError:
                message = ""

        return {
            "error_code": error_code,
            "errorMessage": message,
            "transactionID": tx_id,
            "error_desc": error_desc,
        }

    def deploy(self, constructor_input=None, initial_data=None):
        try:
            if constructor_input is None:
                constructor_input = {}
            if initial_data is None:
                initial_data = {}

            abi, tvc = self.get_abi(), self.get_tvc()
            call_set = CallSet(function_name="constructor", input=constructor_input)
            deploy_set = DeploySet(
                tvc=tvc, initial_pubkey=self.signer.keys.public, initial_data=initial_data
            )
            params = ParamsOfEncodeMessage(
                abi=abi, signer=self.signer, call_set=call_set, deploy_set=deploy_set
            )
            encoded = self.client.abi.encode_message(params=params)

            message_params = ParamsOfSendMessage(
                message=encoded.message, send_events=False, abi=abi
            )
            message_result = self.client.processing.send_message(params=message_params)
            wait_params = ParamsOfWaitForTransaction(
                message=encoded.message,
                shard_block_id=message_result.shard_block_id,
                send_events=False,
                abi=abi,
            )
            result = self.client.processing.wait_for_transaction(params=wait_params)

            # print(result.transaction)
            return result, {
                "error_code": 0,
                "errorMessage": "",
                "transactionID": "",
                "error_desc": "",
            }

        except TonException as ton:
            exception_details = self.get_values_from_exception(ton)
            print("Exception: %s" % ton.args)
            return {}, exception_details

    def get_account_graphql(self, account_id, fields):
        params_query = ParamsOfQuery(
            query="query($accnt: String){accounts(filter:{id:{eq:$accnt}}){"
            + fields
            + "}}",
            variables={"accnt": account_id},
        )
        result = self.client.net.query(params=params_query)

        if len(result.result["data"]["accounts"]) > 0:
            return result.result["data"]["accounts"][0]
        else:
            return ""

    def run_function(self, function_name, function_params):
        try:
            result = self.get_account_graphql(self.get_address(), "boc")
            if result == "":
                return ""
            boc = result.get("boc")
            if boc is None:
                return ""

            abi = self.get_abi()
            call_set = CallSet(function_name=function_name, input=function_params)
            params = ParamsOfEncodeMessage(
                abi=abi,
                address=self.get_address(),
                signer=Signer.NoSigner(),
                call_set=call_set,
            )
            encoded = self.client.abi.encode_message(params=params)

            params_run = ParamsOfRunTvm(message=encoded.message, account=boc, abi=abi)
            result = self.client.tvm.run_tvm(params=params_run)

            params_decode = ParamsOfDecodeMessage(
                abi=abi, message=result.out_messages[0]
            )
            decoded = self.client.abi.decode_message(params=params_decode)
            return decoded
        except TonException as ton:
            exception_details = self.get_values_from_exception(ton)
            print("Exception: %s" % ton.args)
            return {}, exception_details

    def call_function(self, function_name, function_params, async_call=False):
        try:
            abi = self.get_abi()
            call_set = CallSet(function_name=function_name, input=function_params)
            params = ParamsOfEncodeMessage(
                abi=abi, address=self.get_address(), signer=self.signer, call_set=call_set
            )
            encoded = self.client.abi.encode_message(params=params)

            message_params = ParamsOfSendMessage(
                message=encoded.message, send_events=False, abi=abi
            )
            message_result = self.client.processing.send_message(params=message_params)

            if not async_call:
                wait_params = ParamsOfWaitForTransaction(
                    message=encoded.message,
                    shard_block_id=message_result.shard_block_id,
                    send_events=False,
                    abi=abi,
                )
                result = self.client.processing.wait_for_transaction(params=wait_params)

                return result, {
                    "error_code": 0,
                    "errorMessage": "",
                    "transactionID": "",
                    "error_desc": "",
                }
        except TonException as ton:
            exception_details = self.get_values_from_exception(ton)
            print("Exception: %s" % ton.args)
            return {}, exception_details

    @staticmethod
    def hex(input_string: str):
        return str(input_string).encode('utf-8').hex()
