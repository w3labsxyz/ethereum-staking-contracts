// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IDepositForwarderContract.sol";

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
contract StakingRewards is
    AccessControl,
    Ownable,
    IStakingRewardsContract,
    IDepositForwarderContract
{
    bytes32 public constant REWARDS_RECIPIENT_ROLE =
        keccak256("REWARDS_RECIPIENT_ROLE");

    uint256 private constant PUBKEY_LENGTH = 48;
    uint256 private constant STAKE_PER_VALIDATOR = 32 ether;
    uint256 private constant MAX_BASIS_POINTS = 10000;

    event PaymentReleased(address to, uint256 amount);
    event ValidatorExited(bytes exitedValidatorPublicKey);
    event ValidatorsActivated(bytes[] validatorPublicKeys);

    /// @notice The address of the beacon chain deposit contract
    /// https://eips.ethereum.org/EIPS/eip-2982#parameters
    IDepositContract private immutable _depositContractAddress;

    // Fork version
    bytes4 private immutable _forkVersion;

    /// @notice The address of the EIP-7002 withdrawal requests contract
    /// https://eips.ethereum.org/EIPS/eip-7002#configuration
    address private immutable _withdrawalRequestsContractAddress =
        0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA;

    /// @notice The address of the EIP-4788 beacon block root oracle contract
    /// https://eips.ethereum.org/EIPS/eip-4788#specification
    address private immutable _beaconRootsContractAddress =
        0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /// @notice The size of the ring buffer storing the beacon block roots
    /// https://eips.ethereum.org/EIPS/eip-4788#specification
    uint256 internal constant BEACON_ROOTS_HISTORY_BUFFER_LENGTH = 8191;

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
    error BeaconRootsHistoryOutOfRange();
    error BeaconRootsHistoryInvalid();

    /**
     * @dev Creates an instance of `StakingRewards` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(
        address deployer,
        address payable feeRecipient,
        address payable rewardsRecipient,
        uint256 newFeeBasisPoints
    ) Ownable(deployer) {
        if (feeRecipient == address(0)) revert FeeRecipientZeroAddress();
        if (rewardsRecipient == address(0))
            revert RewardsRecipientZeroAddress();
        if (newFeeBasisPoints > MAX_BASIS_POINTS)
            revert InvalidFeeBasisPoints(newFeeBasisPoints);

        _depositContractAddress = (block.chainid == 1)
            ? IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa)
            : IDepositContract(0x4242424242424242424242424242424242424242);

        _forkVersion = 0x00000000;
        if (block.chainid == 1337) {
            _forkVersion = 0x10000038;
        } else if (block.chainid == 17000) {
            _forkVersion = 0x01017000;
        }

        _genesisValidatorsRoot = 0x4b363db94e286120d76eb905340fdd4e54bfe9f06bf33ff6cf5ad27f511bfe95;

        if (block.chainid == 1337) {
            _genesisValidatorsRoot = 0xd61ea484febacfae5298d52a2b581f3e305a51f3112a9241b968dccf019f7b11;
        } else if (block.chainid == 17000) {
            _genesisValidatorsRoot = 0x9143aa7c615a7f7115e2b6aac319c03529df8242ae705fba9df39b79c59fa8b1;
        }

        _feeRecipient = feeRecipient;
        _rewardsRecipient = rewardsRecipient;
        _feeBasisPoints = newFeeBasisPoints;

        // TODO: _grantRole(DEPOSITOR_ROLE, depositContract);
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
     * @dev Get the currently active stake, i.e., the amount of Ether locked into Validators.
     */
    // TODO: Implement this function

    /**
     * @dev Get the total amount of rewards that can be claimed.
     */
    function claimableRewards() public view returns (uint256) {
        uint256 _billableRewards = billableRewards();

        uint256 totalRewards = (_billableRewards *
            (MAX_BASIS_POINTS - _feeBasisPoints)) / 10 ** 4;
        uint256 releasedRewards = released(_rewardsRecipient);
        return totalRewards + _exitedStake - releasedRewards;
    }

    /**
     * @dev Get the total amount of rewards that have been claimed.
     */
    function claimedRewards() public view returns (uint256) {
        return _released[_rewardsRecipient];
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
        uint256 releasedFees = released(_feeRecipient);
        return totalFees - releasedFees;
    }

    /**
     * @dev Get the total amount of fees paid.
     */
    function paidFees() public view returns (uint256) {
        return _released[_feeRecipient];
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
    ) external virtual /* TODO: Authz onlyRole(DEPOSITOR_ROLE) */ {
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
     * @dev Triggers withdrawal of the accumulated rewards and fees to the respective recipients.
     *
     * @notice
     * This function may only be called by the rewards recipient.
     * The recipients will receive the Ether they are owed since the last claiming.
     */
    function claim() external virtual onlyRole(REWARDS_RECIPIENT_ROLE) {
        uint256 _claimableRewards = claimableRewards();
        uint256 _payableFees = payableFees();

        if (_claimableRewards == 0 && _payableFees == 0)
            revert NoFundsToRelease();

        _totalReleased = _totalReleased + _claimableRewards + _payableFees;
        unchecked {
            _released[_rewardsRecipient] =
                _released[_rewardsRecipient] +
                _claimableRewards;
            _released[_feeRecipient] = _released[_feeRecipient] + _payableFees;
        }

        if (_claimableRewards > 0) {
            emit PaymentReleased(_rewardsRecipient, _claimableRewards);
            Address.sendValue(_rewardsRecipient, _claimableRewards);
        }

        if (_payableFees > 0) {
            emit PaymentReleased(_feeRecipient, _payableFees);
            Address.sendValue(_feeRecipient, _payableFees);
        }
    }

    error InvalidDepositSignature();

    /**
     * @dev Accepts the deposit for a validator and forwards the deposit as-is to the beacon deposit contract.
     *
     * @param pubkey A BLS12-381 public key.
     * @param withdrawalCredentials Commitment to a public key for withdrawals.
     * @param signature A BLS12-381 signature.
     * @param depositDataRoot The SHA-256 hash of the SSZ-encoded DepositData object.
     */
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable override {
        // if (
        //     !_isDepositSignatureValid(
        //         pubkey,
        //         withdrawalCredentials,
        //         signature,
        //         depositDataRoot,
        //         msg.value
        //     )
        // ) revert InvalidDepositSignature();

        unchecked {
            IDepositContract(_depositContractAddress).deposit{value: msg.value}(
                pubkey,
                withdrawalCredentials,
                signature,
                depositDataRoot
            );
        }
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

    // Genesis validators root should be set based on target network
    bytes32 private immutable _genesisValidatorsRoot; // GENESIS_VALIDATORS_ROOT;

    /// Execution-spec constants taken from https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md
    /// DOMAIN_DEPOSIT 	DomainType('0x03000000')
    // bytes private constant DEPOSIT_DOMAIN_TYPE = 0x03000000;

    // Verification
    /*

    function _isDepositSignatureValid(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 amount
    ) internal view returns (bool) {
        // Compute deposit domain
        bytes32 domain = _computeDomain(
            DEPOSIT_DOMAIN_TYPE,
            _forkVersion,
            _genesisValidatorsRoot
        );

        // Verify withdrawal credentials format
        // First byte should be 0x00 for BLS withdrawal or 0x01 for execution withdrawal
        require(
            withdrawalCredentials[0] == 0x01,
            "Invalid withdrawal credentials version"
        );

        // Reconstruct deposit message
        bytes32 depositMessage = sha256(
            abi.encode(pubkey, withdrawalCredentials, amount)
        );

        // Construct signing root
        bytes32 signingRoot = sha256(abi.encode(depositMessage, domain));

        // Here you would need to implement or import BLS signature verification
        // This is complex and typically done off-chain, but for completeness:
        // return BLS.verify(pubkey, signingRoot, signature);

        // For now, we'll return true but note this needs actual BLS verification
        return true;
    }

    function _computeDomain(
        bytes32 domainType,
        bytes4 forkVersion,
        bytes32 genesisValidatorsRoot
    ) internal pure returns (bytes32) {
        bytes32 forkDataRoot = sha256(
            abi.encode(forkVersion, genesisValidatorsRoot)
        );
        return bytes32(uint256(domainType) | (uint256(forkDataRoot) >> 32));
    }
*/
    uint256 private constant SIGNATURE_LENGTH = 96;
    error NoValidatorsToRegister();
    error InvalidDepositData();
    error SignatureLengthMismatch();
    error InvalidDepositAmount();

    enum DepositState {
        Registered,
        Activated
    }

    uint private _depositDataCount = 0;
    struct DepositData {
        DepositState state;
        bytes pubkey;
        bytes signature;
        uint256 depositValue;
    }
    mapping(uint => DepositData) private _depositData;

    /// Node operations
    /**
     * @dev Register deposit data for verification and subsequent deposit.
     * @param pubkeys The BLS12-381 public keys of the validators
     * @param signatures The BLS12-381 signatures of the deposit messages
     */
    function registerDepositData(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        uint256[] calldata depositValues
    ) external onlyOwner {
        uint256 numberOfValidators = pubkeys.length;

        if (numberOfValidators == 0) revert NoValidatorsToRegister();

        if (
            pubkeys.length != signatures.length ||
            pubkeys.length != depositValues.length
        ) {
            revert InvalidDepositData();
        }

        for (uint256 i = 0; i < numberOfValidators; ) {
            unchecked {
                if (pubkeys[i].length != PUBKEY_LENGTH)
                    revert PublicKeyLengthMismatch();
                if (signatures[i].length != SIGNATURE_LENGTH)
                    revert SignatureLengthMismatch();
                // if deposit value is less than 1 ether
                if (depositValues[i] < 1 ether) revert InvalidDepositAmount();

                // TODO: Check pubkey is not already registered
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
                    depositValue: depositValues[i]
                });
                ++i;
            }
        }

        _depositDataCount += numberOfValidators;
        emit DepositDataRegistered();
    }

    event DepositDataRegistered();

    /* *
     * @dev Returns the full deposit data for verification.
     * @param depositIndex The BLS12-381 public key of the validator
     * @return DepositData struct containing state, signature and deposit data root
     */
    function getDepositData(
        uint depositIndex
    )
        external
        view
        returns (
            DepositState state,
            bytes memory signature,
            bytes memory pubkey,
            uint256 depositValue
        )
    {
        DepositData memory data = _depositData[depositIndex];
        return (data.state, data.signature, data.pubkey, data.depositValue);
    }

    // Generator point for G2 (negative)
    // These are the coordinates for -G2 point on alt_bn128
    uint256 private constant nG2x1 =
        0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2;
    uint256 private constant nG2x0 =
        0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed;
    uint256 private constant nG2y1 =
        0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b;
    uint256 private constant nG2y0 =
        0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa;

    /**
     * @dev Verifies a BLS signature for a validator's deposit.
     * This is computationally expensive (>100k gas) but can be used to verify signatures before depositing.
     * @param pubkey The BLS12-381 public key of the validator
     * @param message The message to verify (hash of deposit data)
     * @param signature The BLS signature
     * @return bool Whether the signature is valid
     */
    function verifySignature(
        bytes memory pubkey,
        bytes memory message,
        bytes memory signature
    ) public view returns (bool) {
        require(pubkey.length == PUBKEY_LENGTH, "Invalid pubkey length");
        require(
            signature.length == SIGNATURE_LENGTH,
            "Invalid signature length"
        );

        // Convert signature to uint256[2] for pairing (G1 point)
        uint256[2] memory sig;
        assembly {
            sig := signature
        }

        // Convert pubkey to uint256[4] for pairing (G2 point)
        uint256[4] memory pk;
        assembly {
            pk := pubkey
        }

        // Convert message to uint256[2] for pairing (G1 point)
        uint256[2] memory msg;
        assembly {
            msg := message
        }

        // Input for pairing check: e(signature, -G2) * e(message, pubkey) = 1
        uint256[12] memory input = [
            sig[0],
            sig[1], // signature
            nG2x1,
            nG2x0, // -G2.x
            nG2y1,
            nG2y0, // -G2.y
            msg[0],
            msg[1], // message
            pk[1],
            pk[0], // pubkey.x (reversed for big-endian)
            pk[3],
            pk[2] // pubkey.y (reversed for big-endian)
        ];

        uint256[1] memory out;
        bool success;

        // Call the pairing precompile at address 0x8
        assembly {
            success := staticcall(
                gas(), // Forward all gas
                8, // Precompile address for pairing
                input, // Input data
                384, // Input size (12 * 32 bytes)
                out, // Output data
                0x20 // Output size (32 bytes)
            )
        }

        require(success, "Pairing check failed");
        return out[0] != 0;
    }

    /**
     * @dev Returns whether a validator's deposit data is valid by checking the signature.
     * This is computationally expensive but useful for verification before depositing.
     * @param depositIndex The index of the deposit to verify
     * @return bool Whether the deposit data is valid
     */
    function verifyValidatorDepositData(
        uint depositIndex,
        bytes calldata pubkey,
        bytes calldata signature,
        uint256 depositValue
    ) external view returns (bool) {
        // DepositData memory data = _depositData[depositIndex];
        // TODO: if (data.state != DepositData.Registered) return false;

        // TODO: Compare calldata signature to memory signature and pubkey and deposit value!

        // Construct the withdrawal credential using a leading 0x01 to indicate that it is an Ethereum address
        // followed by 11 zero bytes to pad the credential to 32 bytes.
        bytes memory withdrawalCredential = abi.encodePacked(
            bytes1(0x01),
            bytes11(0),
            bytes20(address(this))
        );

        // First verify deposit data root matches
        bytes32 computedRoot = _computeDepositDataRoot(
            pubkey,
            withdrawalCredential,
            signature,
            depositValue
        );
        // if (computedRoot != data.depositDataRoot) return false;

        // Then verify the BLS signature
        // Note: In practice, you'd need to properly construct the message
        // by hashing the deposit data according to the spec
        bytes memory message = abi.encodePacked(computedRoot);
        return verifySignature(pubkey, message, signature);
    }

    function _computeDepositDataRoot(
        bytes calldata pubkey,
        bytes memory withdrawalCredential,
        bytes calldata signature,
        uint256 amount
    ) internal pure returns (bytes32) {
        bytes32 pubkeyRoot = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );

        // Convert amount to little-endian bytes
        bytes memory amountSSZ = new bytes(8);
        uint64 amountGwei = uint64(amount / 1 gwei);
        for (uint i = 0; i < 8; i++) {
            amountSSZ[i] = bytes1(uint8(amountGwei >> (8 * i)));
        }

        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(pubkeyRoot, withdrawalCredential)),
                    sha256(
                        abi.encodePacked(amountSSZ, bytes24(0), signatureRoot)
                    )
                )
            );
    }
}
