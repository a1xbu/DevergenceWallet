import argparse
import time
from datetime import datetime
from hashlib import blake2b
from base58 import b58encode_check

from Faucet import Faucet

from tonclient.errors import TonException
from tonclient.types import ClientConfig, ClientError, SubscriptionResponseType, \
    ParamsOfSubscribeCollection, ResultOfSubscription, ParamsOfDecodeMessageBody
from tonclient.client import DEVNET_BASE_URLS, MAINNET_BASE_URLS
from pytezos import pytezos, Key

import logging

logFormatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
log = logging.getLogger()

consoleHandler = logging.StreamHandler()
consoleHandler.setFormatter(logFormatter)
log.addHandler(consoleHandler)
log.setLevel(logging.INFO)


class Singleton(type):
    _instances = {}

    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            cls._instances[cls] = super(Singleton, cls).__call__(*args, **kwargs)
        return cls._instances[cls]


class FaucetController(metaclass=Singleton):

    results = []
    PREFIX_TX1 = b"\x06\xa1\x9f"
    delay = 0.1
    refresh_interval = 600
    query_interval = 15

    def __init__(self, ever_keyfile, ever_endpoints, tezos_key, tezos_shell):
        self.faucet = Faucet(ever_keyfile, ever_endpoints)
        self.subscription = None

        self.tezos = pytezos.using(shell=tezos_shell)
        self.tezos.key = Key.from_encoded_key(tezos_key)
        self.counter = 0
        self.last_claim_id = 0
        log.info("Init")

    def __op_token_tx(self, target_address, token_value):
        op_dict = {"entrypoint": "transfer",
                   "value": {
                       "prim": "Pair",
                       "args": [{"string": self.tezos.key.public_key_hash()},
                                {"prim": "Pair", "args": [{"string": target_address}, {"int": str(token_value)}]}]}}
        return op_dict

    def call_tezos_faucet(self, target_address: str, tezos_value: int, token_value: int) -> (str, int):
        try:
            opg = self.tezos.transaction(
                destination='KT1S4UuSGsg3aBmdU4px5VY4Ph8bdayxXjuR',
                parameters=self.__op_token_tx(target_address, token_value)
            ).transaction(
                destination='KT1E297g3vuJ5DLfoyWygFqBrsSkBaoDQByB',
                parameters=self.__op_token_tx(target_address, token_value)
            ).transaction(
                destination=target_address,
                amount=tezos_value
            )
            result = opg.autofill().sign().inject()
            tx_hash = result.get("hash", "failed")
            balance = self.tezos.balance()
        except Exception as e:
            log.error("Tezos transfer error %s", e.args)
            return "", -1
        return tx_hash, int(balance*(10**6))


    @staticmethod
    def __callback(response_data, response_type, loop):
        """
        `loop` in args is just for example.
        It will have value only with `asyncio` and may be replaced by `_` or `*args`
        in synchronous requests
        """
        if response_type == SubscriptionResponseType.OK:
            result = ResultOfSubscription(**response_data)
            FaucetController.results.append(result.result)
            # print(result.result)
        if response_type == SubscriptionResponseType.ERROR:
            log.error("WebSocket Disconnected %s", response_data)
            # raise TonException(error=ClientError(**response_data))

    def check_missed_requests(self):
        if self.counter % int(self.query_interval / self.delay) == 0:  # 30 seconds
            try:
                res = self.faucet.query_queue()
                self.handle_request(res)
            except Exception as e:
                log.error("check_missed_requests: " + str(e.args))

        self.counter += 1
        if self.counter % int(self.refresh_interval / self.delay) == 0:  # every 60 seconds
            self.subscribe_events()  # refresh subscription
            self.counter = 0

    def subscribe_events(self):
        now = int(datetime.now().timestamp())
        if self.subscription:
            self.faucet.client.net.unsubscribe(params=self.subscription)
            self.subscription = None
            log.info("Refreshing subscription")
        else:
            log.info("Subscribing")
        q_params = ParamsOfSubscribeCollection(
            collection='messages',
            result='id,src,dst,created_at,boc,body',
            filter={'created_at': {'gt': now}, 'src': {'eq': self.faucet.get_address()}, 'dst': {'eq': ''}}
        )
        self.subscription = self.faucet.client.net.subscribe_collection(
            params=q_params,
            callback=FaucetController.__callback
        )

    def handle_message(self, message):
        try:
            params = ParamsOfDecodeMessageBody(abi=self.faucet.get_abi(), body=message["body"], is_internal=False)
            decoded = self.faucet.client.abi.decode_message_body(params)

            if all([decoded.body_type == "Event", decoded.name == "ClaimEvent"]):
                self.handle_request(decoded)
            if all([decoded.body_type == "Event", decoded.name == "ClaimSuccessEvent"]):
                claim_id = int(decoded.value.get("claim_id"), 16)
                log.info("Claim success id=%d (callback)", claim_id)
        except Exception as e:
            log.error("handle_message" + str(e.args))
        self.results.remove(message)

    def handle_request(self, decoded_message):
        pubkey = int(decoded_message.value.get("pubkey"), 16)
        if pubkey == 0:
            return
        claim_id = int(decoded_message.value.get("claim_id"), 16)
        if claim_id == self.last_claim_id:
            log.info("Duplicate request for id %d", claim_id)
            return
        self.last_claim_id = claim_id
        surf_address = decoded_message.value.get("surf_address")
        log.info(f"{hex(pubkey)}: {claim_id} - ok")

        pubkey_hash = blake2b(int(pubkey).to_bytes(32, "big"), digest_size=20).digest()
        tezos_address = b58encode_check(self.PREFIX_TX1 + pubkey_hash).decode()
        log.info("Requested tokens for %s", tezos_address)

        tx_hash, balance = self.call_tezos_faucet(tezos_address, 10000000, 10000000)

        if balance != -1:
            self.faucet.ClaimSuccess(
                pubkey,
                claim_id,
                tx_hash,
                surf_address,
                balance
            )
            log.info("Claimed for %s, id=%s", tezos_address, claim_id)

    def run(self):
        self.subscribe_events()
        while True:
            time.sleep(self.delay)
            self.check_missed_requests()

            for message in FaucetController.results:
                self.handle_message(message)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Ever-Tezos faucet relay")
    parser.add_argument("-f", "--filekey", dest="keyfile", type=str, default="keyfile.json",
                        help="Json keyfile for Everscale. The key must be a deployer of the Faucet contract")
    parser.add_argument("-e", "--ever", dest="network", type=str, default="localhost",
                        help="Everscale network, can be one of 'localhost', 'testnet', 'mainnet'")
    parser.add_argument("-t", "--tezos", dest="shell", type=str, default="https://rpc.hangzhounet.teztnets.xyz",
                        help="Tezos RPC shell address")
    parser.add_argument("-k", "--key", dest="tezos_wallet", type=str,
                        help="Tezos Faucet encoded private key (edsk...)")
    args = parser.parse_args()

    if not args.tezos_wallet:
        print("You must provide Tezos key in format esdk... see --help")
        exit(1)

    if args.network == "testnet":
        endpoints = DEVNET_BASE_URLS
    elif args.network == "mainnet":
        endpoints = MAINNET_BASE_URLS
    else:
        endpoints = ["localhost"]

    log.info("Started!")
    faucet = FaucetController(
        args.keyfile, endpoints,
        args.tezos_wallet,
        args.shell
    )
    faucet.run()
