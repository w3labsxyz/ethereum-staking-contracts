pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDepositContract} from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import {DepositContract} from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {StakingVaultFactory} from "../src/StakingVaultFactory.sol";

abstract contract StakingVaultSetup is Test {
    IDepositContract depositContract;
    StakingVault stakingVault;
    StakingVault stakingVaultProxy;
    StakingVaultFactory stakingVaultFactory;
    address payable operator;
    address payable feeRecipient;
    address payable staker;
    uint256 feeBasisPoints;
    address withdrawalRequestPredeployAddress =
        address(0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA);

    // before each
    function setUp() public {
        operator = payable(address(0x01));
        feeRecipient = payable(address(0x02));
        staker = payable(address(0x03));
        feeBasisPoints = 1_000;

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
        depositContract = IDepositContract(
            address(0x4242424242424242424242424242424242424242)
        );

        // Deploy our StakingVault implementation contract
        stakingVault = new StakingVault();

        // Deploy the StakingVaultFactory contract
        stakingVaultFactory = new StakingVaultFactory(
            stakingVault,
            operator,
            feeRecipient,
            feeBasisPoints
        );

        // Deploy one instance of the StakingVault, in the name of the staker
        vm.prank(staker);
        stakingVaultProxy = StakingVault(
            payable(address(stakingVaultFactory.createVault()))
        );
    }
}

contract StakingVaultV1Test is Test, StakingVaultSetup {
    /// @dev Even though redundant, we create a dedicated test for the creation
    /// of the StakingVault in order to be able to report the gas costs.
    function test_successfulCreationOfAStakingVault() public {
        // The Staker initializes a proxy to the StakingVault
        vm.prank(address(0x99));
        StakingVault(payable(address(stakingVaultFactory.createVault())));
    }

    /// @dev `requestStakeQuota` can only be called by the staker
    function test_RevertWhen_nonStakerRequestStakeQuota() public {
        // The operator is not permitted to request a stake quota
        vm.prank(operator);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        stakingVaultProxy.requestStakeQuota(32 ether);
    }

    /// @dev `requestStakeQuota` can be called by the staker
    function test_successfulStakeQuotaRequest() public {
        // The Staker requests a stake quota
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(32 ether);
    }

    using stdJson for string;

    struct DepositData {
        bytes pubkey;
        bytes withdrawal_credentials;
        bytes signature;
        uint256 amount;
        bytes32 deposit_data_root;
        bytes32 deposit_message_root;
        string fork_version;
    }

    /// @dev `approveStakeQuota` can register one deposit data
    function test_successfulStakingOf32Ether() public {
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(32 ether);

        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/32eth-deposit.json"
        );
        string memory json = vm.readFile(path);
        // bytes memory data = vm.parseJson(json);
        // DepositData memory depositData = abi.decode(data, (DepositData));
        bytes[] memory pubkeys = vm.parseJsonBytesArray(json, ".pubkeys");
        bytes[] memory signatures = vm.parseJsonBytesArray(json, ".signatures");
        uint256[] memory depositValues = vm.parseJsonUintArray(
            json,
            ".amounts"
        );

        console.log("Staking vault proxy: %s", address(stakingVaultProxy));

        // The operator approves the stake quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(pubkeys, signatures, depositValues);

        StakingVault.DepositData[] memory pd = stakingVaultProxy.depositData(
            32 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 32 ether);
        assertEq(pd[0].pubkey, pubkeys[0]);
        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[0]")
        );
        assertEq(pd[0].signature, signatures[0]);
        assertEq(
            pd[0].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[0]")
        );
        assertEq(pd[0].depositValue, depositValues[0]);

        // The staker sends Ether to the vault in order to stake them
        vm.deal(staker, 33 ether);

        assertEq(operator.balance, 0 ether);
        vm.prank(staker);
        (bool success, ) = payable(operator).call{value: 1 ether}("");
        assertTrue(success, "Call failed");

        assertEq(operator.balance, 1 ether);

        assertEq(staker.balance, 32 ether);

        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 0 ether);

        vm.prank(staker);
        (success, ) = payable(stakingVaultProxy).call{value: 31 ether}("");
        assertFalse(
            success,
            "Call succeeded, but should have failed because msg.value < 32 ether"
        );

        // The staker sent 31 Ether, which was reverted. Therefore, the staker
        // still has 32 Ether.
        assertEq(staker.balance, 32 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 0 ether);

        vm.deal(staker, 33 ether);
        assertEq(staker.balance, 33 ether);
        vm.prank(staker);
        (success, ) = payable(stakingVaultProxy).call{value: 33 ether}("");
        assertFalse(
            success,
            "Call succeeded, but should have failed because msg.value was 33 ether"
        );

        // The staker sent 33 Ether, which was reverted. Therefore, the staker
        // still has 33 Ether.
        assertEq(staker.balance, 33 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 0 ether);

        vm.prank(staker);
        (success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertTrue(success, "Call failed");

        assertEq(staker.balance, 1 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 32 ether);
    }

    /// @dev `approveStakeQuota` can register ten deposit data
    function test_successfulStakingOf64Ether() public {
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(64 ether);

        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/64eth-deposit.json"
        );
        string memory json = vm.readFile(path);
        bytes[] memory pubkeys = vm.parseJsonBytesArray(json, ".pubkeys");
        bytes[] memory signatures = vm.parseJsonBytesArray(json, ".signatures");
        uint256[] memory depositValues = vm.parseJsonUintArray(
            json,
            ".amounts"
        );

        // The operator approves the stake quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(pubkeys, signatures, depositValues);

        StakingVault.DepositData[] memory pd = stakingVaultProxy.depositData(
            64 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 64 ether);
        assertEq(pd[0].pubkey, pubkeys[0]);
        assertEq(pd[1].pubkey, pubkeys[1]);

        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[0]")
        );
        assertEq(
            pd[1].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[1]")
        );

        assertEq(pd[0].signature, signatures[0]);
        assertEq(pd[1].signature, signatures[1]);

        assertEq(
            pd[0].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[0]")
        );
        assertEq(
            pd[1].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[1]")
        );

        assertEq(pd[0].depositValue, depositValues[0]);
        assertEq(pd[1].depositValue, depositValues[1]);

        // Now the staker actually stakes, i.e., sends the funds

        vm.deal(staker, 64 ether);
        vm.prank(staker);
        (bool success, ) = payable(stakingVaultProxy).call{value: 64 ether}("");
        assertTrue(success, "Call failed");

        assertEq(staker.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 64 ether);
    }

    /// @dev `approveStakeQuota` can register ten deposit data
    function test_successfulStakingOf320Ether() public {
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(320 ether);

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

        // The operator approves the stake quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(pubkeys, signatures, depositValues);

        StakingVault.DepositData[] memory pd = stakingVaultProxy.depositData(
            320 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 320 ether);
        assertEq(pd[0].pubkey, pubkeys[0]);
        assertEq(pd[1].pubkey, pubkeys[1]);
        assertEq(pd[2].pubkey, pubkeys[2]);
        assertEq(pd[3].pubkey, pubkeys[3]);
        assertEq(pd[4].pubkey, pubkeys[4]);
        assertEq(pd[5].pubkey, pubkeys[5]);
        assertEq(pd[6].pubkey, pubkeys[6]);
        assertEq(pd[7].pubkey, pubkeys[7]);
        assertEq(pd[8].pubkey, pubkeys[8]);
        assertEq(pd[9].pubkey, pubkeys[9]);

        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[0]")
        );
        assertEq(
            pd[1].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[1]")
        );
        assertEq(
            pd[2].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[2]")
        );
        assertEq(
            pd[3].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[3]")
        );
        assertEq(
            pd[4].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[4]")
        );
        assertEq(
            pd[5].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[5]")
        );
        assertEq(
            pd[6].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[6]")
        );
        assertEq(
            pd[7].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[7]")
        );
        assertEq(
            pd[8].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[8]")
        );
        assertEq(
            pd[9].withdrawalCredentials,
            vm.parseJsonBytes32(json, ".withdrawal_credentials[9]")
        );

        assertEq(pd[0].signature, signatures[0]);
        assertEq(pd[1].signature, signatures[1]);
        assertEq(pd[2].signature, signatures[2]);
        assertEq(pd[3].signature, signatures[3]);
        assertEq(pd[4].signature, signatures[4]);
        assertEq(pd[5].signature, signatures[5]);
        assertEq(pd[6].signature, signatures[6]);
        assertEq(pd[7].signature, signatures[7]);
        assertEq(pd[8].signature, signatures[8]);
        assertEq(pd[9].signature, signatures[9]);

        assertEq(
            pd[0].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[0]")
        );
        assertEq(
            pd[1].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[1]")
        );
        assertEq(
            pd[2].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[2]")
        );
        assertEq(
            pd[3].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[3]")
        );
        assertEq(
            pd[4].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[4]")
        );
        assertEq(
            pd[5].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[5]")
        );
        assertEq(
            pd[6].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[6]")
        );
        assertEq(
            pd[7].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[7]")
        );
        assertEq(
            pd[8].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[8]")
        );
        assertEq(
            pd[9].depositDataRoot,
            vm.parseJsonBytes32(json, ".deposit_data_roots[9]")
        );

        assertEq(pd[0].depositValue, depositValues[0]);
        assertEq(pd[1].depositValue, depositValues[1]);
        assertEq(pd[2].depositValue, depositValues[2]);
        assertEq(pd[3].depositValue, depositValues[3]);
        assertEq(pd[4].depositValue, depositValues[4]);
        assertEq(pd[5].depositValue, depositValues[5]);
        assertEq(pd[6].depositValue, depositValues[6]);
        assertEq(pd[7].depositValue, depositValues[7]);
        assertEq(pd[8].depositValue, depositValues[8]);
        assertEq(pd[9].depositValue, depositValues[9]);

        // Now the staker actually stakes, i.e., sends the funds

        vm.deal(staker, 320 ether);
        vm.prank(staker);
        (bool success, ) = payable(stakingVaultProxy).call{value: 320 ether}(
            ""
        );
        assertTrue(success, "Call failed");

        assertEq(staker.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 320 ether);
    }

    function test_claimingSemantics() public {
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(64 ether);

        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/64eth-deposit.json"
        );
        string memory json = vm.readFile(path);
        bytes[] memory pubkeys = vm.parseJsonBytesArray(json, ".pubkeys");
        bytes[] memory signatures = vm.parseJsonBytesArray(json, ".signatures");
        uint256[] memory depositValues = vm.parseJsonUintArray(
            json,
            ".amounts"
        );

        // The operator approves the stake quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(pubkeys, signatures, depositValues);

        vm.deal(staker, 64 ether);
        vm.prank(staker);
        (bool success, ) = payable(stakingVaultProxy).call{value: 64 ether}("");
        assertTrue(success, "Call failed");

        assertEq(staker.balance, 0 ether);
        assertEq(operator.balance, 0 ether);
        assertEq(feeRecipient.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 64 ether);

        // Simulate that 1 Ether has accumulated in rewards in the vault
        vm.deal(address(stakingVaultProxy), 1 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0.9 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.1 ether);

        // Only the staker can claim the rewards
        vm.prank(operator);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        stakingVaultProxy.claimRewards();

        // Only the operator can claim the fees
        vm.prank(staker);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        stakingVaultProxy.claimFees();

        vm.prank(staker);
        stakingVaultProxy.claimRewards();

        // The balances have been updated accordingly
        assertEq(staker.balance, 0.9 ether);
        assertEq(operator.balance, 0 ether);
        assertEq(feeRecipient.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0.1 ether);
        // Now there are no claimable rewards left, but the fees are still there
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.1 ether);

        // Simulate that new rewards have accumulated in the vault
        vm.deal(address(stakingVaultProxy), 0.2 ether);
        // Of these 0.2 Ether, 0.1 Ether are unclaimed fees and 0.01 Ether are new fees
        assertEq(stakingVaultProxy.claimableRewards(), 0.09 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.11 ether);

        // The staker can claim the rewards
        vm.prank(staker);
        stakingVaultProxy.claimRewards();

        // The balances have been updated accordingly
        assertEq(staker.balance, 0.99 ether);
        assertEq(operator.balance, 0 ether);
        assertEq(feeRecipient.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0.11 ether);
        // Now there are no claimable rewards left, but the fees are still there
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.11 ether);

        // Adding more 0.09 Ether in new staking rewards
        vm.deal(address(stakingVaultProxy), 0.21 ether);
        // We end up with 0.11 Ether unclaimed fees + 0.001 Ether new fees
        // and 0.009 Ether new rewards
        assertEq(stakingVaultProxy.claimableRewards(), 0.09 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.12 ether);

        // The operator can claim the fees
        vm.prank(operator);
        stakingVaultProxy.claimFees();
        // The staker can claim the rewards
        vm.prank(staker);
        stakingVaultProxy.claimRewards();

        // The balances have been updated accordingly
        assertEq(staker.balance, 1.08 ether);
        assertEq(operator.balance, 0.0 ether);
        assertEq(feeRecipient.balance, 0.12 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);

        // Adding more 1 Ether in new staking rewards
        vm.deal(address(stakingVaultProxy), 1 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0.9 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.1 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);

        // We are adding some rewards again but the the staker request unbonding
        // 32 Ether of the principal
        bytes[] memory unbondingPubkeys = new bytes[](1);
        unbondingPubkeys[0] = pubkeys[0];
        vm.prank(staker);
        stakingVaultProxy.requestUnbondings{value: 1234 wei}(unbondingPubkeys);
        // Refund the withdrawal fee sent (to simplify subsequent assertions)
        vm.deal(staker, staker.balance + 1234 wei);

        // The unbonding fee ends up in the eip-7002 contract, not in the vault
        assertEq(address(stakingVaultProxy).balance, 1 ether);
        assertEq(withdrawalRequestPredeployAddress.balance, 1234 wei);

        assertEq(stakingVaultProxy.stakedBalance(), 32 ether);

        // After the unbonding, the principal takes preference over fees and
        // rewards. The staker will now be able to claim any remainder until
        // the principal has been paid out.
        // Even though the 1 Ether in the vault right now are rewards, the
        // staker can withdraw them as principal.
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 1 ether);

        // Only the staker can withdraw withdrawable principal
        vm.prank(operator);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        stakingVaultProxy.withdrawPrincipal();

        vm.prank(staker);
        stakingVaultProxy.withdrawPrincipal();

        // After the withdrawal, the staker has received the principal
        assertEq(staker.balance, 2.08 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);

        // Simulating some more rewards to accrue before the actual principal arrives in the vault
        vm.deal(address(stakingVaultProxy), 1 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 1 ether);

        // And withdrawing the principal again leads to:
        vm.prank(staker);
        stakingVaultProxy.withdrawPrincipal();
        assertEq(staker.balance, 3.08 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);

        // Now we finally receive the principal back from the beacon chain
        // including some additional rewards. This leaves us with the 2 * 1 Ether
        // rewards that have been withdrawn as principal above and the 32 Ether
        // pricipal arriving now plus 0.1 Ether rewards that the principal comes with.
        vm.deal(address(stakingVaultProxy), 32.1 ether);
        // Of which we expect 2.1 ether to be billable rewards and 30 Ether to be principal
        assertEq(stakingVaultProxy.claimableRewards(), 1.89 ether); // 90 % of 2.1 Ether
        assertEq(stakingVaultProxy.claimableFees(), 0.21 ether); // 10 % of 2.1 Ether
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 30 ether);

        // Withdrawing the principal now doesn't affect the rewards
        vm.prank(staker);
        stakingVaultProxy.withdrawPrincipal();
        assertEq(staker.balance, 33.08 ether);
        assertEq(address(stakingVaultProxy).balance, 2.1 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 1.89 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0.21 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);

        // Claiming fees doesn't affect the claimable rewards
        assertEq(feeRecipient.balance, 0.12 ether);
        vm.prank(operator);
        stakingVaultProxy.claimFees();
        assertEq(staker.balance, 33.08 ether);
        assertEq(feeRecipient.balance, 0.33 ether);
        assertEq(address(stakingVaultProxy).balance, 1.89 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 1.89 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);

        // And rewards can be claimed too
        vm.prank(staker);
        stakingVaultProxy.claimRewards();
        assertEq(staker.balance, 34.97 ether);
        assertEq(feeRecipient.balance, 0.33 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(stakingVaultProxy.claimableRewards(), 0 ether);
        assertEq(stakingVaultProxy.claimableFees(), 0 ether);
        assertEq(stakingVaultProxy.withdrawablePrincipal(), 0 ether);
    }

    /// @dev `requestStakeQuota` reverts for non-32 ETH multiples
    function test_revertNonMultipleOf32Ether() public {
        // Test values less than 32 ETH
        vm.prank(staker);
        vm.expectRevert(); // Add specific error if defined in contract
        stakingVaultProxy.requestStakeQuota(16 ether);

        // Test values greater than 32 ETH but not multiple
        vm.prank(staker);
        vm.expectRevert();
        stakingVaultProxy.requestStakeQuota(40 ether);

        // Test odd multiples
        vm.prank(staker);
        vm.expectRevert();
        stakingVaultProxy.requestStakeQuota(33 ether);

        // Test decimal multiples
        vm.prank(staker);
        vm.expectRevert();
        stakingVaultProxy.requestStakeQuota(32.5 ether);

        // Verify that correct multiple still works
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(64 ether);

        // Test very large non-multiple amount
        vm.prank(staker);
        vm.expectRevert();
        stakingVaultProxy.requestStakeQuota(1000 ether);
    }

    /// @dev Tests depositor management and staking permissions
    function test_depositorManagementAndStaking() public {
        address payable depositor1 = payable(address(0x11));
        address payable depositor2 = payable(address(0x12));

        // Request stake quota
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(64 ether);

        // Set up deposit data
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/64eth-deposit.json"
        );
        string memory json = vm.readFile(path);
        bytes[] memory pubkeys = vm.parseJsonBytesArray(json, ".pubkeys");
        bytes[] memory signatures = vm.parseJsonBytesArray(json, ".signatures");
        uint256[] memory depositValues = vm.parseJsonUintArray(
            json,
            ".amounts"
        );

        // Operator approves the stake quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(pubkeys, signatures, depositValues);

        // Test that non-depositor can't stake
        vm.deal(depositor1, 32 ether);
        vm.prank(depositor1);
        (bool success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertFalse(
            success,
            "Unauthorized depositor should not be able to stake"
        );

        // Add depositor1
        vm.prank(staker);
        stakingVaultProxy.addDepositor(depositor1);

        // Verify depositor1 can now stake
        vm.deal(depositor1, 32 ether);
        vm.prank(depositor1);
        (success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertTrue(success, "Authorized depositor should be able to stake");
        assertEq(address(depositContract).balance, 32 ether);

        // Add depositor2
        vm.prank(staker);
        stakingVaultProxy.addDepositor(depositor2);

        // Verify depositor2 can stake
        vm.deal(depositor2, 32 ether);
        vm.prank(depositor2);
        (success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertTrue(success, "Second depositor should be able to stake");
        assertEq(address(depositContract).balance, 64 ether);

        // Remove depositor1
        vm.prank(staker);
        stakingVaultProxy.removeDepositor(depositor1);

        // Verify removed depositor can't stake anymore
        vm.deal(depositor1, 32 ether);
        vm.prank(depositor1);
        (success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertFalse(success, "Removed depositor should not be able to stake");

        // Test invalid depositor management
        vm.prank(staker);
        vm.expectRevert(); // ZeroAddress error
        stakingVaultProxy.addDepositor(payable(address(0)));

        vm.prank(staker);
        vm.expectRevert(); // ZeroAddress error
        stakingVaultProxy.removeDepositor(payable(address(0)));

        // Test that staker can't be removed as depositor
        vm.prank(staker);
        vm.expectRevert(); // InvalidRoleRemoval error
        stakingVaultProxy.removeDepositor(payable(staker));

        // Test that only staker can manage depositors
        vm.prank(depositor2);
        vm.expectRevert(); // AccessControl error
        stakingVaultProxy.addDepositor(depositor1);

        vm.prank(depositor2);
        vm.expectRevert(); // AccessControl error
        stakingVaultProxy.removeDepositor(depositor1);
    }

    /// @dev Tests sequential staking with multiple quota requests and approvals
    function test_sequentialStakingWithMultipleQuotas() public {
        // First round - 32 ETH
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(32 ether);

        // Load 32 ETH deposit data
        string memory root = vm.projectRoot();
        string memory path32 = string.concat(
            root,
            "/tests/fixtures/32eth-deposit.json"
        );
        string memory json32 = vm.readFile(path32);
        bytes[] memory pubkeys32 = vm.parseJsonBytesArray(json32, ".pubkeys");
        bytes[] memory signatures32 = vm.parseJsonBytesArray(
            json32,
            ".signatures"
        );
        uint256[] memory depositValues32 = vm.parseJsonUintArray(
            json32,
            ".amounts"
        );

        // Operator approves first quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(
            pubkeys32,
            signatures32,
            depositValues32
        );

        // Verify deposit data for full amount
        StakingVault.DepositData[] memory pd = stakingVaultProxy.depositData(
            32 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 32 ether);
        assertEq(pd[0].pubkey, pubkeys32[0]);
        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes32(json32, ".withdrawal_credentials[0]")
        );
        assertEq(pd[0].signature, signatures32[0]);
        assertEq(
            pd[0].depositDataRoot,
            vm.parseJsonBytes32(json32, ".deposit_data_roots[0]")
        );
        assertEq(pd[0].depositValue, depositValues32[0]);

        // Stake first 32 ETH
        vm.deal(staker, 32 ether);
        vm.prank(staker);
        (bool success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertTrue(success, "First stake failed");
        assertEq(address(depositContract).balance, 32 ether);

        // Second round - 64 ETH
        vm.prank(staker);
        stakingVaultProxy.requestStakeQuota(64 ether);

        // Load 64 ETH deposit data
        string memory path64 = string.concat(
            root,
            "/tests/fixtures/64eth-deposit.json"
        );
        string memory json64 = vm.readFile(path64);
        bytes[] memory pubkeys64 = vm.parseJsonBytesArray(json64, ".pubkeys");
        bytes[] memory signatures64 = vm.parseJsonBytesArray(
            json64,
            ".signatures"
        );
        uint256[] memory depositValues64 = vm.parseJsonUintArray(
            json64,
            ".amounts"
        );

        // Operator approves second quota
        vm.prank(operator);
        stakingVaultProxy.approveStakeQuota(
            pubkeys64,
            signatures64,
            depositValues64
        );

        // Verify deposit data for full amount
        pd = stakingVaultProxy.depositData(64 ether);

        // Verify last two validator data (from 64 ETH deposit)
        assertEq(pd[0].pubkey, pubkeys64[0]);
        assertEq(pd[1].pubkey, pubkeys64[1]);

        // Stake second quota (64 ETH)
        vm.deal(staker, 64 ether);
        vm.prank(staker);
        (success, ) = payable(stakingVaultProxy).call{value: 64 ether}("");
        assertTrue(success, "Second stake failed");

        // Verify final balances
        assertEq(address(depositContract).balance, 96 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(staker.balance, 0 ether);
    }

    /// @dev Tests fee estimation for requesting withdrawals via EIP-7002
    function test_feeRecommendationForUnbondingRequests() public {
        address wrpa = withdrawalRequestPredeployAddress;

        // Assume the base fee is currently 10 wei
        vm.mockCall(wrpa, bytes(""), abi.encode(10));

        // We assume that there is exactly one free slot in the withdrawal queue.
        // Therefore, the recommended fee for one unbonding would equal the base fee.
        uint256 fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(1);
        assertEq(fee, 10 wei);

        // When withdrawing two slots, the fee would be increased exponentially
        fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(2);
        assertEq(fee, 10 wei);

        // ... but stay the same for three
        fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(3);
        assertEq(fee, 11 wei);

        // ... and exponentially increase again for four
        fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(4);
        assertEq(fee, 11 wei);

        // Assume the base fee is currently 1 wei
        vm.mockCall(wrpa, bytes(""), abi.encode(1));

        // ... and exponentially increase again for four
        fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(7);
        assertEq(fee, 48 wei);
    }
}
