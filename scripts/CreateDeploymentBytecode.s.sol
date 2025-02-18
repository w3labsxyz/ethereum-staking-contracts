// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {StakingHub} from "../src/StakingHub.sol";

import {BaseScript} from "./Base.s.sol";

contract CreateStakingVaultDeploymentBytecode is BaseScript {
    function run() external returns (bytes memory) {
        bytes memory bytecode = abi.encodePacked(
            type(StakingVault).creationCode
        );

        vm.writeFile("out/CreateStakingVault.bytecode", vm.toString(bytecode));
        return bytecode;
    }
}

contract CreateStakingHubDeploymentBytecode is BaseScript {
    function run(
        address stakingVaultImplementation,
        address operator,
        address feeRecipient,
        uint256 feeBasisPoints
    ) external returns (bytes memory) {
        bytes memory bytecode = abi.encodePacked(
            type(StakingHub).creationCode,
            abi.encode(
                stakingVaultImplementation,
                operator,
                feeRecipient,
                feeBasisPoints
            )
        );

        vm.writeFile("out/CreateStakingHub.bytecode", vm.toString(bytecode));
        return bytecode;
    }
}
