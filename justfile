default:
  just --list

# Run a local ethereum localnet
localnet-start:
    kurtosis run --enclave localnet github.com/ethpandaops/ethereum-package --args-file config/localnet/minimal.yml

# Stop and remove the local ethereum localnet
localnet-stop:
    kurtosis enclave rm -f localnet

# Print the status of the local ethereum localnet
localnet-info:
    kurtosis enclave inspect localnet

deploy-devnet:
    forge script --chain="dev" scripts/Devnet.s.sol:Deploy --broadcast --fork-url http://great-weevil:34002

compile-abi:
    forge build
    jq 'del(.metadata, .rawMetadata, .id, .bytecode, .deployedBytecode, .ast)' \
        out/StakingHub.sol/StakingHub.json > abi/StakingHub.json
    jq 'del(.metadata, .rawMetadata, .id, .bytecode, .deployedBytecode, .ast)' \
        out/StakingVault.sol/StakingVault.json > abi/StakingVault.json
