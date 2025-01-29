// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";
import { StakingVault } from "../src/StakingVault.sol";
import { StakingHub } from "../src/StakingHub.sol";

import { BaseScript } from "./Base.s.sol";

contract DeployDevnet is BaseScript {
    function run() public broadcast {
        uint256 feeBasisPoints = 1000;

        // Private Key #1
        address payable operator = payable(address(0x8943545177806ED17B9F23F0a21ee5948eCaa776));

        // Private Key #2
        address payable feeRecipient = payable(address(0xE25583099BA105D9ec0A67f5Ae86D90e50036425));

        // Private Key #3
        address payable staker = payable(address(0x614561D2d143621E126e87831AEF287678B442b8));

        // Deploy our StakingVault implementation contract
        StakingVault stakingVaultImplementation = new StakingVault();

        // Deploy the StakingHub contract
        StakingHub StakingHub = new StakingHub(stakingVaultImplementation, operator, feeRecipient, feeBasisPoints);

        // Deploy a proxy for the staker
        // TODO: call as staker
        StakingVault stakingVaultProxy = StakingHub.createVault(0);

        console.log("Operator: %s", operator);
        console.log("Fee recipient: %s", feeRecipient);
        console.log("Staker: %s", staker);
        console.log("StakingVault (Implementation): %s", address(stakingVaultImplementation));
        console.log("StakingHub: %s", address(StakingHub));
        console.log("StakingVault (of the Staker): %s", address(stakingVaultProxy));
    }
}
