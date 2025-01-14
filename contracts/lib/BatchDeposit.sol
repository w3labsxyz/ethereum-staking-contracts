// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IDepositContract.sol";

/**
 * @title BatchDeposit
 *
 * @dev This contract allows to batch deposit validators to the Ethereum 2.0
 * deposit contract.
 */
contract BatchDeposit is ReentrancyGuard {
    uint256 private constant PUBKEY_LENGTH = 48;
    uint256 private constant SIGNATURE_LENGTH = 96;
    uint256 private constant MAX_VALIDATORS_PER_BATCH = 100;
    uint256 private constant DEPOSIT_AMOUNT = 32 ether;

    error NotPayable();
    error InvalidDepositContractAddress();
    error InvalidNumberOfValidators();
    error InvalidTransactionAmount();
    error PublicKeyLengthMismatch();
    error SignaturesLengthMismatch();
    error DepositDataRootsLengthMismatch();
    error SignatureLengthMismatch();

    /**
     * @dev This contract will not accept direct ETH transactions.
     */
    receive() external payable {
        revert NotPayable();
    }

    /**
     * @dev Allows to deposit multiple validators in a single transaction.
     *
     * @param stakingRewardsAddress The Ethereum address used for the staking rewards contract.
     * @param pubkeys The BLS12-381 public keys of the validators.
     * @param signatures The BLS12-381 signatures of the deposit messages.
     * @param depositDataRoots The deposit data roots of the validators.
     *
     * @notice
     * The stakingRewards contract must implement the IDepositContract interface.
     *
     * Only Type 1 withdrawal credentials are supported. The withdrawal
     * credentials are constructed using a leading 0x01 to indicate that it
     * is an Ethereum address followed by 11 zero bytes to pad the credential
     * to 32 bytes.
     *
     * The following parameters must be provided in the same order:
     * - The BLS12-381 public keys of the validators.
     * - The BLS12-381 signatures of the deposit messages.
     * - The deposit data roots of the validators.
     */
    function batchDeposit(
        address stakingRewardsAddress,
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
            bytes20(stakingRewardsAddress)
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

                IDepositContract(stakingRewardsAddress).deposit{
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
    }
}
