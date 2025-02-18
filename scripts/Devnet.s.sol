// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {StakingHub} from "../src/StakingHub.sol";

import {BaseScript} from "./Base.s.sol";

contract DeployStakingVaultProxy is BaseScript {
    function run(StakingHub stakingHub) public broadcast {
        // Staker private Key
        uint256 stakerKey = 0x53321db7c1e331d93a11a41d16f004d7ff63972ec8ec7c25db329728ceeb1710;
        address staker = address(0x614561D2d143621E126e87831AEF287678B442b8);

        // Deploy a proxy for the staker
        vm.stopBroadcast();
        vm.startBroadcast(stakerKey);
        StakingVault stakingVaultProxy = stakingHub.createVault(128 ether);

        console.log("Staker: %s", staker);
        console.log(
            "StakingVault (of the Staker): %s",
            address(stakingVaultProxy)
        );
    }
}

contract RequestStakQuotaOnStakingVaultProxy is BaseScript {
    function run(
        StakingHub stakingHub,
        uint256 numberOfValidators
    ) public broadcast {
        // Staker private Key
        uint256 stakerKey = 0x53321db7c1e331d93a11a41d16f004d7ff63972ec8ec7c25db329728ceeb1710;
        address staker = address(0x614561D2d143621E126e87831AEF287678B442b8);

        // Deploy a proxy for the staker
        vm.stopBroadcast();
        vm.startBroadcast(stakerKey);
        StakingVault stakingVaultProxy = stakingHub.vaultOfStaker(staker);
        stakingVaultProxy.requestStakeQuota(numberOfValidators * 32 ether);

        console.log(
            "Staker %s has requested to stake on 100 Validators",
            staker
        );
    }
}
