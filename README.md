# Justfarming Contracts

This repository contains the smart contract code for the Justfarming platform.
Each contract has its own directory under [`contracts`](/contracts).

## Contracts

### Split Rewards

The contracts in the `split-rewards` directory handle the allocation of staking rewards between a staking customer and the platform. The primary contract `SplitRewards.sol` implements a pull-based approach for withdrawing validator rewards. For more information, see `contracts/split-rewards/README.md`.

### Batch Deposit

The contracts in the `batch-deposit` directory enable the customer to deploy more than one Ethereum validator at once. `BatchDeposit.sol` contract interacts with the Ethereum staking deposit contract, allowing multiple calls in a loop. For more information, see `contracts/batch-deposit/README.md`.

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

You can lint `.js` files with

``` shell
npm run lint:js
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

## Migrations

To migrate the contracts to a network:

``` shell
npx truffle migrate --network <network-name>
```

## Note

This project uses Truffle Suite for testing, deployment and smart contract management.
Please ensure you are familiar with it before proceeding.
