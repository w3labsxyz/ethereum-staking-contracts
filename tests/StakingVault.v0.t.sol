pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import { DepositContract } from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import { StakingVaultV0 } from "../src/StakingVault.v0.sol";
import { StakingVaultFactory } from "../src/StakingVaultFactory.sol";

contract StakingVaultV0Test is Test {
    IDepositContract depositContract;
    StakingVaultV0 stakingVault;
    StakingVaultFactory stakingVaultFactory;
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

        depositContract = new DepositContract();

        stakingVault = new StakingVaultV0();

        stakingVaultFactory =
            new StakingVaultFactory(stakingVault, operator, feeRecipient, feeBasisPoints, depositContract);
    }

    /// @notice Test the initial construction of the implementation contract
    function test_constructionOfTheImplementationContract() public view {
        // Expect the implementation contract state to be empty before initialization
        IDepositContract storedDepositContract = stakingVault.depositContractAddress();
        assertEq(address(storedDepositContract), address(0x0));
        assertEq(stakingVault.operator(), address(0x0));
        assertEq(stakingVault.feeRecipient(), address(0x0));
        assertEq(stakingVault.staker(), address(0x0));
        assertEq(stakingVault.feeBasisPoints(), 0);
    }

    /// @notice Test the initialization of proxy contracts
    function test_initializationOfAProxyContract() public {
        // The Staker initializes a proxy to the StakingVault
        vm.prank(staker);
        StakingVaultV0 stakingVaultProxy = StakingVaultV0(stakingVaultFactory.createVault());

        // The proxy has another address than the implementation
        assertNotEq(address(stakingVault), address(stakingVaultProxy));

        // The staker, feeRecipient, and operator are the same for the proxy
        assertEq(stakingVaultProxy.staker(), staker);
        assertEq(stakingVaultProxy.operator(), operator);
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);
        assertEq(stakingVaultProxy.feeBasisPoints(), feeBasisPoints);

        // The depositContractAddress is correctly set for the proxy
        IDepositContract storedDepositContract = stakingVaultProxy.depositContractAddress();
        assertEq(address(storedDepositContract), address(depositContract));

        // State updates only apply to the proxy, i.e., they do not
        // affect the implementation contract but only the proxy
        storedDepositContract = stakingVault.depositContractAddress();
        assertEq(address(storedDepositContract), address(0x0));
        assertEq(stakingVault.operator(), address(0x0));
        assertEq(stakingVault.feeRecipient(), address(0x0));
        assertEq(stakingVault.staker(), address(0x0));
    }

    /// @notice Stakers can create at most one vault
    function test_RevertWhen_stakerCreatesSecondVault() public {
        vm.startPrank(staker);

        // The staker does not yet have a vault
        assertEq(address(stakingVaultFactory.vaultForAddress(staker)), address(0x0));

        // The first call to createVault should succeed
        stakingVaultFactory.createVault();
        StakingVaultV0 stakingVaultInstance = stakingVaultFactory.vaultForAddress(staker);
        assertNotEq(address(stakingVaultInstance), address(0x0));

        // The second call to createVault should revert because the staker does already have a vault
        vm.expectRevert(StakingVaultFactory.OneVaultPerAddress.selector);
        stakingVaultFactory.createVault();

        vm.stopPrank();
    }

    /// @notice Test that the proxies of multiple stakers don't interfere with each other
    function test_stakersVaultsDontInterfereWithEachOther() public {
        address payable staker1 = payable(address(0x11));
        address payable staker2 = payable(address(0x12));

        // Initialize a StakingVault for Staker #1
        vm.prank(staker1);
        StakingVaultV0 stakingVaultProxy1 = StakingVaultV0(stakingVaultFactory.createVault());

        // Initialize a StakingVault for Staker #2
        vm.prank(staker2);
        StakingVaultV0 stakingVaultProxy2 = StakingVaultV0(stakingVaultFactory.createVault());

        // The staker is set for each stakingVaultProxy individually
        assertEq(stakingVaultProxy1.staker(), staker1);
        assertEq(stakingVaultProxy2.staker(), staker2);

        // Updating the feeRecipient in one proxy does not affect the other
        address payable newFeeRecipient = payable(address(0x13));
        vm.prank(operator);
        stakingVaultProxy1.setFeeRecipient(newFeeRecipient);
        assertEq(stakingVaultProxy1.feeRecipient(), newFeeRecipient);
        assertEq(stakingVaultProxy2.feeRecipient(), feeRecipient);
    }

    /// @notice Test that updates to operators and feeRecipients in the
    /// implmentation contract are reflected in the proxies as well
    function test_updatesToOperatorsAndFeeRecipients() public {
        // A Staker initializes a proxy to the StakingVault
        vm.prank(staker);
        StakingVaultV0 stakingVaultProxy = StakingVaultV0(stakingVaultFactory.createVault());

        // The feeRecipient and operator are the same for the proxy and the implementation
        assertEq(stakingVaultProxy.operator(), operator);
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);

        // Update the default operator and feeRecipient in the factory contract
        address payable newOperator = payable(address(0x11));
        address payable newFeeRecipient = payable(address(0x12));
        stakingVaultFactory.setDefaultOperator(newOperator);
        stakingVaultFactory.setDefaultFeeRecipient(newFeeRecipient);

        // The default operator and feeRecipient in the factory contract are updated
        assertEq(stakingVaultFactory.defaultOperator(), newOperator);
        assertEq(stakingVaultFactory.defaultFeeRecipient(), newFeeRecipient);

        // The operator and feeRecipient in the implementation contract are not
        // affected by an update to the defaults in the factory contract
        assertEq(stakingVault.operator(), address(0x0));
        assertEq(stakingVault.feeRecipient(), address(0x0));

        // The operator and feeRecipient in the proxy have not changed
        assertEq(stakingVaultProxy.operator(), operator);
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);

        // Updating the operator and feeRecipient in the proxy contract
        // can be done by the operator in the proxy contract directly
        vm.prank(operator);
        stakingVaultProxy.setOperator(newOperator);

        vm.prank(operator);
        // The previous operator is not anymore permitted to apply updates
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        stakingVaultProxy.setFeeRecipient(newFeeRecipient);

        // But the new operator can apply updates
        vm.prank(newOperator);
        stakingVaultProxy.setFeeRecipient(newFeeRecipient);

        // The operator and feeRecipient in the proxy have been updated
        assertEq(stakingVaultProxy.operator(), newOperator);
        assertEq(stakingVaultProxy.feeRecipient(), newFeeRecipient);
        // While the values in the implementation contract and inside of the
        // factory remain untouched
        assertEq(stakingVaultFactory.defaultOperator(), newOperator);
        assertEq(stakingVaultFactory.defaultFeeRecipient(), newFeeRecipient);
        assertEq(stakingVault.operator(), address(0x0));
        assertEq(stakingVault.feeRecipient(), address(0x0));
    }
}

// TODO: Test invalid fee basis points
