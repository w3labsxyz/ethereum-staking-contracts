pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDepositContract} from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import {DepositContract} from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import {StakingVaultV1} from "../src/StakingVault.v1.sol";
import {StakingVaultFactory} from "../src/StakingVaultFactory.sol";

abstract contract StakingVaultSetup is Test {
    IDepositContract depositContract;
    StakingVaultV1 stakingVault;
    StakingVaultV1 stakingVaultProxy;
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

        stakingVault = new StakingVaultV1();

        stakingVaultFactory = new StakingVaultFactory(
            stakingVault,
            operator,
            feeRecipient,
            feeBasisPoints,
            depositContract
        );

        vm.prank(staker);
        stakingVaultProxy = StakingVaultV1(
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
        StakingVaultV1(payable(address(stakingVaultFactory.createVault())));
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

    /// @dev `requestStakeQuota` can only increase the stake quota
    // TODO: implement

    /// @dev `requestStakeQuota` can only request multiples of 32
    // TODO: implement

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

        StakingVaultV1.DepositData[] memory pd = stakingVaultProxy.depositData(
            32 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 32 ether);
        assertEq(pd[0].pubkey, pubkeys[0]);
        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[0]")
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

        // The staker sent 32 Ether, which was reverted. Therefore, the staker
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

        StakingVaultV1.DepositData[] memory pd = stakingVaultProxy.depositData(
            64 ether
        );

        assertEq(stakingVaultProxy.stakeQuota(), 64 ether);
        assertEq(pd[0].pubkey, pubkeys[0]);
        assertEq(pd[1].pubkey, pubkeys[1]);

        assertEq(
            pd[0].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[0]")
        );
        assertEq(
            pd[1].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[1]")
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

        StakingVaultV1.DepositData[] memory pd = stakingVaultProxy.depositData(
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
            vm.parseJsonBytes(json, ".withdrawal_credentials[0]")
        );
        assertEq(
            pd[1].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[1]")
        );
        assertEq(
            pd[2].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[2]")
        );
        assertEq(
            pd[3].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[3]")
        );
        assertEq(
            pd[4].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[4]")
        );
        assertEq(
            pd[5].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[5]")
        );
        assertEq(
            pd[6].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[6]")
        );
        assertEq(
            pd[7].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[7]")
        );
        assertEq(
            pd[8].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[8]")
        );
        assertEq(
            pd[9].withdrawalCredentials,
            vm.parseJsonBytes(json, ".withdrawal_credentials[9]")
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
}

// bytes memory reconstructedDdr = abi.encodePacked(
//     stakingVaultProxy.deposit_data_root{value: 32 ether}(
//         pd[0].pubkey,
//         pd[0].withdrawalCredentials,
//         pd[0].signature
//     )
// );
// console.logBytes(reconstructedDdr);
