pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import { DepositContract } from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import { StakingVault } from "../src/StakingVault.sol";
import { StakingHub } from "../src/StakingHub.sol";

contract StakingVaultInitializationTest is Test {
    IDepositContract depositContract;
    StakingVault stakingVault;
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

    /// @dev Test the initial construction of the implementation contract
    function test_constructionOfTheImplementationContract() public view {
        // Expect the implementation contract state to be empty before initialization
        IDepositContract storedDepositContract = stakingVault.depositContractAddress();
        assertEq(address(storedDepositContract), address(0x0));
        assertFalse(stakingVault.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVault.feeRecipient(), address(0x0));
        assertEq(stakingVault.staker(), address(0x0));
        assertEq(stakingVault.feeBasisPoints(), 0);
    }

    /// @dev Test the initialization of proxy contracts
    function test_initializationOfAProxyContract() public {
        // The Staker initializes a proxy to the StakingVault
        vm.prank(staker);
        StakingVault stakingVaultProxy = stakingHub.createVault(0);

        // The proxy has another address than the implementation
        assertNotEq(address(stakingVault), address(stakingVaultProxy));

        // The staker, feeRecipient, and operator are the same for the proxy
        assertEq(stakingVaultProxy.staker(), staker);
        assertTrue(stakingVaultProxy.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);
        assertEq(stakingVaultProxy.feeBasisPoints(), feeBasisPoints);

        // The depositContractAddress is correctly set for the proxy
        IDepositContract storedDepositContract = stakingVaultProxy.depositContractAddress();
        assertEq(address(storedDepositContract), address(depositContract));

        // State updates only apply to the proxy, i.e., they do not
        // affect the implementation contract but only the proxy
        storedDepositContract = stakingVault.depositContractAddress();
        assertEq(address(storedDepositContract), address(0x0));
        assertFalse(stakingVault.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVault.feeRecipient(), address(0x0));
        assertEq(stakingVault.staker(), address(0x0));
    }

    /// @dev Test the initialization of a proxy contract with initial stake quota
    function test_initializationOfAProxyContractWithInitialStakeQuota() public {
        // The Staker initializes a proxy to the StakingVault
        vm.prank(staker);
        StakingVault stakingVaultProxy = stakingHub.createVault(320 ether);
    }

    /// @dev Stakers can create at most one vault
    function test_RevertWhen_stakerCreatesSecondVault() public {
        vm.startPrank(staker);

        // The staker does not yet have a vault
        assertEq(address(stakingHub.vaultOfStaker(staker)), address(0x0));

        // The first call to createVault should succeed
        stakingHub.createVault(0);
        StakingVault stakingVaultInstance = stakingHub.vaultOfStaker(staker);
        assertNotEq(address(stakingVaultInstance), address(0x0));

        // The second call to createVault should revert because the staker does already have a vault
        vm.expectRevert(StakingHub.OneVaultPerAddress.selector);
        stakingHub.createVault(0);

        vm.stopPrank();
    }

    /// @dev Test that the proxies of multiple stakers don't interfere with each other
    function test_stakersVaultsDontInterfereWithEachOther() public {
        address payable staker1 = payable(address(0x11));
        address payable staker2 = payable(address(0x12));

        // Initialize a StakingVault for Staker #1
        vm.prank(staker1);
        StakingVault stakingVaultProxy1 = stakingHub.createVault(0);

        // Initialize a StakingVault for Staker #2
        vm.prank(staker2);
        StakingVault stakingVaultProxy2 = stakingHub.createVault(0);

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

    /// @dev Test that updates to operators and feeRecipients in the
    /// implmentation contract are reflected in the proxies as well
    function test_updatesToOperatorsAndFeeRecipients() public {
        // A Staker initializes a proxy to the StakingVault
        vm.prank(staker);
        StakingVault stakingVaultProxy = stakingHub.createVault(0);

        // The feeRecipient and operator are the same for the proxy and the implementation
        assertTrue(stakingVaultProxy.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);

        // Update the default operator and feeRecipient in the factory contract
        address payable newOperator = payable(address(0x11));
        address payable newFeeRecipient = payable(address(0x12));
        vm.prank(operator);
        stakingHub.setDefaultOperator(newOperator);
        vm.prank(operator);
        stakingHub.setDefaultFeeRecipient(newFeeRecipient);

        // The default operator and feeRecipient in the factory contract are updated
        assertEq(stakingHub.defaultOperator(), newOperator);
        assertEq(stakingHub.defaultFeeRecipient(), newFeeRecipient);

        // The operator and feeRecipient in the implementation contract are not
        // affected by an update to the defaults in the factory contract
        assertFalse(stakingVault.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVault.feeRecipient(), address(0x0));

        // The operator and feeRecipient in the proxy have not changed
        assertTrue(stakingVaultProxy.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVaultProxy.feeRecipient(), feeRecipient);

        vm.prank(operator);
        stakingVaultProxy.setFeeRecipient(newFeeRecipient);

        // The operator and feeRecipient in the proxy have been updated
        assertEq(stakingVaultProxy.feeRecipient(), newFeeRecipient);
        // While the values in the implementation contract and inside of the
        // factory remain untouched
        assertEq(stakingHub.defaultOperator(), newOperator);
        assertEq(stakingHub.defaultFeeRecipient(), newFeeRecipient);
        assertFalse(stakingVault.hasRole(stakingVault.OPERATOR_ROLE(), operator));
        assertEq(stakingVault.feeRecipient(), address(0x0));
    }
}
