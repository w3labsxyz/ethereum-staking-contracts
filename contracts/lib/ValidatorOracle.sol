// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IDepositForwarderContract.sol";
import "./LittleEndian.sol";

interface IValidatorOracle {
    // TODO: Add funs function activateValidators(bytes[] calldata pubkeys) external;
}

/**
 * @title StakingRewards
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
contract ValidatorOracle is IValidatorOracle, Ownable {
    /// @notice The address of the EIP-4788 beacon block root oracle contract
    /// https://eips.ethereum.org/EIPS/eip-4788#specification
    address private immutable _beaconRootsContractAddress =
        0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /// @notice The size of the ring buffer storing the beacon block roots
    /// https://eips.ethereum.org/EIPS/eip-4788#specification
    uint256 internal constant BEACON_ROOTS_HISTORY_BUFFER_LENGTH = 8191;

    error BeaconRootsHistoryOutOfRange();
    error BeaconRootsHistoryInvalid();

    /**
     * @dev Creates an instance of the `ValidatorOracle` contract.
     */
    constructor(address deployer) Ownable(deployer) {}

    // types
    enum VALIDATOR_STATUS {
        INACTIVE, // doesnt exist
        ACTIVE, // staked on ethpos and withdrawal credentials are pointed to the EigenPod
        WITHDRAWN // withdrawn from the Beacon Chain
    }

    struct ValidatorInfo {
        // index of the validator in the beacon chain
        uint64 validatorIndex;
        // amount of beacon chain ETH restaked on EigenLayer in gwei
        uint64 restakedBalanceGwei;
        //timestamp of the validator's most recent balance update
        uint64 lastCheckpointedAt;
        // status of the validator
        VALIDATOR_STATUS status;
    }

    struct Checkpoint {
        bytes32 beaconBlockRoot;
        uint24 proofsRemaining;
        uint64 podBalanceGwei;
        int128 balanceDeltasGwei;
    }

    /// @notice This is a mapping that tracks a validator's information by their pubkey hash
    mapping(bytes32 => ValidatorInfo) internal _validatorPubkeyHashToInfo;

    /// @notice The current checkpoint, if there is one active
    Checkpoint internal _currentCheckpoint;

    // public view functions

    /// @notice Returns the validatorInfo for a given validatorPubkeyHash
    function validatorPubkeyHashToInfo(
        bytes32 validatorPubkeyHash
    ) external view returns (ValidatorInfo memory) {
        return _validatorPubkeyHashToInfo[validatorPubkeyHash];
    }

    /// @notice Returns the validatorInfo for a given validatorPubkey
    function validatorPubkeyToInfo(
        bytes calldata validatorPubkey
    ) external view returns (ValidatorInfo memory) {
        return
            _validatorPubkeyHashToInfo[
                _calculateValidatorPubkeyHash(validatorPubkey)
            ];
    }

    function validatorStatus(
        bytes32 pubkeyHash
    ) external view returns (VALIDATOR_STATUS) {
        return _validatorPubkeyHashToInfo[pubkeyHash].status;
    }

    /// @notice Returns the validator status for a given validatorPubkey
    function validatorStatus(
        bytes calldata validatorPubkey
    ) external view returns (VALIDATOR_STATUS) {
        bytes32 validatorPubkeyHash = _calculateValidatorPubkeyHash(
            validatorPubkey
        );
        return _validatorPubkeyHashToInfo[validatorPubkeyHash].status;
    }

    /// @notice Returns the currently-active checkpoint
    function currentCheckpoint() public view returns (Checkpoint memory) {
        return _currentCheckpoint;
    }

    // internal

    /// @notice Indices for fields in the `Validator` container:
    /// 0: pubkey
    /// 1: withdrawal credentials
    /// 2: effective balance
    /// 3: slashed?
    /// 4: activation eligibility epoch
    /// 5: activation epoch
    /// 6: exit epoch
    /// 7: withdrawable epoch
    ///
    /// (See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator)

    /// @notice Number of fields in the `Validator` container
    /// (See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator)
    uint256 internal constant VALIDATOR_FIELDS_LENGTH = 8;
    uint256 internal constant VALIDATOR_PUBKEY_INDEX = 0;
    uint256 internal constant VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX = 1;
    uint256 internal constant VALIDATOR_BALANCE_INDEX = 2;
    uint256 internal constant VALIDATOR_SLASHED_INDEX = 3;
    uint256 internal constant VALIDATOR_ACTIVATION_EPOCH_INDEX = 5;
    uint256 internal constant VALIDATOR_EXIT_EPOCH_INDEX = 6;

    /// @dev Retrieves a validator's pubkey hash
    function getPubkeyHash(
        bytes32[] memory validatorFields
    ) internal pure returns (bytes32) {
        return validatorFields[VALIDATOR_PUBKEY_INDEX];
    }

    /// @dev Retrieves a validator's withdrawal credentials
    function getWithdrawalCredentials(
        bytes32[] memory validatorFields
    ) internal pure returns (bytes32) {
        return validatorFields[VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX];
    }

    /// @dev Retrieves a validator's effective balance (in gwei)
    function getEffectiveBalanceGwei(
        bytes32[] memory validatorFields
    ) internal pure returns (uint64) {
        return
            LittleEndian.uint64FromLittleEndian(
                validatorFields[VALIDATOR_BALANCE_INDEX]
            );
    }

    /// @dev Retrieves a validator's activation epoch
    function getActivationEpoch(
        bytes32[] memory validatorFields
    ) internal pure returns (uint64) {
        return
            LittleEndian.uint64FromLittleEndian(
                validatorFields[VALIDATOR_ACTIVATION_EPOCH_INDEX]
            );
    }

    /// @dev Retrieves true IFF a validator is marked slashed
    function isValidatorSlashed(
        bytes32[] memory validatorFields
    ) internal pure returns (bool) {
        return validatorFields[VALIDATOR_SLASHED_INDEX] != 0;
    }

    /// @dev Retrieves a validator's exit epoch
    function getExitEpoch(
        bytes32[] memory validatorFields
    ) internal pure returns (uint64) {
        return
            LittleEndian.uint64FromLittleEndian(
                validatorFields[VALIDATOR_EXIT_EPOCH_INDEX]
            );
    }

    // internal
    ///@notice Calculates the pubkey hash of a validator's pubkey as per SSZ spec
    function _calculateValidatorPubkeyHash(
        bytes memory validatorPubkey
    ) internal pure returns (bytes32) {
        require(
            validatorPubkey.length == 48,
            "EigenPod._calculateValidatorPubkeyHash must be a 48-byte BLS public key"
        );
        return sha256(abi.encodePacked(validatorPubkey, bytes16(0)));
    }

    /// @notice Get the beacon block root at a specific timestamp according to the EIP-4788 specification.
    function getParentBlockRoot(
        uint64 timestamp
    ) public view returns (bytes32) {
        if (
            block.timestamp - timestamp >=
            BEACON_ROOTS_HISTORY_BUFFER_LENGTH * 12
        ) revert BeaconRootsHistoryOutOfRange();

        (bool success, bytes memory result) = _beaconRootsContractAddress
            .staticcall(abi.encode(timestamp));

        if (!success || result.length == 0) revert BeaconRootsHistoryInvalid();

        return abi.decode(result, (bytes32));
    }
}
