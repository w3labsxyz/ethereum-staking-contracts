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
    address immutable depositContract;

    error NotPayable();

    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant MAX_VALIDATORS_PER_BATCH = 100;
    uint256 constant DEPOSIT_AMOUNT = 32 ether;

    mapping(bytes => bool) private _isValidatorAvailable;

    event DepositEvent(address from, uint256 nodesAmount);

    constructor(address depositContractAddr) {
        require(
            depositContractAddr != address(0),
            "Invalid deposit contract address"
        );

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
    ) public view returns (bool) {
        return _isValidatorAvailable[pubkey];
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

        require(
            numberOfValidators > 0,
            "the number of validators to register must be greater than 0"
        );

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            require(
                pubkeys[i].length == PUBKEY_LENGTH,
                "public key must be 48 bytes long"
            );
            require(
                !_isValidatorAvailable[pubkeys[i]],
                "validator is already registered"
            );

            _isValidatorAvailable[pubkeys[i]] = true;
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

        require(
            numberOfValidators > 0 &&
                numberOfValidators <= MAX_VALIDATORS_PER_BATCH,
            "the number of validators must be greater than 0 and less than or equal to 100"
        );
        require(
            msg.value == DEPOSIT_AMOUNT * numberOfValidators,
            "the transaction amount must be equal to the number of validators to deploy multiplied by 32 ETH"
        );
        require(
            signatures.length == pubkeys.length,
            "the number of signatures must match the number of public keys"
        );
        require(
            depositDataRoots.length == pubkeys.length,
            "the number of deposit data roots must match the number of public keys"
        );

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            require(
                pubkeys[i].length == PUBKEY_LENGTH,
                "public key must be 48 bytes long"
            );
            require(
                signatures[i].length == SIGNATURE_LENGTH,
                "signature must be 96 bytes long"
            );
            require(
                _isValidatorAvailable[pubkeys[i]],
                "validator is not available"
            );

            _isValidatorAvailable[pubkeys[i]] = false;

            IDepositContract(depositContract).deposit{value: DEPOSIT_AMOUNT}(
                pubkeys[i],
                withdrawalCredential,
                signatures[i],
                depositDataRoots[i]
            );
        }

        IStakingRewardsContract(stakingRewardsContract).activateValidators(
            pubkeys
        );

        emit DepositEvent(msg.sender, numberOfValidators);
    }
}
