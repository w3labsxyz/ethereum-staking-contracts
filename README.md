# Justfarming Contracts

This repository contains the smart contract code for the Justfarming platform.
Each contract has its own directory under [`contracts`](/contracts).

## Contracts

### Split Rewards

The contracts in the `split-rewards` directory handle the allocation of staking rewards between a staking customer and the platform. The primary contract `SplitRewards.sol` implements a pull-based approach for withdrawing validator rewards. For more information, see `contracts/split-rewards/README.md`.

### Batch Deposit

The contracts in the `batch-deposit` directory enable the customer to deploy more than one Ethereum validator at once. `BatchDeposit.sol` contract interacts with the Ethereum staking deposit contract, allowing multiple calls in a loop. For more information, see `contracts/batch-deposit/README.md`.

Credits also go to [stakefish](https://www.stake.fish) and [abyss](https://www.abyss.finance) who have built their batch depositors in the open:

- [stakefish BatchDeposits contract (GitHub)](https://github.com/stakefish/eth2-batch-deposit/blob/main/contracts/BatchDeposits.sol)
- [Abyss Eth2 Depositor contract (GitHub)](https://github.com/abyssfinance/abyss-eth2depositor/blob/main/contracts/AbyssEth2Depositor.sol)

## Setup

The Justfaring contracts project uses the [Truffle Suite](https://trufflesuite.com/) and [Node.js with `npm`](https://nodejs.org/en) to manage its dependencies.

With `node`, you can proceed with installing the project-specific dependencies:

``` shell
npm install
```

For static analysis, [Slither](https://github.com/crytic/slither) is used as a tools for performing automated security analysis on the smart contracts.

``` shell
pip3 install slither-analyzer
```

`solc-select` is being used for managing the solidity version in use.

``` shell
pip3 install solc-select
solc-select install 0.8.20
solc-select use 0.8.20
```

## Developing

### Linting

You can lint `.js` and `.ts` files with

``` shell
npm run lint:ts
```

as well as the `.sol` files with

``` shell
npm run lint:sol
```

Most issues can be fixed with

``` shell
npm run lint:js -- --fix
npm run fmt
```

### Testing

To run the tests:

``` shell
npm run test
```

### Analysis

To run the analyzer:

``` shell
npm run analyze
```

## Integration testing

### Local Testnet

In addition to the previously mentioned requirements, you will need the following in order to run the local testnet:

- [Setup docker](https://docs.kurtosis.com/next/install#i-install--start-docker)
- [Install kurtosis](https://docs.kurtosis.com/next/install#ii-install-the-cli)

Launch a local ethereum network:
``` shell
kurtosis run --enclave justfarming-contracts config/localnet/main.star "$(cat ./config/localnet/params.json)"
```

With default settings being used, the network will run at `http://127.0.0.1:64248`.
Prefunded accounts use the following private keys ([source](https://github.com/kurtosis-tech/eth-network-package/blob/main/src/prelaunch_data_generator/genesis_constants/genesis_constants.star)):
``` md
ef5177cd0b6b21c87db5a0bf35d4084a8a57a9d6a064f86d51ac85f2b873a4e2
48fcc39ae27a0e8bf0274021ae6ebd8fe4a0e12623d61464c498900b28feb567
7988b3a148716ff800414935b305436493e1f25237a2a03e5eebc343735e2f31
b3c409b6b0b3aa5e65ab2dc1930534608239a478106acf6f3d9178e9f9b00b35
df9bb6de5d3dc59595bcaa676397d837ff49441d211878c024eabda2cd067c9f
7da08f856b5956d40a72968f93396f6acff17193f013e8053f6fbb6c08c194d6
```

Find the rpc port of your locally running execution client by running
``` shell
npx hardhat update-rpc-port
```

This command also update the local environment (`.env.local`) used for the `networks.localnet` configuration in [./hardhat.config.ts](/hardhat.config.ts) to use this port.

Deploy contracts to the locally running network:

``` shell
npm run deploy:localnet
```

Remember to clean up when you are done.
``` shell
kurtosis clean -a
```

You can stream the logs of your validator node with:
``` shell
docker logs -f $(docker ps | grep justfarming-lighthouse-validator | awk '{print $1}' | tr -d '\n')
```

this is especially helpful for observing validators become active upon using `BatchDepoit.sol`.

## Deployment

To deploy the contracts to a network:

``` shell
npx hardhat ...
```
