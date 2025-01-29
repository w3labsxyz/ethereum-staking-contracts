pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import { DepositContract } from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import { StakingVault } from "../src/StakingVault.sol";
import { StakingHub } from "../src/StakingHub.sol";
import { EIP7002 } from "../src/EIP7002.sol";

contract StakingVaultV2 is StakingVault {
    /// @dev Initialize the upgraded implementation contract
    function initializeV2(uint256 newFeeBasisPoints) external reinitializer(2) {
        _feeBasisPoints = newFeeBasisPoints;

        // @dev Override the eip-7002 address
        _withdrawalRequestPredeployAddress = address(0xabcd);
    }

    /// @dev Override
    function recommendedWithdrawalRequestsFee(uint256 numberOfWithdrawalRequests) external override returns (uint256) {
        return 2 * _recommendedWithdrawalRequestsFee(numberOfWithdrawalRequests);
    }
}

contract StakingVaultUpgradesTest is Test {
    IDepositContract depositContract;
    StakingVault stakingVault;
    StakingVaultV2 stakingVaultV2;
    StakingHub stakingHub;
    address payable operator;
    address payable feeRecipient;
    address payable staker;
    uint256 feeBasisPoints;

    // before each
    function setUp() public {
        operator = payable(address(0x01));
        feeRecipient = payable(address(0x02));
        staker = payable(address(0x03));
        feeBasisPoints = 1000;

        // Deploy the native Ethereum Deposit Contract to
        // the commonly used address 0x4242424242424242424242424242424242424242
        address dci = address(new DepositContract());
        vm.etch(address(0x4242424242424242424242424242424242424242), dci.code);
        depositContract = IDepositContract(address(0x4242424242424242424242424242424242424242));

        stakingVault = new StakingVault();

        stakingHub = new StakingHub(stakingVault, operator, feeRecipient, feeBasisPoints);
    }

    /// @dev Test the upgradeability of the staking vault
    function test_upgrade() public {
        // Deploy the EIP-7002 contract to 0xabcd
        string[] memory inputs = new string[](2);
        inputs[0] = "geas";
        inputs[1] = "lib/sys-asm/src/withdrawals/main.eas";
        bytes memory eip7002Bytecode = vm.ffi(inputs);
        vm.etch(address(0xabcd), eip7002Bytecode);

        // Deploy one instance of the StakingVault, in the name of the staker
        vm.prank(staker);
        StakingVault stakingVaultProxy = stakingHub.createVault(0);

        assertEq(stakingVaultProxy.feeBasisPoints(), 1000);

        // The following reverts because the staking vault proxy does not yet
        // point to eip-7002 at 0xabcd
        vm.expectRevert(EIP7002.EIP7002ContractNotDeployed.selector);
        stakingVaultProxy.recommendedWithdrawalRequestsFee(1);

        stakingVaultV2 = new StakingVaultV2();

        // The operator may not upgrade the contract
        vm.prank(operator);
        vm.expectRevert();
        stakingVaultProxy.upgradeToAndCall(
            address(stakingVaultV2), abi.encodeWithSelector(StakingVaultV2.initializeV2.selector, 900)
        );

        // Upgrade the proxy to the new implementation
        vm.prank(staker);
        stakingVaultProxy.upgradeToAndCall(
            address(stakingVaultV2), abi.encodeWithSelector(StakingVaultV2.initializeV2.selector, 900)
        );

        assertEq(stakingVaultProxy.feeBasisPoints(), 900);
        assertEq(stakingVaultProxy.recommendedWithdrawalRequestsFee(1), 2);
    }
}
