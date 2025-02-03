// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardTransientUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";

import { BeaconChain } from "./BeaconChain.sol";
import { EIP7002 } from "./EIP7002.sol";

import { IStakingHub } from "./interfaces/IStakingHub.sol";
import { IStakingVault } from "./interfaces/IStakingVault.sol";

/// @title StakingVault
///
/// @notice This is the w3.labs StakingVault contract
///
/// @dev This contract allows to stake with validators operated by an external
/// node operator and to split staking rewards among a rewards recipient
/// and a fee recipient.
///
/// Recipients are registered at construction time. Each time rewards are
/// released, the contract computes the amount of Ether to distribute to each
/// account. The sender does not need to be aware of the mechanics behind
/// splitting the Ether, since it is handled transparently by the contract.
///
/// @custom:security-contact security@w3labs.xyz
contract StakingVault is
    IStakingVault,
    AccessControlUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    UUPSUpgradeable,
    EIP7002
{
    /*
     * Access Control
     */

    /// @dev Role for the node operator
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Role for the staker
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    /// @dev Role for depositors
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /// @dev Fees can not exceed 100%
    uint256 private constant MAX_BASIS_POINTS = 10_000;

    /*
     * State
     */

    /// @dev The address of the fee recipient
    address payable internal _feeRecipient;

    /// @dev The address of the staker
    address payable internal _staker;

    /// @dev The basis points charged as a fee
    uint256 internal _feeBasisPoints;

    /// @dev The staking hub
    IStakingHub internal _stakingHub;

    /// @dev The address of the beacon chain deposit contract
    /// See: https://eips.ethereum.org/EIPS/eip-2982#parameters
    IDepositContract internal _depositContractAddress;

    /// @dev The total number of deposit data in the _depositData mapping
    uint16 private _depositDataCount;

    /// @dev The total number of deposits that were exercised by the staker
    /// This number is also the next index of the deposit data to be processed
    uint16 private _numberOfDeposits;

    /// @dev The total number of unbondings that were requested by the staker
    /// This number is also the next index of the unbonding data to be processed
    uint16 private _numberOfUnbondings;

    /// @dev Indexed map of deposit data. Supports a maximum of 2^16 - 1 deposit data,
    /// i.e., 65535 * 32 Ether
    mapping(uint16 => StoredDepositData) private _depositData;

    /// @dev Balance per validator (identified by public key)
    mapping(bytes => uint256) private _principalPerValidator;

    /// @dev The amount of Ether actively staked
    uint256 private _principalAtStake;

    /// @dev The total amount of principal than can be withdrawn
    uint256 private _withdrawablePrincipal;

    /// @dev The total amount of rewards claimed
    uint256 private _claimedRewards;

    /// @dev The total amount of fees claimed
    uint256 private _claimedFees;

    /*
     * Events
     */

    /// @dev The event emitted when the stake quota is approved
    event StakeQuotaUpdated(uint256 approvedStakeQuota);

    /*
     * Errors
     */

    /// @dev Error when trying to remove the OPERATOR_ROLE or STAKER_ROLE
    error AccessControlInvalidRoleRemoval();

    error InvalidFeeBasisPoints(uint256 feeBasisPoints);

    error ZeroAddress();

    error InvalidRoleRemoval();

    /// @dev Error when the public key length does not match the expected length
    error PublicKeyLengthMismatch();

    /// @dev Error when the signature length does not match the expected length
    error SignatureLengthMismatch();

    /// @dev Error when the deposit amount is invalid
    error InvalidDepositAmount();

    /// @dev Error when deposit data are invalid
    error InvalidDepositData();

    /// @dev The error raised when the requested stake quota is invalid
    error RequestedStakeQuotaInvalid();

    /// @dev The error raised when the stake quota is too low
    error StakeQuotaTooLow();

    /// @dev The error raised when the validator is already active
    error ValidatorAlreadyActive();

    /// @dev The error raised when there are no validators to trigger withdrawals for
    error InvalidUnbonding();

    /// @dev The error raised when the fee included in the withdrawal request is too low
    error WithdrawalRequestFeeTooLow();

    /// @dev The error raised when the fee included in the withdrawal request is invalid
    error InvalidWithdrawalRequestFee();

    /// @notice The error raised when there are no funds to release
    error NoFundsToRelease();

    /*
     * Contract lifecycle
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize instances of this contract
    function initialize(
        IStakingHub newStakingHub,
        address payable newOperator,
        address payable newFeeRecipient,
        address payable newStaker,
        uint256 newFeeBasisPoints,
        uint256 initialStakeQuota
    )
        external
        initializer
    {
        if (address(newStakingHub) == address(0)) revert ZeroAddress();
        if (newOperator == address(0)) revert ZeroAddress();
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        if (newStaker == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _stakingHub = newStakingHub;

        _grantRole(OPERATOR_ROLE, newOperator);

        _feeRecipient = newFeeRecipient;

        _staker = newStaker;
        _grantRole(STAKER_ROLE, newStaker);
        _grantRole(DEPOSITOR_ROLE, newStaker);

        // The staker is also the admin of the depositor role,
        // i.e., the staker can add and remove depositors
        _setRoleAdmin(DEPOSITOR_ROLE, STAKER_ROLE);

        if (newFeeBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidFeeBasisPoints(newFeeBasisPoints);
        }

        _feeBasisPoints = newFeeBasisPoints;

        if (block.chainid == 1) {
            _depositContractAddress = IDepositContract(
                // https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa
                0x00000000219ab540356cBB839Cbe05303d7705Fa
            );
        } else {
            _depositContractAddress = IDepositContract(
                // For other networks, such as those used in testing, we use the supplied address
                // https://holesky.etherscan.io/address/0x4242424242424242424242424242424242424242
                0x4242424242424242424242424242424242424242
            );
        }

        // https://eips.ethereum.org/EIPS/eip-7002#configuration
        _withdrawalRequestPredeployAddress = address(0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA);

        if (initialStakeQuota != 0) _requestStakeQuota(initialStakeQuota);
    }

    /*
     * UUPSUpgradeable impl
     */

    /// @notice Authorizes that upgrades via `upgradeToAndCall` can only be done by the staker
    /// @dev Implementation provided for the requirement of the `UUPSUpgradeable` interface
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(STAKER_ROLE) { }

    /*
     * AccessControl implementation
     */

    /// @dev Override the `grantRole` function to disallow the removal of the
    /// OPERATOR_ROLE and STAKER_ROLE
    function renounceRole(bytes32 role, address callerConfirmation) public virtual override {
        if (role == OPERATOR_ROLE) revert AccessControlInvalidRoleRemoval();
        if (role == STAKER_ROLE) revert AccessControlInvalidRoleRemoval();

        super.renounceRole(role, callerConfirmation);
    }

    /*
     * Staking operations
     */

    /// @notice Request a quota to be staked in this vault. Only callable by the staker.
    ///
    /// @param newRequestedStakeQuota The total amount of Ether (in wei) requested to be stakeable in this vault.
    ///
    /// @dev Requested stake quotas are not persisted in the state of the contract. Instead, an event is emitted
    /// to signal the requested stake quota. The operator may then approve the requested stake quota by
    /// registering the respective deposit data. Requesting stake quota is additive, i.e., the staker may
    /// request multiple times to stake more Ether.
    function requestStakeQuota(uint256 newRequestedStakeQuota) external virtual onlyRole(STAKER_ROLE) {
        _requestStakeQuota(newRequestedStakeQuota);
        _stakingHub.announceStakeQuotaRequest(_staker, newRequestedStakeQuota);
    }

    function _requestStakeQuota(uint256 newRequestedStakeQuota) internal virtual {
        if (newRequestedStakeQuota % BeaconChain.MAX_EFFECTIVE_BALANCE != 0) {
            revert RequestedStakeQuotaInvalid();
        }

        uint16 numberOfDeposits = uint16(newRequestedStakeQuota / BeaconChain.MAX_EFFECTIVE_BALANCE);
        uint16 depositDataOffset = _depositDataCount;
        for (uint16 i = depositDataOffset; i < depositDataOffset + numberOfDeposits; i++) {
            _depositData[i] = StoredDepositData({
                // We are using non-zero values to initialize the fields
                // in order to actually allocate the storage slots
                pubkey_1: bytes32(uint256(1)),
                pubkey_2: bytes32(uint256(1)),
                signature_1: bytes32(uint256(1)),
                signature_2: bytes32(uint256(1)),
                signature_3: bytes32(uint256(1))
            });
        }
    }

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
    )
        external
        virtual
        onlyRole(OPERATOR_ROLE)
    {
        uint256 numberOfDepositData = pubkeys.length;

        if (
            numberOfDepositData == 0 || numberOfDepositData >= type(uint16).max || pubkeys.length != signatures.length
                || pubkeys.length != depositValues.length
        ) revert InvalidDepositData();

        uint16 depositDataOffset = _depositDataCount;
        for (uint16 i = 0; i < numberOfDepositData; i++) {
            if (pubkeys[i].length != BeaconChain.PUBKEY_LENGTH) {
                revert PublicKeyLengthMismatch();
            }
            if (signatures[i].length != BeaconChain.SIGNATURE_LENGTH) {
                revert SignatureLengthMismatch();
            }
            if (depositValues[i] != BeaconChain.MAX_EFFECTIVE_BALANCE) {
                revert InvalidDepositAmount();
            }

            StoredDepositData storage slot = _depositData[depositDataOffset + i];
            slot.pubkey_1 = bytes32(pubkeys[i][:32]);
            slot.pubkey_2 = bytes32(pubkeys[i][32:48]);
            slot.signature_1 = bytes32(signatures[i][:32]);
            slot.signature_2 = bytes32(signatures[i][32:64]);
            slot.signature_3 = bytes32(signatures[i][64:]);
        }

        // We can safely downcast here as we have checked the length of pubkeys above
        _depositDataCount += uint16(numberOfDepositData);

        emit StakeQuotaUpdated(_stakeQuota());
    }

    /// @notice By sending Ether to this contract, the sender is staking the funds
    ///
    /// @dev This contract accepts payments and consumes available deposit data
    /// It reverts if:
    /// - The sender is not a staker
    /// - The message value does not match available deposit data
    receive() external payable virtual nonReentrant {
        if (!hasRole(DEPOSITOR_ROLE, _msgSender())) {
            revert AccessControlUnauthorizedAccount(_msgSender(), DEPOSITOR_ROLE);
        }

        if (msg.value > _stakeQuota()) revert StakeQuotaTooLow();
        if (msg.value % BeaconChain.MAX_EFFECTIVE_BALANCE != 0) {
            revert InvalidDepositAmount();
        }

        // Construct 0x01 withdrawal credentials using the address of this staking vault
        bytes32 withdrawalCredentials = _withdrawalCredentials();

        uint16 previousNumberOfDeposits = _numberOfDeposits;
        uint16 numberOfNewDeposits = uint16(msg.value / BeaconChain.MAX_EFFECTIVE_BALANCE);

        _numberOfDeposits += numberOfNewDeposits;
        _principalAtStake += BeaconChain.MAX_EFFECTIVE_BALANCE * numberOfNewDeposits;

        for (uint16 i = previousNumberOfDeposits; i < previousNumberOfDeposits + numberOfNewDeposits; i++) {
            StoredDepositData storage storedDepositData = _depositData[i];

            bytes memory pubkey = bytes.concat(storedDepositData.pubkey_1, bytes16(storedDepositData.pubkey_2));
            bytes memory signature = bytes.concat(
                storedDepositData.signature_1, storedDepositData.signature_2, storedDepositData.signature_3
            );

            _principalPerValidator[pubkey] += BeaconChain.MAX_EFFECTIVE_BALANCE;

            // Deposit the funds to the beacon chain deposit contract
            _depositContractAddress.deposit{ value: BeaconChain.MAX_EFFECTIVE_BALANCE }(
                pubkey,
                abi.encodePacked(withdrawalCredentials),
                signature,
                BeaconChain.depositDataRoot(pubkey, withdrawalCredentials, signature, BeaconChain.MAX_EFFECTIVE_BALANCE)
            );
        }
    }

    function recommendedWithdrawalRequestsFee(uint256 numberOfWithdrawalRequests) external virtual returns (uint256) {
        return _recommendedWithdrawalRequestsFee(numberOfWithdrawalRequests);
    }

    /// @notice Request unbondings of staked principal by EIP-7002 execution layer requests.
    /// This function allows the ultimate owner of the funds - the staker - to independently choose to unbond staked
    /// Ether. This mitigates potential trust issues as the operator is now unable to "hold the Ether hostage".
    /// Additionally, the staker could even unbond the principal in the unlikely event that the validator active keys
    /// would be lost.
    ///
    /// @param pubkeys The public keys of the validators to trigger withdrawals for
    function requestUnbondings(bytes[] calldata pubkeys) external payable virtual nonReentrant onlyRole(STAKER_ROLE) {
        uint256 numberOfUnbondings = pubkeys.length;
        if (numberOfUnbondings == 0) revert InvalidUnbonding();
        if (numberOfUnbondings >= type(uint16).max) revert InvalidUnbonding();

        uint256 recommendedFee = _recommendedWithdrawalRequestsFee(numberOfUnbondings);

        if (msg.value < recommendedFee) revert WithdrawalRequestFeeTooLow();

        if (msg.value % numberOfUnbondings != 0) {
            revert InvalidWithdrawalRequestFee();
        }

        uint256 withdrawalFee = msg.value / numberOfUnbondings;
        uint256 totalWithdrawAmount = 0;

        for (uint256 i = 0; i < numberOfUnbondings; i++) {
            if (pubkeys[i].length != BeaconChain.PUBKEY_LENGTH) {
                revert PublicKeyLengthMismatch();
            }

            _addEip7002WithdrawalRequest(
                pubkeys[i],
                // We always exercise full withdrawals at this point
                BeaconChain.MAX_EFFECTIVE_BALANCE_IN_GWEI,
                withdrawalFee
            );

            uint256 expectedWithdrawAmount = _principalPerValidator[pubkeys[i]];
            if (expectedWithdrawAmount != 0) {
                _principalPerValidator[pubkeys[i]] = 0;
            }
            totalWithdrawAmount += expectedWithdrawAmount;
        }

        _principalAtStake -= totalWithdrawAmount;
        _withdrawablePrincipal += totalWithdrawAmount;
        _numberOfUnbondings += uint16(numberOfUnbondings);

        _stakingHub.announceUnbondingRequest(_staker, pubkeys);
    }

    /// @notice Register unbondings that have been submitted to the beacon chain via the signed exit message generated
    /// by the validator key
    ///
    /// @dev This function is not usually called as calling `requestUnbondings` is the preferred way to trigger
    /// unbondings. It is only used if exit messages have been submitted to the beacon chain directly.
    ///
    /// @param pubkeys The public keys of the validators to register unbondings for
    function attestUnbondings(bytes[] calldata pubkeys) external virtual onlyRole(OPERATOR_ROLE) {
        uint256 numberOfUnbondings = pubkeys.length;
        if (numberOfUnbondings == 0) revert InvalidUnbonding();
        if (numberOfUnbondings >= type(uint16).max) revert InvalidUnbonding();

        uint256 totalWithdrawAmount = 0;

        for (uint256 i = 0; i < numberOfUnbondings; i++) {
            if (pubkeys[i].length != BeaconChain.PUBKEY_LENGTH) {
                revert PublicKeyLengthMismatch();
            }

            uint256 expectedWithdrawAmount = _principalPerValidator[pubkeys[i]];
            _principalPerValidator[pubkeys[i]] = 0;
            totalWithdrawAmount += expectedWithdrawAmount;
        }

        _principalAtStake -= totalWithdrawAmount;
        _withdrawablePrincipal += totalWithdrawAmount;
        _numberOfUnbondings += uint16(numberOfUnbondings);
    }

    /// @notice Triggers withdrawal of unbonded principal
    /// Only callable by the staker
    /// Reverts if there is no claimable principal
    function withdrawPrincipal() external virtual nonReentrant onlyRole(STAKER_ROLE) {
        uint256 claimable = _withdrawablePrincipal;

        if (claimable == 0) revert NoFundsToRelease();

        if (claimable > address(this).balance) {
            claimable = address(this).balance;
        }

        _withdrawablePrincipal -= claimable;
        Address.sendValue(_staker, claimable);
    }

    /// @notice Triggers withdrawal of the accumulated rewards to the staker.
    /// Only callable by the staker
    /// Reverts if the staker has no claimable rewards
    function claimRewards() external virtual nonReentrant onlyRole(STAKER_ROLE) {
        uint256 claimable = _claimableRewards();

        if (claimable == 0) revert NoFundsToRelease();

        _claimedRewards += claimable;
        Address.sendValue(_staker, claimable);
    }

    /// @notice Triggers withdrawal of the acculated fees to the fee recipient
    /// Only callable by the operator
    /// Reverts if the operator has no claimable fees
    function claimFees() external virtual nonReentrant onlyRole(OPERATOR_ROLE) {
        uint256 claimable = _claimableFees();

        if (claimable == 0) revert NoFundsToRelease();

        _claimedFees += claimable;
        Address.sendValue(_feeRecipient, claimable);
    }

    /*
     * Public views on the internal state
     */

    /// @notice Get the approved stake quota
    function stakeQuota() external view virtual returns (uint256) {
        return _stakeQuota();
    }

    /// @notice Get the amount currently staked
    function stakedBalance() external view virtual returns (uint256) {
        return _principalAtStake;
    }

    /// @notice Get the total amount of principal that can be withdrawn
    function withdrawablePrincipal() external view virtual returns (uint256) {
        if (_withdrawablePrincipal >= address(this).balance) {
            return address(this).balance;
        }

        return _withdrawablePrincipal;
    }

    /// @notice Get the total amount of rewards that can be claimed.
    function claimableRewards() external view virtual returns (uint256) {
        return _claimableRewards();
    }

    /// @notice Get the total amount of rewards that have been claimed.
    function claimedRewards() external view virtual returns (uint256) {
        return _claimedRewards;
    }

    /// @notice Get the total amount of fees that can be claimed.
    function claimableFees() external view virtual returns (uint256) {
        return _claimableFees();
    }

    /// @notice Get the total amount of fees paid.
    function claimedFees() external view virtual returns (uint256) {
        return _claimedFees;
    }

    /// @notice Getter for the billable rewards.
    function billableRewards() external view virtual returns (uint256 ret) {
        return _billableRewards();
    }

    /// @notice Get all public keys that are or have been active
    function allPubkeys() external view virtual returns (bytes[] memory) {
        bytes[] memory pubkeys = new bytes[](_depositDataCount);

        for (uint16 i = 0; i < _numberOfDeposits; i++) {
            StoredDepositData storage storedDepositData = _depositData[i];
            pubkeys[i] = bytes.concat(storedDepositData.pubkey_1, bytes16(storedDepositData.pubkey_2));
        }

        return pubkeys;
    }

    /// @notice Get the address of the fee recipient
    function feeRecipient() external view virtual returns (address) {
        return _feeRecipient;
    }

    /// @notice Get the address of the staker
    function staker() external view virtual returns (address) {
        return _staker;
    }

    /// @notice Get the fee basis points
    function feeBasisPoints() external view virtual returns (uint256) {
        return _feeBasisPoints;
    }

    /// @notice Get the address of the beacon chain deposit contract
    function depositContractAddress() external view virtual returns (IDepositContract) {
        return _depositContractAddress;
    }

    /// @notice Get the next deposit data for a given amount of stake
    /// Reverts if newStake exceeds the stakeQuota
    ///
    /// @param newStake The amount of stake that deposit data is requested for
    function depositData(uint256 newStake) external view virtual returns (DepositData[] memory) {
        if (newStake > _stakeQuota()) revert StakeQuotaTooLow();
        if (newStake == 0) revert InvalidDepositAmount();
        if (newStake % BeaconChain.MAX_EFFECTIVE_BALANCE != 0) {
            revert InvalidDepositAmount();
        }

        uint16 numberOfNewDeposits = uint16(newStake / BeaconChain.MAX_EFFECTIVE_BALANCE);

        // Construct 0x01 withdrawal credentials using the address of this staking vault
        bytes32 withdrawalCredentials = _withdrawalCredentials();
        DepositData[] memory tempDepositData = new DepositData[](numberOfNewDeposits);

        uint16 depositDataOffset = _numberOfDeposits;
        for (uint16 i = 0; i < numberOfNewDeposits; i++) {
            StoredDepositData storage storedDepositData = _depositData[depositDataOffset + i];

            bytes memory pubkey = bytes.concat(storedDepositData.pubkey_1, bytes16(storedDepositData.pubkey_2));
            bytes memory signature = bytes.concat(
                storedDepositData.signature_1, storedDepositData.signature_2, storedDepositData.signature_3
            );

            tempDepositData[i] = DepositData({
                pubkey: pubkey,
                withdrawalCredentials: withdrawalCredentials,
                signature: signature,
                depositDataRoot: BeaconChain.depositDataRoot(
                    pubkey, withdrawalCredentials, signature, BeaconChain.MAX_EFFECTIVE_BALANCE
                ),
                depositValue: BeaconChain.MAX_EFFECTIVE_BALANCE
            });
        }

        return tempDepositData;
    }

    /*
     * Internals
     */

    /// @dev Get the withdrawal credentials of this staking vault.
    /// This staking vault does only use 0x01 withdrawal credentials, pointing validator rewards and withdrawals to
    /// itself.
    ///
    /// @return The withdrawal credentials of this staking vault
    function _withdrawalCredentials() internal view virtual returns (bytes32) {
        bytes32 ret = bytes32(bytes.concat(bytes1(0x01), bytes11(0), bytes20(address(this))));
        return ret;
    }

    /// @dev Get the total amount of rewards that can be claimed.
    function _claimableRewards() internal view virtual returns (uint256) {
        uint256 billable = _billableRewards();

        if (billable == 0) return 0;

        // MAX_BASIS_POINTS = 100%
        uint256 totalRewards = (billable * (MAX_BASIS_POINTS - _feeBasisPoints)) / MAX_BASIS_POINTS;
        return totalRewards - _claimedRewards;
    }

    /// @dev Get the total amount of fees that can be claimed.
    function _claimableFees() internal view virtual returns (uint256) {
        uint256 billable = _billableRewards();

        if (billable == 0) return 0;

        // MAX_BASIS_POINTS = 100%
        uint256 totalFees = (billable * _feeBasisPoints) / MAX_BASIS_POINTS;
        return totalFees - _claimedFees;
    }

    /// @dev Getter for the billable rewards.
    function _billableRewards() internal view virtual returns (uint256 ret) {
        uint256 wp = _withdrawablePrincipal;

        // If there is still principal to be withdrawn, we can't claim rewards or fees
        if (wp >= address(this).balance) return 0;

        return address(this).balance - wp + _claimedFees + _claimedRewards;
    }

    /// @dev Getter for the current stake quota
    function _stakeQuota() internal view virtual returns (uint256) {
        return (_depositDataCount - _numberOfDeposits) * BeaconChain.MAX_EFFECTIVE_BALANCE;
    }

    /*
     * Administrative functions
     */

    /// @notice Update the address of the fee recipient
    function setFeeRecipient(address payable newFeeRecipient) external virtual onlyRole(OPERATOR_ROLE) {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        _feeRecipient = newFeeRecipient;
    }
}
