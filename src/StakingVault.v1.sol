// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./StakingVault.v0.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@ethereum/beacon-deposit-contract/IDepositContract.sol";
import {BeaconChain} from "./BeaconChain.sol";

/**
 * @title StakingVault
 *
 * @dev This contract allows to split staking rewards among a rewards recipient
 * and a fee recipient.
 * Recipients are registered at construction time. Each time rewards are
 * released, the contract computes the amount of Ether to distribute to each
 * account. The sender does not need to be aware of the mechanics behind
 * splitting the Ether, since it is handled transparently by the contract.
 *
 * The split affects only the rewards accumulated but not any returned stake.
 * The rewards recipient will therefore need to register (activate) and
 * deregister (exit) any validators associated to this contract.
 *
 * `StakingRewards` follows a _pull payment_ model. This means that payments are
 * not automatically forwarded to the accounts but kept in this contract,
 * and the actual transfer is triggered as a separate step by calling the
 * {release} function.
 */
contract StakingVaultV1 is StakingVaultV0 {
    /*
     * Errors
     */

    /// @dev Error when the public key length does not match the expected length
    error PublicKeyLengthMismatch();

    /// @dev Error when the signature length does not match the expected length
    error SignatureLengthMismatch();

    /// @dev Error when the deposit amount is invalid
    error InvalidDepositAmount();

    /// @dev Error when there is no deposit data to register
    error NoDepositDataToRegister();

    /// @dev Error when deposit data are invalid
    error InvalidDepositData();

    /*
     * Contract lifecycle
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize instances of this contract
    function initialize_v1() public initializer {}

    /*
     * Staking operations
     */

    /// @dev The requested stake quota
    uint256 private _requestedStakeQuota;

    /// @dev The stake quota approved by the operator
    uint256 private _stakeQuota;

    /// @dev The error raised when the requested stake quota is less than the current staked balance
    error RequestedStakeQuotaLessThanStakedBalance();

    /// @dev The error raised when the requested stake quota is invalid
    error RequestedStakeQuotaInvalid();

    /// @dev The event emitted when the requested stake quota is updated
    event RequestedStakeQuota(uint256 requestedStakeQuota);

    /// @dev The event emitted when the stake quota is approved
    event StakeQuotaUpdated(uint256 approvedStakeQuota);

    /// @notice Request a quota to be staked in this vault. Only callable by the staker.
    ///
    /// @param newRequestedStakeQuota The total amount of Ether requested to be stakeable in this vault.
    ///
    /// @dev Reverts if the new requested stake quota is not bigger than the already requested quota.
    function requestStakeQuota(
        uint256 newRequestedStakeQuota
    ) external onlyRole(STAKER_ROLE) {
        if (newRequestedStakeQuota <= _requestedStakeQuota)
            revert RequestedStakeQuotaLessThanStakedBalance();

        if (
            newRequestedStakeQuota < BeaconChain.MAX_EFFECTIVE_BALANCE ||
            newRequestedStakeQuota % BeaconChain.MAX_EFFECTIVE_BALANCE != 0
        ) revert RequestedStakeQuotaInvalid();

        uint16 numberOfDeposits = uint16(
            newRequestedStakeQuota / BeaconChain.MAX_EFFECTIVE_BALANCE
        );

        for (uint16 i = 0; i < numberOfDeposits; i++) {
            _depositData[i] = PartialDepositData({
                // We are using non-zero values to initialize the fields
                // in order to actually allocate the storage slots
                pubkey_1: bytes32(uint256(1)),
                pubkey_2: bytes32(uint256(1)),
                signature_1: bytes32(uint256(1)),
                signature_2: bytes32(uint256(1)),
                signature_3: bytes32(uint256(1))
            });
        }

        _requestedStakeQuota = newRequestedStakeQuota;
        emit RequestedStakeQuota(_requestedStakeQuota);
    }

    PartialDepositData[] private _partialDepositData;

    /// @dev The structure of partial deposit data
    /// @dev To save gas, we chunk the 48 bytes public keys and 96 bytes signatures into 32 bytes pieces.
    /// @param pubkey The BLS12-381 public key of the validator
    /// @param signature The BLS12-381 signature of the deposit message
    /// @param depositValue The deposit value of the validator
    struct PartialDepositData {
        bytes32 pubkey_1;
        bytes32 pubkey_2;
        bytes32 signature_1;
        bytes32 signature_2;
        bytes32 signature_3;
    }

    /// @dev The structure of full deposit data
    /// @param pubkey The BLS12-381 public key of the validator
    /// @param signature The BLS12-381 signature of the deposit message
    /// @param depositValue The deposit value of the validator
    struct DepositData {
        bytes pubkey;
        bytes withdrawalCredentials;
        bytes signature;
        bytes32 depositDataRoot;
        uint256 depositValue;
    }

    /// @dev The total number of deposit data in the _depositData mapping
    uint16 private _depositDataCount;

    /// @dev The next index of the deposit data to be processed
    uint16 private _depositDataIndex;

    /// @dev Indexed map of deposit data. Supports a maximum of 2^16 - 1 deposit data,
    /// i.e., 65535 * 32 Ether
    mapping(uint16 => PartialDepositData) private _depositData;

    /// @notice Approve a quota to be staked in this vault by registering the
    /// respective deposit data. Only callable by the operator.
    /// Reverts if the deposit data are invalid.
    ///
    /// @param pubkeys The BLS12-381 public keys of the validators
    /// @param signatures The BLS12-381 signatures of the deposit messages
    /// @param depositValues The deposit values of the validators
    function approveStakeQuota(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        uint256[] calldata depositValues
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 numberOfDepositData = pubkeys.length;

        if (numberOfDepositData == 0 || numberOfDepositData >= type(uint16).max)
            revert NoDepositDataToRegister();

        if (
            pubkeys.length != signatures.length ||
            pubkeys.length != depositValues.length
        ) revert InvalidDepositData();

        // unchecked {
        for (uint16 i = 0; i < numberOfDepositData; ) {
            if (pubkeys[i].length != BeaconChain.PUBKEY_LENGTH)
                revert PublicKeyLengthMismatch();
            if (signatures[i].length != BeaconChain.SIGNATURE_LENGTH)
                revert SignatureLengthMismatch();
            if (depositValues[i] != BeaconChain.MAX_EFFECTIVE_BALANCE)
                revert InvalidDepositAmount();

            // TODO: Check pubkey is not already registered

            // TODO: Check pubkey is not already exited

            PartialDepositData storage pdd = _depositData[
                _depositDataCount + i
            ];
            pdd.pubkey_1 = bytes32(pubkeys[i][:32]);
            pdd.pubkey_2 = bytes32(pubkeys[i][32:48]);
            pdd.signature_1 = bytes32(signatures[i][:32]);
            pdd.signature_2 = bytes32(signatures[i][32:64]);
            pdd.signature_3 = bytes32(signatures[i][64:]);

            _stakeQuota += depositValues[i];

            ++i;
        }
        // }

        // We can safely downcast here as we have checked the length of pubkeys above
        _depositDataCount += uint16(numberOfDepositData);
        emit StakeQuotaUpdated(_stakeQuota);
    }

    /// @notice Get the approved stake quota
    function stakeQuota() external view returns (uint256) {
        return _stakeQuota;
    }

    /// @dev The error raised when the stake quota is too low
    error StakeQuotaTooLow();

    /// @notice Get the next deposit data for a given amount of stake
    /// Reverts if newStake exceeds the stakeQuota
    ///
    /// @param newStake The amount of stake that deposit data is requested for
    function depositData(
        uint256 newStake
    ) public view returns (DepositData[] memory) {
        if (newStake > _stakeQuota) revert StakeQuotaTooLow();
        if (newStake == 0 || newStake % BeaconChain.MAX_EFFECTIVE_BALANCE != 0)
            revert InvalidDepositAmount();

        uint16 numberOfDeposits = uint16(
            newStake / BeaconChain.MAX_EFFECTIVE_BALANCE
        );

        // Construct 0x01 withdrawal credentials using the address of this staking vault
        bytes memory withdrawalCredentials = _withdrawalCredentials();
        DepositData[] memory tempDepositData = new DepositData[](
            numberOfDeposits
        );

        for (uint16 i = 0; i < numberOfDeposits; i++) {
            PartialDepositData storage storedDepositData = _depositData[
                _depositDataIndex + i
            ];

            bytes memory pubkey = bytes.concat(
                storedDepositData.pubkey_1,
                bytes16(storedDepositData.pubkey_2)
            );
            bytes memory signature = bytes.concat(
                storedDepositData.signature_1,
                storedDepositData.signature_2,
                storedDepositData.signature_3
            );

            // TODO: Validate that the validator is not exiting or exited

            tempDepositData[i] = DepositData({
                pubkey: pubkey,
                withdrawalCredentials: withdrawalCredentials,
                signature: signature,
                depositDataRoot: BeaconChain.depositDataRoot(
                    pubkey,
                    withdrawalCredentials,
                    signature,
                    BeaconChain.MAX_EFFECTIVE_BALANCE
                ),
                depositValue: BeaconChain.MAX_EFFECTIVE_BALANCE
            });
        }

        return tempDepositData;
    }

    /// @dev Balance per validator (identified by public key)
    mapping(bytes => uint256) private _stakedBalances;

    /// @dev The active staked balance
    uint256 private _stakedBalance = 0;

    /// @notice By sending Ether to this contract, the sender is staking the funds
    ///
    /// @dev This contract accepts payments and consumes available deposit data
    /// It reverts if:
    /// - The sender is not a staker
    /// - The message value does not match available deposit data
    receive() external payable {
        // TODO: Consider adding an allowlist of stakers
        if (!hasRole(STAKER_ROLE, _msgSender()))
            revert AccessControlUnauthorizedAccount(_msgSender(), STAKER_ROLE);

        if (msg.value > _stakeQuota) revert StakeQuotaTooLow();
        if (
            msg.value < BeaconChain.MAX_EFFECTIVE_BALANCE ||
            msg.value % BeaconChain.MAX_EFFECTIVE_BALANCE != 0
        ) revert InvalidDepositAmount();

        // Construct 0x01 withdrawal credentials using the address of this staking vault
        bytes memory withdrawalCredentials = _withdrawalCredentials();

        uint16 numberOfDeposits = uint16(
            msg.value / BeaconChain.MAX_EFFECTIVE_BALANCE
        );

        for (uint16 i = 0; i < numberOfDeposits; i++) {
            PartialDepositData storage storedDepositData = _depositData[
                _depositDataIndex + i
            ];

            // TODO: Validate validator is not exited

            bytes memory pubkey = bytes.concat(
                storedDepositData.pubkey_1,
                bytes16(storedDepositData.pubkey_2)
            );
            bytes memory signature = bytes.concat(
                storedDepositData.signature_1,
                storedDepositData.signature_2,
                storedDepositData.signature_3
            );

            // Deposit the funds to the beacon chain deposit contract
            _depositContractAddress.deposit{
                value: BeaconChain.MAX_EFFECTIVE_BALANCE
            }(
                pubkey,
                withdrawalCredentials,
                signature,
                BeaconChain.depositDataRoot(
                    pubkey,
                    withdrawalCredentials,
                    signature,
                    BeaconChain.MAX_EFFECTIVE_BALANCE
                )
            );

            _stakeQuota -= BeaconChain.MAX_EFFECTIVE_BALANCE;
            _stakedBalance += BeaconChain.MAX_EFFECTIVE_BALANCE;
            // _stakedBalances[pubkey] += BeaconChain.MAX_EFFECTIVE_BALANCE;
            // We delete the deposit data as they will not be used again and
            // deleting them provides a gas refund
            // delete _depositData[_depositDataIndex];
        }

        _depositDataIndex += numberOfDeposits;
    }

    /// @notice Get the withdrawal credentials of this staking vault
    ///
    /// @dev This staking vault uses 0x01 withdrawal credentials, pointing
    /// validator rewards and withdrawals to itself.
    ///
    /// @return The withdrawal credentials of this staking vault
    function _withdrawalCredentials() internal view returns (bytes memory) {
        return
            abi.encodePacked(bytes1(0x01), bytes11(0), bytes20(address(this)));
    }

    /// @dev The event emitted when an unbonding is requested by the staker
    event UnbondRequested(uint256 amount);

    /// @dev The amount of Ether being unbonded
    uint256 private _unbondingAmount;

    /// @dev The total amount of Ether exited
    uint256 private _exitedStake;

    /// @notice The error raised when the requested amount does not match with validator balances
    error InvalidUnbondAmount();

    /// @notice Request unbonding of a certain amount of Ether
    /// Only callable by the staker
    /// Reverts if the requested amount does not match with validator balances
    /// @param amount The amount of Ether to unbond
    function requestUnbond(uint256 amount) external onlyRole(STAKER_ROLE) {
        if (amount > _stakedBalance) revert InvalidUnbondAmount();

        // TODO: if (_stakedBalances[pubkey] == 0) revert ValidatorNotActive();
        // TODO: Verify the amount can be unbonded by exiting certain validators

        _stakedBalance -= amount;
        _unbondingAmount += amount;
        _exitedStake += amount;
        emit UnbondRequested(amount);
    }

    /// @notice Trigger the unbond of a certain amount of Ether
    /// Only callable by the staker
    /// Implements execution layer triggerable exits via EIP-7002
    /// Reverts if the requested amount does not match with validator balances
    /// Reverts if any of the valdiators are not active or exitable
    /// @param amount The amount of Ether to unbond
    function unbond(uint256 amount) external onlyRole(STAKER_ROLE) {
        if (amount > _unbondingAmount) revert InvalidUnbondAmount();
        _stakedBalance -= amount;
        _unbondingAmount += amount;
        _exitedStake += amount;
        // error ValidatorNotActive();
        // TODO: Implement
    }

    /// @dev The total amount of rewards released
    uint256 private _claimedRewards;
    /// @dev The total amount of fees released
    uint256 private _claimedFees;

    /// @notice The error raised when there are no funds to release
    error NoFundsToRelease();

    /// @dev Triggers withdrawal of the accumulated rewards to the staker.
    /// Also releases any unbonded principal, if available
    /// Only callable by the staker
    /// Reverts if the staker has no claimable rewards
    function claimRewards() external virtual onlyRole(STAKER_ROLE) {
        uint256 claimable = claimableRewards();

        if (claimable == 0) revert NoFundsToRelease();

        _claimedRewards += claimable;

        emit FundsReleased(_staker, claimable);
        Address.sendValue(_staker, claimable);
    }

    /// @dev Triggers withdrawal of the acculated fees to the fee recipient
    /// Only callable by the operator
    /// Reverts if the operator has no claimable fees
    function claimFees() external virtual onlyRole(OPERATOR_ROLE) {
        uint256 claimable = claimableFees();

        if (claimable == 0) revert NoFundsToRelease();

        _claimedFees += claimable;

        emit FundsReleased(_feeRecipient, claimable);
        Address.sendValue(_feeRecipient, claimable);
    }

    /// @notice The event released when funds are released
    event FundsReleased(address indexed recipient, uint256 amount);

    /*
     * Public views on the internal state
     */

    /// @notice Get the amount currently staked
    function stakedBalance() external view returns (uint256) {
        return _stakedBalance;
    }

    /**
     * @dev Get the total amount of rewards that can be claimed.
     */
    function claimableRewards() public view returns (uint256) {
        uint256 billable = billableRewards();

        // 10_000 basis points = 100%
        uint256 totalRewards = (billable * (10_000 - _feeBasisPoints)) /
            10 ** 4;
        return totalRewards + _exitedStake - _claimedRewards;
    }

    /**
     * @dev Get the total amount of rewards that have been claimed.
     */
    function claimedRewards() public view returns (uint256) {
        return _claimedRewards;
    }

    /**
     * @dev Get the total amount of fees that can be claimed.
     */
    function claimableFees() public view returns (uint256) {
        uint256 billable = billableRewards();

        if (billable == 0) return 0;

        uint256 totalFees = (billable * _feeBasisPoints) / 10 ** 4;
        return totalFees - _claimedFees;
    }

    /**
     * @dev Get the total amount of fees paid.
     */
    function claimedFees() public view returns (uint256) {
        return _claimedFees;
    }

    /**
     * @dev Getter for the billable rewards.
     */
    function billableRewards() public view returns (uint256) {
        uint256 totalBalance = address(this).balance +
            _claimedFees +
            _claimedRewards;
        uint256 billable = 0;

        if (totalBalance >= _exitedStake) {
            billable = totalBalance - _exitedStake;
        }

        return billable;
    }
}
