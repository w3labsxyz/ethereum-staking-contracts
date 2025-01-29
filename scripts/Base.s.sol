// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Private key to be used in local development
    uint256 internal constant LOCALNET_PRIVATE_KEY = 0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31;

    /// @dev The private key used to sign transactions.
    uint256 internal privateKey;

    /// @dev Initializes the transaction broadcaster with the $PRIVATE_KEY or falls back to the default.
    constructor() {
        privateKey = vm.envOr("PRIVATE_KEY", LOCALNET_PRIVATE_KEY);

        address currentAddress = vm.addr(privateKey);

        console.log("Operating as %s", currentAddress);
    }

    modifier broadcast() {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }
}
