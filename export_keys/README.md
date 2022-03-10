# Helper script to export Surf keys in edsk-format

This script helps you to export your Surf wallet keys in format compatible with
Tezos wallets such as Temple wallet. The scripts also derives the Tezos address from the public key.

## Usage

* Install python requirements:
```shell script
pip install -r requirements.txt
```

* Run script for your seed phrase:

```shell script
python export_key.py "<seed phrase>"
``` 

### Example:

```shell script
> python export_key.py "economy crane wing fruit cave nothing bitter rent globe regular cross giraffe"
Tezos address: tz1f64ewziwZ3pheP4VqGcnF6iMEV4atYmx8
Tezos private key: edskRoN4ChS1REvKEFtRf281mQci6eComGJEbBtgb4vbBXYWf1rxTfHStgGtjkKdqZkHbyDQ8opqLE3pFgyRaa22yVH9cZN9Qq
```
