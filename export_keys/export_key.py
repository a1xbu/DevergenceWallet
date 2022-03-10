import sys
from base58 import b58encode_check
from hashlib import blake2b
from tonclient.client import *
from tonclient.types import *


def main():
    if len(sys.argv) <= 1:
        print("Usage: \n\tpython export_key.py \"{seed phrase}\"")
        print("Example: python export_key.py \"" +
              "economy crane wing fruit cave nothing bitter rent globe regular cross giraffe\"")
        return
    seed = sys.argv[1]

    path = "m/44'/396'/0'/0/0"
    client = TonClient(ClientConfig())
    sign_keys = client.crypto.mnemonic_derive_sign_keys(ParamsOfMnemonicDeriveSignKeys(seed, path))

    pubkey_hash = blake2b(sign_keys.public.encode(), digest_size=20).digest()
    tezos_address = b58encode_check(b"\x06\xa1\x9f" + pubkey_hash).decode()
    encoded_key = b58encode_check(b'+\xf6N\x07' + bytes.fromhex(sign_keys.secret + sign_keys.public)).decode()

    print(f"Tezos address: {tezos_address}")
    print(f"Tezos private key: {encoded_key}")


if __name__ == '__main__':
    main()
