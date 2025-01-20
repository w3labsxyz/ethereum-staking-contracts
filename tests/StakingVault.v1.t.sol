pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IDepositContract} from "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import {DepositContract} from "@ethereum/beacon-deposit-contract/DepositContract.sol";
import {IEIP7002} from "@eips/7002/IEIP7002.sol";
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

        string[] memory inputs = new string[](2);
        inputs[0] = "geas";
        inputs[1] = "lib/eip-7002/main.eas";
        bytes memory res = vm.ffi(inputs);
        assertEq(string(res), "gm");

        bytes
            memory eip7002 = hex"3373fffffffffffffffffffffffffffffffffffffffe1460cb5760115f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff146101f457600182026001905f5b5f82111560685781019083028483029004916001019190604d565b909390049250505036603814608857366101f457346101f4575f5260205ff35b34106101f457600154600101600155600354806003026004013381556001015f35815560010160203590553360601b5f5260385f601437604c5fa0600101600355005b6003546002548082038060101160df575060105b5f5b8181146101835782810160030260040181604c02815460601b8152601401816001015481526020019060020154807fffffffffffffffffffffffffffffffff00000000000000000000000000000000168252906010019060401c908160381c81600701538160301c81600601538160281c81600501538160201c81600401538160181c81600301538160101c81600201538160081c81600101535360010160e1565b910180921461019557906002556101a0565b90505f6002555f6003555b5f54807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff14156101cd57505f5b6001546002828201116101e25750505f6101e8565b01600290035b5f555f600155604c025ff35b5f5ffd";
        address withdrawalRequestPredeployAddress = address(
            0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA
        );
        vm.etch(withdrawalRequestPredeployAddress, eip7002);
        vm.deal(withdrawalRequestPredeployAddress, 96 ether);
        IEIP7002 withdrawalRequestPredeploy = IEIP7002(
            withdrawalRequestPredeployAddress
        );

        bytes memory data = abi.encodeWithSelector(
            withdrawalRequestPredeploy.getFee.selector
        );
        (bool s, bytes memory ret) = address(withdrawalRequestPredeploy).call{
            value: 0 ether
        }("");

        uint256 withdrawalFee = uint256(bytes32(ret));
        console.log("Fee: %d Wei", withdrawalFee);
        // assertEq(withdrawalFee, 0.01 ether);

        bytes
            memory pubkey = hex"b87870ea7c529836358b715669ffe344d70b862ce6480fa6cd766683e6348e0b98db19b0419b9aac370ef922602031a0";
        uint64 withdrawalAmountGwei = uint64(32 ether / 1 gwei);
        data = bytes.concat(
            pubkey,
            bytes8(withdrawalAmountGwei) // Convert to big-endian bytes8
        );
        (s, ret) = address(withdrawalRequestPredeploy).call{
            value: withdrawalFee
        }(data);
        console.log("Withdrawal request succeeded: %s", s);
        console.logBytes(ret);

        address dci = address(new DepositContract());
        vm.etch(address(0x4242424242424242424242424242424242424242), dci.code);
        depositContract = IDepositContract(
            address(0x4242424242424242424242424242424242424242)
        );

        stakingVault = new StakingVaultV1();

        stakingVaultFactory = new StakingVaultFactory(
            stakingVault,
            operator,
            feeRecipient,
            feeBasisPoints
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

        StakingVaultV1.DepositData[] memory pd = stakingVaultProxy.depositData(
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
        stakingVaultProxy.requestStakeQuota(32 ether);

        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/tests/fixtures/32eth-deposit.json"
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

        vm.deal(staker, 32 ether);
        vm.prank(staker);
        (bool success, ) = payable(stakingVaultProxy).call{value: 32 ether}("");
        assertTrue(success, "Call failed");

        assertEq(staker.balance, 0 ether);
        assertEq(operator.balance, 0 ether);
        assertEq(feeRecipient.balance, 0 ether);
        assertEq(address(stakingVaultProxy).balance, 0 ether);
        assertEq(address(depositContract).balance, 32 ether);

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
