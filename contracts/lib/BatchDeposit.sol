// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./StakingRewards.sol";
import "../interfaces/IDepositContract.sol";

/**
 * @title BatchDeposit
 *
 * @dev This contract allows to batch deposit validators to the Ethereum 2.0
 * deposit contract. The validators available for deposit are registered by the
 * contract owner.
 */
contract BatchDeposit is Ownable, ReentrancyGuard {
    address private immutable depositContract;

    uint256 private constant PUBKEY_LENGTH = 48;
    uint256 private constant SIGNATURE_LENGTH = 96;
    uint256 private constant MAX_VALIDATORS_PER_BATCH = 100;
    uint256 private constant DEPOSIT_AMOUNT = 32 ether;

    enum ValidatorState {
        None,
        Registered,
        Activated
    }
    mapping(bytes => ValidatorState) private _validatorStates;

    event Deposited(address from, uint256 nodesAmount);

    error NotPayable();
    error InvalidDepositContractAddress();
    error NoValidatorsToRegister();
    error PublicKeyLengthMismatch();
    error ValidatorAlreadyRegistered();
    error ValidatorIsOrWasActive();
    error InvalidNumberOfValidators();
    error InvalidTransactionAmount();
    error SignaturesLengthMismatch();
    error DepositDataRootsLengthMismatch();
    error SignatureLengthMismatch();
    error ValidatorNotAvailable();

    constructor(address depositContractAddr) {
        if (depositContractAddr == address(0))
            revert InvalidDepositContractAddress();

        depositContract = depositContractAddr;
    }

    /**
     * @dev This contract will not accept direct ETH transactions.
     */
    receive() external payable {
        revert NotPayable();
    }

    /**
     * @dev Returns whether a validator is available.
     *
     * @param pubkey The BLS12-381 public key of the validator.
     *
     * @return bool Whether the validator is available.
     */
    function isValidatorAvailable(
        bytes calldata pubkey
    ) external view returns (bool) {
        return _validatorStates[pubkey] == ValidatorState.Registered;
    }

    /**
     * @dev Register public keys of validators that are ready to be deposited to.
     *
     * @param pubkeys The BLS12-381 public keys of the validators.
     *
     * @notice
     * One the contract owner may register new validators.
     */
    function registerValidators(bytes[] calldata pubkeys) external onlyOwner {
        uint256 numberOfValidators = pubkeys.length;

        if (numberOfValidators == 0) revert NoValidatorsToRegister();

        for (uint256 i = 0; i < numberOfValidators; ) {
            unchecked {
                if (pubkeys[i].length != PUBKEY_LENGTH)
                    revert PublicKeyLengthMismatch();
                if (_validatorStates[pubkeys[i]] == ValidatorState.Registered)
                    revert ValidatorAlreadyRegistered();
                if (_validatorStates[pubkeys[i]] == ValidatorState.Activated)
                    revert ValidatorIsOrWasActive();

                _validatorStates[pubkeys[i]] = ValidatorState.Registered;

                ++i;
            }
        }
    }

    /**
     * @dev Allows to deposit multiple validators in a single transaction.
     *
     * @param stakingRewardsContract The address of an instance of the StakingRewards contract.
     * @param pubkeys The BLS12-381 public keys of the validators.
     * @param signatures The BLS12-381 signatures of the deposit messages.
     * @param depositDataRoots The deposit data roots of the validators.
     *
     * @notice
     * Only Type 1 withdrawal credentials are supported. The withdrawal
     * credentials are constructed using a leading 0x01 to indicate that it
     * is an Ethereum address followed by 11 zero bytes to pad the credential
     * to 32 bytes.
     *
     * Validator public keys must have been registered prior to depositing to
     * them.
     *
     * The following parameters must be provided in the same order:
     * - The BLS12-381 public keys of the validators.
     * - The BLS12-381 signatures of the deposit messages.
     * - The deposit data roots of the validators.
     */
    function batchDeposit(
        address stakingRewardsContract,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external payable nonReentrant {
        uint256 numberOfValidators = pubkeys.length;

        // Construct the withdrawal credential using a leading 0x01 to indicate that it is an Ethereum address
        // followed by 11 zero bytes to pad the credential to 32 bytes.
        bytes memory withdrawalCredential = abi.encodePacked(
            bytes1(0x01),
            bytes11(0),
            bytes20(stakingRewardsContract)
        );

        if (
            numberOfValidators == 0 ||
            numberOfValidators > MAX_VALIDATORS_PER_BATCH
        ) revert InvalidNumberOfValidators();
        if (msg.value != DEPOSIT_AMOUNT * numberOfValidators)
            revert InvalidTransactionAmount();
        if (signatures.length != pubkeys.length)
            revert SignaturesLengthMismatch();
        if (depositDataRoots.length != pubkeys.length)
            revert DepositDataRootsLengthMismatch();

        for (uint256 i = 0; i < numberOfValidators; ) {
            unchecked {
                if (pubkeys[i].length != PUBKEY_LENGTH)
                    revert PublicKeyLengthMismatch();
                if (signatures[i].length != SIGNATURE_LENGTH)
                    revert SignatureLengthMismatch();
                if (_validatorStates[pubkeys[i]] != ValidatorState.Registered)
                    revert ValidatorNotAvailable();

                _validatorStates[pubkeys[i]] = ValidatorState.Activated;

                IDepositContract(depositContract).deposit{
                    value: DEPOSIT_AMOUNT
                }(
                    pubkeys[i],
                    withdrawalCredential,
                    signatures[i],
                    depositDataRoots[i]
                );

                ++i;
            }
        }

        IStakingRewardsContract(stakingRewardsContract).activateValidators(
            pubkeys
        );

        emit Deposited(msg.sender, numberOfValidators);
    }
}
