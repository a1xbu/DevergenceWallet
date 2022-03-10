## Run Faucet Everscale-Tezos relay

Install libraries:
```
sudo apt install libsodium-dev libsecp256k1-dev libgmp-dev
```

Install python dependencies:
```
pip install -r requirements.txt
```

Run:
```
python $BASEDIR/run.py -f ./keyfile.json -e testnet -k edsk...<your_tezos_private_key>...
```

> Note: `keyfile.json` should contain the keypair of the Faucet contract owner.
