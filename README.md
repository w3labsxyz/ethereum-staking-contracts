# w3.labs Staking Contracts

This repository contains the smart contract code for the w3.labs staking platform.
Contracts are organized in the [`src`](/src) directory. [`lib`](/lib) contains external interfaces we depend on, managed via git submodules.
The [`tests`](/tests) and [`scripts](/scripts) directories contain tests and scripts respectively.

The following table lists the networks and respective addresses that the contracts have been deployed to:

| Network | Chain Id | Contract                      | Address                                                                                                                       |
| ------- | -------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Mainnet | 1        | StakingHub                    | [0xa2a9c501d1d29ff696e7045c05deef1ed7511143](https://etherscan.io/address/0xa2a9c501d1d29ff696e7045c05deef1ed7511143)         |
| Mainnet | 1        | StakingVault (Implementation) | [0x01e3758a2ed05E2E87F0E62CBB247b42146a8293](https://etherscan.io/address/0x01e3758a2ed05E2E87F0E62CBB247b42146a8293)         |
| Holesky | 17000    | StakingHub                    | [0xe0a30f5f34c91b0acd2726d07da88d67fe4e5994](https://holesky.etherscan.io/address/0xe0a30f5f34c91b0acd2726d07da88d67fe4e5994) |
| Holesky | 17000    | StakingVault (Implementation) | [0x7152223aabe4f83c0b7dd03e9552017393153633](https://holesky.etherscan.io/address/0x7152223aabe4f83c0b7dd03e9552017393153633) |

## Contracts

### StakingHub

The w3.labs StakingHub contract acts as the central hub to creating instances of our StakingVault.
The notable interface exposed is the `createVault` function, which allows for the creation of a new StakingVault instance.
We instantiate StakingVaults by creating [`EIP-1967 proxies`](https://eips.ethereum.org/EIPS/eip-1967) pointing to the StakingVault Implementation, thereby following the [`EIP-1822 UUPS standard`](https://eips.ethereum.org/EIPS/eip-1822).

### StakingVault

The w3.labs StakingVault contract enables the deployment of multiple Ethereum validators at once.
The notable interactions with it are depicted in the following sequence diagram:

```mermaid
sequenceDiagram
    actor Staker
    participant StakingHub Contract
    participant StakingVault Contract
    participant Beacon Deposit Contract
    participant Ethereum Network
    participant Validator
    actor w3.labs Consensus

    Staker->>StakingHub Contract: Create Vault
    StakingHub Contract->>StakingVault Contract: Initialize Vault
    activate StakingVault Contract
    StakingVault Contract-->>Staker: Vault assigned
    deactivate StakingVault Contract

    loop Staking phase
        Staker->>StakingVault Contract: Request Stake Quota
        w3.labs Consensus->>Validator: Provision Validators
        w3.labs Consensus->>StakingVault Contract: Allocate Stake Quota

        Staker->>StakingVault Contract: Verify Deposit Data
        Staker->>StakingVault Contract: Stake
        StakingVault Contract->>+Beacon Deposit Contract: Forward Stake
        Note over Beacon Deposit Contract: Wait for Ethereum Network to activate validator
	end

    loop Active phase
        Ethereum Network->>Validator: Request Block Attestations & Signings
        Validator->>Ethereum Network: Sign and Attest Blocks
        Ethereum Network->>Validator: Increase Validator Balance with Consensus-Rewards
        Ethereum Network->>Validator: Withdraw Consensus-Rewards every ~4.5 days
        Ethereum Network->>StakingVault Contract: Credit Consensus-Rewards every ~4.5 days
		Ethereum Network->>StakingVault Contract: Send Execution-Rewards for signed Blocks

		Staker->>StakingVault Contract: Claim Rewards
		StakingVault Contract->>Staker: Send Rewards

		w3.labs Consensus->>StakingVault Contract: Claim Fees
		StakingVault Contract->>w3.labs Consensus: Send Fees
	end

    Staker->>StakingVault Contract: Request Unbonding
    StakingVault Contract->>+Ethereum Network: Forward Unbonding Request

    Note over Ethereum Network: Wait for Ethereum Exit Queue

    Validator->>Validator: Stop Validation

    Ethereum Network->>StakingVault Contract: Release Stake & Consensus-Rewards

    Staker->>StakingVault Contract: Claim Rewards
    StakingVault Contract->>Staker: Send Rewards
    Staker->>StakingVault Contract: Withdraw Principal
    StakingVault Contract->>Staker: Send Principal

    w3.labs Consensus->>StakingVault Contract: Claim Fees
    StakingVault Contract->>w3.labs Consensus: Send Fees
```

## Design Decisions

### UUPS

As noted above, we are implementing the UUPS standard. The StakingVault is initializable when instantiated via an EIP-1967 proxy. This allows the effective owner of a StakingVault to upgrade their instance of a StakingVault.

### Access Control

The StakingVault defined three roles: `staker`, `depositor`, and `operator`
The `staker` role is the primary role, allowing for:

- Upgrading the StakingVault
- Requesting stake quotas
- Requesting stake unbondings
- Withdraw principal after unbonding
- Claim rewards
- Add addresses to the `depositor` role
- Act as `depositor`

The `depositor` role is a secondary role, allowing for:

- Depositing, i.e., staking, funds into the StakingVault

The `operator` role is associated with the node operator, allowing for:

- Approving stake quotas, i.e., adding deposit data to the StakingVault
- Attest unbondings
- Claim fees
- Update the fee recipient address

### Expensive stake quota requests

Stake quota requests are purposefully expensive to prevent spamming our validator provisioning service.
The cost of a stake quota request is proportional to the number of validators requested.
We do this by preallocating storage slots for deposit data that is to be registered by the operator.

### Execution triggerable exits

We are implementing [EIP-7002](https://eips.ethereum.org/EIPS/eip-7002) to allow the `staker` to trigger unbondings of stake, i.e., exits of validators, solely via the execution layer. That is to fully enable the `staker` to manage their stake without the need for external interactions.

#### EIP-7002

EIP-7002 will become active with the upcoming [Pectra hardfork](https://eips.ethereum.org/EIPS/eip-7600). Up until then, the associated functions will revert.

The tests contain references to the compiles [geas](https://github.com/fjl/geas) implementation of EIP-7002, as found in:

- Original source: https://github.com/lightclient/sys-asm/blob/main/src/withdrawals/main.eas
- Taken from commit `e5d197005661481f7b83f189e183949eaa2d3ae5`
- The official audit references this repository: https://github.com/ethereum/requests-for-proposals/blob/master/open-rfps/pectra-system-contracts-audit.md
- Compiled with: `geas lib/sys-asm/src/withdrawals/main.eas`

### No support for EIP-7251

We are aware of [EIP-7251](https://eips.ethereum.org/EIPS/eip-7251), but this StakingVault implementation does explicitly use `0x01` withdrawal credentials only. We consider implementing a compounding version of this StakingVault using `0x02` credentials, but this is out of scope for this implementation.

Execution-layer triggerable validator consolidation are not an issue for our StakingVault as the StakingVault itself is set to be the withdrawal address and therefore the only entity that can trigger such consolidations.

### Not using EIP-4788

We are aware of [EIP-4788](https://eips.ethereum.org/EIPS/eip-4788), i.e., the effective presence of beacon chain data in the EVM but found little value for our concrete implementation compared to the complexity it poses to implement and the UX it imposes onto the caller. We have therefore decided not to implement any proofs and proof checking in the StakingVault. This comes with at least one limitation when calculating rewards, fees, and unbonded principal: In our design, withdrawable principal takes precedence. When an unbonding is triggered, rewards and fees present in the vault are temporarily "locked" by being allocated towards being withdrawn as principal. Once the principal is swept off the balance of the exited validator, fees and rewards can be claimed as usual.

## Setup

We are using foundry as the primary development toolkit for this project. Follow [the foundry documentation to set it up](https://book.getfoundry.sh/getting-started/installation). The following tools are used in this project:

- [Forge](https://github.com/foundry-rs/foundry): compile, test, fuzz, format, and deploy smart
  contracts
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and utilities for testing
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code

For static analysis, [Slither](https://github.com/crytic/slither) is used to perform automated security analysis on the smart contracts.

```shell
python3.13 -m venv venv
source venv/bin/activate
pip3 install slither-analyzer
```

We use `solc-select` for managing the active solidity version.

```shell
pip3 install solc-select
solc-select install 0.8.28
solc-select use 0.8.28
```

## Developing

### Building

```shell
# forge clean
forge build
```

### Formatting

```shell
forge fmt
```

### Linting

```shell
npm run lint
```

### Static-Analysis

```shell
npm run analyze
```

### Testing

To run the tests, you can run:

```shell
npm run test
npm run test:gas-report
npm run test:coverage:report
```

## Deployment

To deploy the contracts, we use [Nick's method](https://medium.com/patronum-labs/nicks-method-ethereum-keyless-execution-168a6659479c).

### Deploying the `StakingVault` implementation contract:

#### Deploying in the devnet

```shell
export OPERATOR_ADDRESS=0xE0C015892d16eBfc16500811fEB05501A425116B
export FEE_RECIPIENT_ADDRESS=0x0bf37242332Ee420A091891BD94921cEDE2ff46a
export BASIS_POINTS=1000
export RPC_URL=http://great-weevil:34002

# Create the raw bytecode for deploying the StakingVault
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingVaultDeploymentBytecode
# The `3872765` gas required has been derived via `forge test --gas-report`
npm run presign-deployment-tx -- StakingVault 1000000000 3872765
# Fund the deployer account
cast send --value 0.003872765ether 0xC58a4F71b13cFa2CF9A5C065CC45d484F9329694 --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --rpc-url $RPC_URL
# And broadcast the transaction
cast publish "$(cat out/CreateStakingVault.tx.json)" --rpc-url $RPC_URL
# Verify the contract
export STAKING_VAULT_IMPLEMENTATION_ADDRESS=0x2bf97632f255741282639ff72344e6cd9c98fcf4
forge verify-contract --rpc-url $RPC_URL --verifier blockscout --verifier-url http://localhost:36003/api --json $STAKING_VAULT_IMPLEMENTATION_ADDRESS StakingVault

# Create the raw bytecode for deploying the StakingHub
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingHubDeploymentBytecode --sig "run(address,address,address,uint256)" $STAKING_VAULT_IMPLEMENTATION_ADDRESS $OPERATOR_ADDRESS $FEE_RECIPIENT_ADDRESS $BASIS_POINTS
# We found out the 1603338 gas by simulating in the devnet
npm run presign-deployment-tx -- StakingHub 1000000000 1603338
# Fund the deployer account
cast send --value 0.001603338ether 0xCaF3fbD31226D39edd3198Bf200408C779E496CC --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --rpc-url $RPC_URL
# And broadcast the transaction
cast publish "$(cat out/CreateStakingHub.tx.json)" --rpc-url $RPC_URL
export STAKING_HUB_ADDRESS=0xe447bcbf912260916d7370a8b7561dbdc9132d2e
forge verify-contract --rpc-url $RPC_URL --verifier blockscout --verifier-url http://localhost:36003/api --json --guess-constructor-args $STAKING_HUB_ADDRESS StakingHub

# To deploy a proxy, run
cast send --value 1ether 0x614561D2d143621E126e87831AEF287678B442b8 --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --rpc-url $RPC_URL
forge script scripts/Devnet.s.sol:DeployStakingVaultProxy --rpc-url $RPC_URL --broadcast --sig "run(address)" $STAKING_HUB_ADDRESS

# To request a certain amount of stake quota
forge script scripts/Devnet.s.sol:RequestStakQuotaOnStakingVaultProxy --rpc-url $RPC_URL --broadcast --sig "run(address,uint256)" $STAKING_HUB_ADDRESS 100

# StakingVault Proxy of the staker: 0xb6ac5EeAF247CE45E2DE29933252b83fD9cB71c4

# Fund the operator
cast send --value 0.5ether 0xE0C015892d16eBfc16500811fEB05501A425116B --private-key 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31 --rpc-url $RPC_URL
```

#### Deploying in Holesky

```shell
export OPERATOR_ADDRESS=0xE0C015892d16eBfc16500811fEB05501A425116B
export FEE_RECIPIENT_ADDRESS=0x0bf37242332Ee420A091891BD94921cEDE2ff46a
export BASIS_POINTS=1000
export RPC_URL=http://mighty-weevil:8545

# Start with the StakingVault
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingVaultDeploymentBytecode
npm run presign-deployment-tx -- StakingVault 5000000000 3872765
# Fund the deployer account
cast publish "$(cat out/CreateStakingVault.tx.json)" --rpc-url $RPC_URL
export STAKING_VAULT_IMPLEMENTATION_ADDRESS=0x7152223aabe4f83c0b7dd03e9552017393153633
op run --env-file=".env" -- forge verify-contract --verifier etherscan --rpc-url $RPC_URL --json $STAKING_VAULT_IMPLEMENTATION_ADDRESS StakingVault

# Continue with the StakingHub
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingHubDeploymentBytecode --sig "run(address,address,address,uint256)" $STAKING_VAULT_IMPLEMENTATION_ADDRESS $OPERATOR_ADDRESS $FEE_RECIPIENT_ADDRESS $BASIS_POINTS
# We found out the 1603338 gas by simulating in the devnet
npm run presign-deployment-tx -- StakingHub 5000000000 1603338
# Fund the deployer account
cast publish "$(cat out/CreateStakingHub.tx.json)" --rpc-url $RPC_URL
export STAKING_HUB_ADDRESS=0xe0a30f5f34c91b0acd2726d07da88d67fe4e5994
op run --env-file=".env" -- forge verify-contract --verifier etherscan --rpc-url $RPC_URL --json --guess-constructor-args $STAKING_HUB_ADDRESS StakingHub
```

#### Deploying in Mainnet

```shell
export OPERATOR_ADDRESS=0xE0837559527A693a23fEbf7c15BC36A943464386
export FEE_RECIPIENT_ADDRESS=0x30529bb39F3f940cBa6F03B7C19bc70de6fa9555
export BASIS_POINTS=1000
export RPC_URL=http://boss-ray:8545

# Start with the StakingVault
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingVaultDeploymentBytecode
npm run presign-deployment-tx -- StakingVault 2000000000 3872765
# Fund the deployer account
cast publish "$(cat out/CreateStakingVault.tx.json)" --rpc-url $RPC_URL
export STAKING_VAULT_IMPLEMENTATION_ADDRESS=0x01e3758a2ed05E2E87F0E62CBB247b42146a8293
op run --env-file=".env" -- forge verify-contract --verifier etherscan --rpc-url $RPC_URL --json $STAKING_VAULT_IMPLEMENTATION_ADDRESS StakingVault
forge verify-contract --rpc-url $RPC_URL --verifier blockscout --verifier-url https://eth.blockscout.com/api --json $STAKING_VAULT_IMPLEMENTATION_ADDRESS StakingVault
forge verify-contract --rpc-url $RPC_URL --verifier sourcify --json $STAKING_VAULT_IMPLEMENTATION_ADDRESS StakingVault

# Continue with the StakingHub
forge script scripts/CreateDeploymentBytecode.s.sol:CreateStakingHubDeploymentBytecode --sig "run(address,address,address,uint256)" $STAKING_VAULT_IMPLEMENTATION_ADDRESS $OPERATOR_ADDRESS $FEE_RECIPIENT_ADDRESS $BASIS_POINTS
# We found out the 1603338 gas by simulating in the devnet
npm run presign-deployment-tx -- StakingHub 2000000000 1603338
# Fund the deployer account
cast publish "$(cat out/CreateStakingHub.tx.json)" --rpc-url $RPC_URL
export STAKING_HUB_ADDRESS=0xA2A9C501D1D29fF696E7045c05DeEf1ed7511143
op run --env-file=".env" -- forge verify-contract --verifier etherscan --rpc-url $RPC_URL --json --guess-constructor-args $STAKING_HUB_ADDRESS StakingHub
forge verify-contract --rpc-url $RPC_URL --verifier blockscout --verifier-url https://eth.blockscout.com/api --json --guess-constructor-args $STAKING_HUB_ADDRESS StakingHub
```
