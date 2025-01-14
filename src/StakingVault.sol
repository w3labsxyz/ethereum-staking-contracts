// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@ethereum/beacon-deposit-contract/IDepositContract.sol";

interface IStakingVault { }

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
contract StakingVault is AccessControl, Ownable, IStakingVault {
    /// General Constants

    uint256 private constant PUBKEY_LENGTH = 48;
    uint256 private constant SIGNATURE_LENGTH = 96;
    uint256 private constant MAX_BASIS_POINTS = 10_000;

    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// General Variables

    /// @notice The address of the beacon chain deposit contract
    /// https://eips.ethereum.org/EIPS/eip-2982#parameters
    IDepositContract private immutable _depositContractAddress;
    address payable private immutable _operator;
    address payable private immutable _staker;
    uint256 private immutable _feeBasisPoints;

    /// General Errors

    error PublicKeyLengthMismatch();
    error SignatureLengthMismatch();
    error InvalidDepositAmount();
    error OperatorZeroAddress();
    error StakerZeroAddress();
    error InvalidFeeBasisPoints(uint256 newFeeBasisPoints);

    /**
     * @dev Creates an instance of `StakingVault`
     *
     */
    constructor(
        address payable staker,
        address payable operator,
        IDepositContract depositContractAddress,
        uint256 newFeeBasisPoints
    )
        Ownable(staker)
    {
        if (operator == address(0)) revert OperatorZeroAddress();
        if (staker == address(0)) revert StakerZeroAddress();
        if (newFeeBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidFeeBasisPoints(newFeeBasisPoints);
        }

        _depositContractAddress = depositContractAddress;
        if (block.chainid == 1) {
            _depositContractAddress = IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa);
        }
        if (block.chainid == 17_000) {
            _depositContractAddress = IDepositContract(0x4242424242424242424242424242424242424242);
        }

        _operator = operator;
        _staker = staker;
        _feeBasisPoints = newFeeBasisPoints;

        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(STAKER_ROLE, staker);
    }

    /// Node operations

    error NoDepositDataToRegister();
    error InvalidDepositData();

    event DepositDataRegistered();

    uint256 private _depositDataCount = 0;
    uint256 private _depositDataIndex = 0;

    enum DepositState {
        Registered
    }

    struct DepositData {
        DepositState state;
        bytes pubkey;
        bytes signature;
        bytes32 depositDataRoot;
        uint256 depositValue;
    }

    mapping(uint256 => DepositData) private _depositData;

    /**
     * @dev Register deposit data for verification and subsequent deposit.
     * @param pubkeys The BLS12-381 public keys of the validators
     * @param signatures The BLS12-381 signatures of the deposit messages
     * @param depositDataRoots The deposit data roots of the validators.
     * @param depositValues The deposit values of the validators
     */
    function registerDepositData(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots,
        uint256[] calldata depositValues
    )
        external
        onlyRole(OPERATOR_ROLE)
    {
        uint256 numberOfDepositData = pubkeys.length;

        if (numberOfDepositData == 0) revert NoDepositDataToRegister();

        if (
            pubkeys.length != signatures.length || pubkeys.length != depositValues.length
                || pubkeys.length != depositDataRoots.length
        ) {
            revert InvalidDepositData();
        }

        for (uint256 i = 0; i < numberOfDepositData;) {
            unchecked {
                if (pubkeys[i].length != PUBKEY_LENGTH) {
                    revert PublicKeyLengthMismatch();
                }
                if (signatures[i].length != SIGNATURE_LENGTH) {
                    revert SignatureLengthMismatch();
                }
                // if deposit value is not equal to 32 ether
                if (depositValues[i] < 1 ether) revert InvalidDepositAmount();

                // TODO: Check pubkey is not already registered
                // TODO: Check pubkey is not already exited
                // if (
                //     _validatorData[pubkeys[i]].state ==
                //     ValidatorState.Registered
                // ) revert ValidatorAlreadyRegistered();
                // if (
                //     _validatorData[pubkeys[i]].state == ValidatorState.Activated
                // ) revert ValidatorIsOrWasActive();

                _depositData[_depositDataCount + i] = DepositData({
                    state: DepositState.Registered,
                    pubkey: pubkeys[i],
                    signature: signatures[i],
                    depositDataRoot: depositDataRoots[i],
                    depositValue: depositValues[i]
                });
                ++i;
            }
        }

        _depositDataCount += numberOfDepositData;
        emit DepositDataRegistered();
    }

    /**
     * @dev Get deposit data at a given index for verification
     * @param index The index of the deposit data
     * @return The deposit data at the given index
     */
    function getDepositData(uint256 index) external view returns (DepositData memory) {
        return _depositData[index];
    }

    /// Depositing

    /// Deposit Errors

    error ValidatorNotActive();
    error NoFundsToRelease();

    /// Deposit Events

    event ValidatorExited(bytes exitedValidatorPublicKey);
    event FundsReleased(address to, uint256 amount);

    /// Deposit Functions

    /**
     * @dev This contract accepts payments and consumes available deposit data
     * by depositing the funds to the beacon chain deposit contract.
     *
     * TODO: Should we limit staking to one address? Or use an allowlist instead?
     */
    receive() external payable {
        if (!hasRole(STAKER_ROLE, _msgSender())) {
            revert AccessControlUnauthorizedAccount(_msgSender(), STAKER_ROLE);
        }

        uint256 depositValue = msg.value;

        // Construct 0x01 withdrawal credentials using the address of this staking vault
        bytes memory withdrawalCredential = abi.encodePacked(bytes1(0x01), bytes11(0), bytes20(address(this)));

        while (depositValue > 0 && _depositDataIndex < _depositDataCount) {
            DepositData storage depositData = _depositData[_depositDataIndex];

            // TODO: Add a DepositState.Verified and check for that instead
            if (depositData.state != DepositState.Registered) {
                // Deposit data will be skipped if not in the correct state
                continue;
            }

            if (depositValue < depositData.depositValue) {
                // If the deposit value is less than the required deposit value
                // revert the transaction
                revert InvalidDepositAmount();
            }

            // TODO: Validate validator is not exited

            // Deposit the funds to the beacon chain deposit contract
            _depositContractAddress.deposit{ value: depositData.depositValue }(
                depositData.pubkey, withdrawalCredential, depositData.signature, depositData.depositDataRoot
            );

            depositValue -= depositData.depositValue;
            _stakedBalance += depositData.depositValue;
            _stakedBalances[depositData.pubkey] += depositData.depositValue;
            delete _depositData[_depositDataIndex];
            ++_depositDataIndex;
        }

        // If there are still funds left, revert the transaction
        if (depositValue > 0) revert InvalidDepositAmount();
    }

    /**
     * @dev Removes an validator from the active set if it is still active.
     *
     * @param pubkey The public key of the active validators to exit.
     *
     * @notice
     * This function may only be called by the rewards recipient.
     */
    function exitValidator(bytes calldata pubkey) external onlyRole(STAKER_ROLE) {
        if (pubkey.length != PUBKEY_LENGTH) revert PublicKeyLengthMismatch();
        if (_stakedBalances[pubkey] == 0) revert ValidatorNotActive();
        uint256 validatorStakeBalance = _stakedBalances[pubkey];

        _stakedBalance -= _stakedBalances[pubkey];
        _stakedBalances[pubkey] = 0;
        _exitedStake = _exitedStake + validatorStakeBalance;

        emit ValidatorExited(pubkey);
    }

    /**
     * @dev Triggers withdrawal of the accumulated rewards and fees to the respective recipients.
     *
     * @notice
     * This function may only be called by the rewards recipient.
     * The recipients will receive the Ether they are owed since the last claiming.
     */
    function claim() external virtual onlyRole(STAKER_ROLE) {
        uint256 _claimableRewards = claimableRewards();
        uint256 _payableFees = payableFees();

        if (_claimableRewards == 0 && _payableFees == 0) {
            revert NoFundsToRelease();
        }

        _totalReleased = _totalReleased + _claimableRewards + _payableFees;
        unchecked {
            _released[_staker] = _released[_staker] + _claimableRewards;
            _released[_operator] = _released[_operator] + _payableFees;
        }

        if (_claimableRewards > 0) {
            emit FundsReleased(_staker, _claimableRewards);
            Address.sendValue(_staker, _claimableRewards);
        }

        if (_payableFees > 0) {
            emit FundsReleased(_operator, _payableFees);
            Address.sendValue(_operator, _payableFees);
        }
    }

    /// Reporting

    /// Reporting Errors

    /// Reporting Events

    /// Reporting Variables

    /// Balance per validator
    mapping(bytes => uint256) private _stakedBalances;
    uint256 private _stakedBalance = 0;

    uint256 private _totalReleased = 0;
    uint256 private _exitedStake = 0;
    mapping(address => uint256) private _released;

    /// Reporting Functions

    /**
     * @dev Getter for the feeBasisPoints.
     */
    function feeBasisPoints() external view returns (uint256) {
        return _feeBasisPoints;
    }

    function stakedBalance() external view returns (uint256) {
        return _stakedBalance;
    }

    /**
     * @dev Get the total amount of rewards that can be claimed.
     */
    function claimableRewards() public view returns (uint256) {
        uint256 _billableRewards = billableRewards();

        uint256 totalRewards = (_billableRewards * (MAX_BASIS_POINTS - _feeBasisPoints)) / 10 ** 4;
        uint256 releasedRewards = _released[_staker];
        return totalRewards + _exitedStake - releasedRewards;
    }

    /**
     * @dev Get the total amount of rewards that have been claimed.
     */
    function claimedRewards() public view returns (uint256) {
        return _released[_staker];
    }

    /**
     * @dev Get the total amount of unpaid fees.
     */
    function payableFees() public view returns (uint256) {
        uint256 _billableRewards = billableRewards();

        if (_billableRewards == 0) {
            return 0;
        }

        uint256 totalFees = (_billableRewards * _feeBasisPoints) / 10 ** 4;
        uint256 releasedFees = _released[_operator];
        return totalFees - releasedFees;
    }

    /**
     * @dev Get the total amount of fees paid.
     */
    function paidFees() public view returns (uint256) {
        return _released[_operator];
    }

    /**
     * @dev Getter for the billable rewards.
     */
    function billableRewards() public view returns (uint256) {
        uint256 totalBalance = address(this).balance + _totalReleased;
        uint256 _billableRewards = 0;

        if (totalBalance >= _exitedStake) {
            _billableRewards = totalBalance - _exitedStake;
        }

        return _billableRewards;
    }
}
