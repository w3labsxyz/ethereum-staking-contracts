// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { DepositContract } from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import { StakingVault } from "@src/StakingVault.sol";
import { StakingHub } from "@src/StakingHub.sol";

abstract contract StakingVaultSetup is Test {
    IDepositContract depositContract;
    StakingVault stakingVault;
    StakingVault stakingVaultProxy;
    StakingHub stakingHub;
    address payable operator;
    address payable feeRecipient;
    address payable staker;
    uint256 feeBasisPoints;
    address withdrawalRequestPredeployAddress = address(0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA);

    // before each
    function setUp() public virtual {
        operator = payable(address(0x01));
        feeRecipient = payable(address(0x02));
        staker = payable(address(0x03));
        feeBasisPoints = 1000;

        // Deploy the EIP-7002 contract
        string[] memory inputs = new string[](2);
        inputs[0] = "geas";
        inputs[1] = "lib/sys-asm/src/withdrawals/main.eas";
        bytes memory eip7002Bytecode = vm.ffi(inputs);
        vm.etch(withdrawalRequestPredeployAddress, eip7002Bytecode);
        vm.deal(withdrawalRequestPredeployAddress, 0 ether);

        // Deploy the native Ethereum Beacon Deposit Contract
        address dci = address(new DepositContract());
        vm.etch(address(0x4242424242424242424242424242424242424242), dci.code);
        depositContract = IDepositContract(address(0x4242424242424242424242424242424242424242));

        // Deploy our StakingVault implementation contract
        stakingVault = new StakingVault();

        // Deploy the StakingHub contract
        stakingHub = new StakingHub(stakingVault, operator, feeRecipient, feeBasisPoints);

        // Deploy one instance of the StakingVault, in the name of the staker
        vm.prank(staker);
        stakingVaultProxy = stakingHub.createVault(0);
    }
}
