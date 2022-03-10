GIVER=0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415

function giver {
    tonos-cli --url http://127.0.0.1 call 0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415 \
        sendTransaction "{\"dest\":\"$1\",\"value\":200000000,\"bounce\":false}" \
        --abi ../giver/Giver.abi.json \
        --sign ../giver/Giver.keys.json
}

function get_address {
    echo $(cat $1.log | grep "Raw address:" | cut -d ' ' -f 3)
}

function genaddr {
    tonos-cli genaddr $1.tvc $1.abi.json --setkey keyfile.json > $1.log
}

echo "Step 1. Calculating address"
CONTRACT_NAME=Blake2b

## If you re-compile the contract it may change its address
# everdev sol compile $CONTRACT_NAME.sol

genaddr $CONTRACT_NAME
CONTRACT_ADDRESS=$(get_address $CONTRACT_NAME)

echo "Step 2. Sending tokens to address: $CONTRACT_ADDRESS"
giver $CONTRACT_ADDRESS

echo "Step 3. Deploying contract"
tonos-cli --url http://127.0.0.1 deploy --abi $CONTRACT_NAME.abi.json --sign keyfile.json $CONTRACT_NAME.tvc "{}"
