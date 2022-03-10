GIVER=0:ece57bcc6c530283becbbd8a3b24d3c5987cdddc3c8b7b33be6e4a6312490415

NET=http://127.0.0.1
#NET=http://net.ton.dev

function giver {
    tonos-cli --url $NET call $GIVER \
        sendTransaction "{\"dest\":\"$1\",\"value\":$2,\"bounce\":false}" \
        --abi ./../../giver/Giver.abi.json \
        --sign ./../../giver/Giver.keys.json
}

function get_address {
    echo $(cat $1.log | grep "Raw address:" | cut -d ' ' -f 3)
}

function genaddr {
    tonos-cli genaddr $1.tvc $1.abi.json --setkey keyfile.json > $1.log
}


DEBOT_NAME=FaucetBot

everdev sol compile $DEBOT_NAME.sol
everdev sol compile Faucet.sol
everdev sol compile User.sol
USER_CODE=$(cat ./User.b64)

genaddr $DEBOT_NAME
DEBOT_ADDRESS=$(get_address $DEBOT_NAME)

genaddr Faucet
FAUCET_ADDRESS=$(get_address Faucet)

debot_abi=$(cat $DEBOT_NAME.abi.json | jq --compact-output | xxd -ps -c 200000)

giver $FAUCET_ADDRESS 2000000000
giver $DEBOT_ADDRESS 500000000

tonos-cli --url $NET deploy --abi Faucet.abi.json --sign keyfile.json Faucet.tvc "{}"
tonos-cli --url $NET deploy --abi $DEBOT_NAME.abi.json --sign keyfile.json $DEBOT_NAME.tvc "{}"

tonos-cli --url $NET call $FAUCET_ADDRESS setUserCode "{\"code\":\"$USER_CODE\"}" --abi Faucet.abi.json --sign keyfile.json
tonos-cli --url $NET call $DEBOT_ADDRESS setABI "{\"dabi\":\"$debot_abi\"}" --abi $DEBOT_NAME.abi.json --sign keyfile.json
tonos-cli --url $NET call $DEBOT_ADDRESS setFaucetAddress "{\"faucet\":\"$FAUCET_ADDRESS\"}" --abi $DEBOT_NAME.abi.json --sign keyfile.json

echo Faucet address $FAUCET_ADDRESS
echo Debot deployed at $DEBOT_ADDRESS
#tonos-cli --url $NET debot fetch $DEBOT_ADDRESS
