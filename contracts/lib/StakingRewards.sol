// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IStakingRewardsContract {
    function activateValidators(bytes[] calldata pubkeys) external;
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
contract StakingRewards is AccessControl, IStakingRewardsContract {
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant FEE_RECIPIENT_ROLE =
        keccak256("FEE_RECIPIENT_ROLE");
    bytes32 public constant REWARDS_RECIPIENT_ROLE =
        keccak256("REWARDS_RECIPIENT_ROLE");

    uint256 private constant PUBKEY_LENGTH = 48;
    uint256 private constant STAKE_PER_VALIDATOR = 32 ether;
    uint256 private constant MAX_BASIS_POINTS = 10000;

    event PaymentReleased(address to, uint256 amount);
    event ValidatorExited(bytes exitedValidatorPublicKey);
    event ValidatorsActivated(bytes[] validatorPublicKeys);

    address private immutable _depositContract;
    address payable private immutable _rewardsRecipient;
    address payable private immutable _feeRecipient;

    uint256 private _numberOfActiveValidators;
    mapping(bytes => bool) private _isActiveValidator;

    mapping(address => uint256) private _released;
    uint256 private _totalReleased;
    uint256 private _exitedStake;
    uint256 private immutable _feeBasisPoints;

    error DepositContractZeroAddress();
    error FeeRecipientZeroAddress();
    error RewardsRecipientZeroAddress();
    error InvalidFeeBasisPoints(uint256 newFeeBasisPoints);
    error NoValidatorsToActivate();
    error PublicKeyLengthMismatch();
    error ValidatorAlreadyActive();
    error ValidatorNotActive();
    error SenderNotPermittedToReleaseFunds();
    error NoFundsToRelease();

    /**
     * @dev Creates an instance of `StakingRewards` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(
        address depositContract,
        address payable feeRecipient,
        address payable rewardsRecipient,
        uint256 newFeeBasisPoints
    ) {
        if (depositContract == address(0)) revert DepositContractZeroAddress();
        if (feeRecipient == address(0)) revert FeeRecipientZeroAddress();
        if (rewardsRecipient == address(0))
            revert RewardsRecipientZeroAddress();
        if (newFeeBasisPoints > MAX_BASIS_POINTS)
            revert InvalidFeeBasisPoints(newFeeBasisPoints);

        _depositContract = depositContract;
        _feeRecipient = feeRecipient;
        _rewardsRecipient = rewardsRecipient;
        _feeBasisPoints = newFeeBasisPoints;

        _grantRole(DEPOSITOR_ROLE, depositContract);
        _grantRole(FEE_RECIPIENT_ROLE, feeRecipient);
        _grantRole(REWARDS_RECIPIENT_ROLE, rewardsRecipient);
    }

    /**
     * @dev Getter for the number of active validators.
     */
    function numberOfActiveValidators() external view returns (uint256) {
        return _numberOfActiveValidators;
    }

    /**
     * @dev Getter for the feeBasisPoints.
     */
    function feeBasisPoints() external view returns (uint256) {
        return _feeBasisPoints;
    }

    /**
     * @dev Getter for the total amount of Ether already released.
     */
    function totalReleased() external view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @dev Getter for the amount of Ether already released to a payee.
     */
    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    /**
     * @dev Getter for the amount of an account's releasable Ether.
     */
    function releasable(address account) public view returns (uint256) {
        uint256 totalBalance = address(this).balance + _totalReleased;
        uint256 billableRewards = 0;

        if (totalBalance >= _exitedStake) {
            billableRewards = totalBalance - _exitedStake;
        }

        if (account == _feeRecipient && billableRewards > 0) {
            uint256 totalFees = (billableRewards * _feeBasisPoints) / 10 ** 4;
            uint256 releasedFees = released(_feeRecipient);
            return totalFees - releasedFees;
        } else if (account == _rewardsRecipient) {
            uint256 totalRewards = (billableRewards *
                (MAX_BASIS_POINTS - _feeBasisPoints)) / 10 ** 4;
            uint256 releasedRewards = released(_rewardsRecipient);
            return totalRewards + _exitedStake - releasedRewards;
        } else {
            return 0;
        }
    }

    /**
     * @dev Adds a set of validators to the active set.
     *
     * @param pubkeys The public keys of active validators to add.
     *
     * @notice
     * This function may only be called by the deposit contract.
     */
    function activateValidators(
        bytes[] calldata pubkeys
    ) external virtual onlyRole(DEPOSITOR_ROLE) {
        uint256 numberOfPublicKeys = pubkeys.length;

        if (numberOfPublicKeys == 0) revert NoValidatorsToActivate();

        for (uint256 i = 0; i < numberOfPublicKeys; ) {
            unchecked {
                if (pubkeys[i].length != PUBKEY_LENGTH)
                    revert PublicKeyLengthMismatch();
                if (_isActiveValidator[pubkeys[i]])
                    revert ValidatorAlreadyActive();

                _isActiveValidator[pubkeys[i]] = true;

                ++i;
            }
        }
        _numberOfActiveValidators =
            _numberOfActiveValidators +
            numberOfPublicKeys;
        emit ValidatorsActivated(pubkeys);
    }

    /**
     * @dev Removes an validator from the active set if it is still active.
     *
     * @param pubkey The public key of the active validators to exit.
     *
     * @notice
     * This function may only be called by the rewards recipient.
     */
    function exitValidator(
        bytes calldata pubkey
    ) external virtual onlyRole(REWARDS_RECIPIENT_ROLE) {
        if (pubkey.length != PUBKEY_LENGTH) revert PublicKeyLengthMismatch();
        if (!_isActiveValidator[pubkey]) revert ValidatorNotActive();
        _isActiveValidator[pubkey] = false;
        _numberOfActiveValidators = _numberOfActiveValidators - 1;
        _exitedStake = _exitedStake + STAKE_PER_VALIDATOR;
        emit ValidatorExited(pubkey);
    }

    /**
     * @dev Triggers withdrawal of the accumulated rewards or fees to the respective recipient.
     *
     * @notice
     * This function may only be called by the rewards recipient or fee recipient.
     * The recipient will receive the Ether they are owed since the last time they claimed.
     */
    function release() external virtual {
        if (
            !hasRole(REWARDS_RECIPIENT_ROLE, msg.sender) &&
            !hasRole(FEE_RECIPIENT_ROLE, msg.sender)
        ) revert SenderNotPermittedToReleaseFunds();

        // We know that the rewards recipient and fee recipients are payable,
        // hence can confidently cast the msg.sender to be payable
        address payable recipient = payable(msg.sender);
        uint256 releasableFunds = releasable(recipient);

        if (releasableFunds == 0) revert NoFundsToRelease();

        _totalReleased = _totalReleased + releasableFunds;
        unchecked {
            _released[recipient] = _released[recipient] + releasableFunds;
        }

        emit PaymentReleased(recipient, releasableFunds);
        Address.sendValue(recipient, releasableFunds);
    }
}
