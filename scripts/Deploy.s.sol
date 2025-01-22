// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {StakingVaultV1} from "../src/StakingVault.v1.sol";
import {StakingVaultFactory} from "../src/StakingVaultFactory.sol";

import {BaseScript} from "./Base.s.sol";

contract DeployStakingVaultImplementation is BaseScript {
    function run() public broadcast returns (StakingVaultV1 v1) {
        v1 = new StakingVaultV1();
    }
}

contract DeployStakingVaultFactory is BaseScript {
    function run() public broadcast returns (StakingVaultFactory factory) {
        factory = new StakingVaultFactory(
            StakingVaultV1(
                payable(address(0xb4B46bdAA835F8E4b4d8e208B6559cD267851051))
            ),
            payable(address(0x8943545177806ED17B9F23F0a21ee5948eCaa776)),
            payable(address(0x8943545177806ED17B9F23F0a21ee5948eCaa776)),
            1_000
        );
    }
}

contract DeployStakingVaultProxy is BaseScript {
    function run() public broadcast returns (StakingVaultV1 proxy) {
        StakingVaultFactory factory = StakingVaultFactory(
            payable(address(0x17435ccE3d1B4fA2e5f8A08eD921D57C6762A180))
        );

        proxy = StakingVaultV1(payable(address(factory.createVault())));
    }
}

contract ApproveStakeQuota is BaseScript {
    function run() public broadcast {
        StakingVaultV1 proxy = StakingVaultV1(
            payable(address(0xc3d8108FC7f92B936552d658fc3dBC834193f344))
        );

        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/320eth-deposit.json"
        );
        string memory json = vm.readFile(path);
        bytes[] memory pubkeys = vm.parseJsonBytesArray(json, ".pubkeys");
        bytes[] memory signatures = vm.parseJsonBytesArray(json, ".signatures");
        uint256[] memory depositValues = vm.parseJsonUintArray(
            json,
            ".amounts"
        );

        proxy.approveStakeQuota(pubkeys, signatures, depositValues);
    }
}

contract StakeNow is BaseScript {
    function run() public broadcast {
        address payable proxy = payable(
            address(0xc3d8108FC7f92B936552d658fc3dBC834193f344)
        );

        (bool success, ) = proxy.call{value: 64 ether}("");

        console.log("Staking success: %s", success);
    }
}
