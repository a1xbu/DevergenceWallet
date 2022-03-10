import sys
from Faucet import Faucet
from User import User
from tonclient.client import DEVNET_BASE_URLS, MAINNET_BASE_URLS


def main():
    if len(sys.argv) <= 1:
        print("Usage: \nkeyfile.json [endpoint1] [endpoint2] [...]")
        return
    endpoints = sys.argv[2:] if len(sys.argv) >= 2 else DEVNET_BASE_URLS
    keyfile = sys.argv[1]

    faucet = Faucet(keyfile, endpoints)
    user = User(keyfile, endpoints)

    user_code = user.get_code_from_tvc()
    print(user_code)

    result = faucet.setUserCode(user_code)
    print(result)
    print(faucet.get_address())


if __name__ == '__main__':
    main()
