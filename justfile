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

deploy-vault chain:
    forge script --chain="{{chain}}" scripts/Deploy.s.sol:DeployStakingVaultImplementation --broadcast --fork-url http://localhost:34002

deploy-factory chain:
    forge script --chain="{{chain}}" scripts/Deploy.s.sol:DeployStakingVaultFactory --broadcast --fork-url http://localhost:34002

deploy-proxy chain:
    forge script --chain="{{chain}}" scripts/Deploy.s.sol:DeployStakingVaultProxy --broadcast --fork-url http://localhost:34002
