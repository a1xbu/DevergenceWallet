GIVER=0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415
NET=http://127.0.0.1

function giver {
    tonos-cli --url http://127.0.0.1 call 0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415 \
        sendTransaction "{\"dest\":\"$1\",\"value\":1000000000,\"bounce\":false}" \
        --abi ./giver/Giver.abi.json \
        --sign ./giver/Giver.keys.json
}

function get_address {
    echo $(cat $1.log | grep "Raw address:" | cut -d ' ' -f 3)
}

function genaddr {
    tonos-cli genaddr $1.tvc $1.abi.json > $1.log
}


DEBOT_NAME=WalletBot

everdev sol compile $DEBOT_NAME.sol

genaddr $DEBOT_NAME
DEBOT_ADDRESS=$(get_address $DEBOT_NAME)

debot_abi=$(cat $DEBOT_NAME.abi.json | jq --compact-output | xxd -ps -c 200000)

ICON_BYTES=$(base64 -w 0 ./images/icon.png)
LOGO_BYTES=$(base64 -w 0 ./images/logo.png)
ICON=$(echo -n "data:image/png;base64,$ICON_BYTES")
LOGO=$(echo -n "data:image/png;base64,$LOGO_BYTES")


giver $DEBOT_ADDRESS

tonos-cli --url $NET deploy --abi $DEBOT_NAME.abi.json $DEBOT_NAME.tvc "{}"
tonos-cli --url $NET call $DEBOT_ADDRESS setABI "{\"dabi\":\"$debot_abi\"}" --abi $DEBOT_NAME.abi.json
tonos-cli --url $NET call $DEBOT_ADDRESS setIcon "{\"icon\":\"$ICON\"}" --abi $DEBOT_NAME.abi.json
tonos-cli --url $NET call $DEBOT_ADDRESS setLogo "{\"logo\":\"$LOGO\"}" --abi $DEBOT_NAME.abi.json

## Uncomment and put here the Faucet DeBot address if you have it
# FAUCET_ADDRESS=0:0f2b2cf50cb9cd2d7fe7abba4e5a512d717a553380e30ed6b3347e7a755b1fdd
# tonos-cli --url $NET call $DEBOT_ADDRESS setFaucetAddress "{\"faucet\":\"$FAUCET_ADDRESS\"}" --abi $DEBOT_NAME.abi.json

echo DeBot address: $DEBOT_ADDRESS

## Uncomment to automatically run the debot in the console debot browser:
# tonos-cli --url $NET debot fetch $DEBOT_ADDRESS
