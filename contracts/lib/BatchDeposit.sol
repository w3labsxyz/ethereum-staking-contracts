// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IDepositContract.sol";

contract BatchDeposit is ReentrancyGuard, Pausable, Ownable {
    using SafeMath for uint256;

    address immutable depositContract;

    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant CREDENTIALS_LENGTH = 32;
    uint256 constant MAX_VALIDATORS = 100;
    uint256 constant DEPOSIT_AMOUNT = 32 ether;

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
        revert("This contract does not accept ETH sent to it");
    }

    /**
     * @dev Allows to deposit 1 to 100 nodes at once.
     *
     * - pubkeys                - Array of BLS12-381 public keys.
     * - withdrawalCredentials  - Array of commitments to a public keys for withdrawals.
     * - signatures             - Array of BLS12-381 signatures.
     * - depositDataRoots       - Array of the SHA-256 hashes of the SSZ-encoded DepositData objects.
     */
    function batchDeposit(
        bytes[] calldata pubkeys,
        bytes[] calldata withdrawalCredentials,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external payable whenNotPaused nonReentrant {
        uint256 numberOfValidators = pubkeys.length;

        require(
            numberOfValidators > 0 && numberOfValidators <= MAX_VALIDATORS,
            "BatchDeposit: You must deposit 1 to 100 nodes per transaction"
        );
        require(
            msg.value == DEPOSIT_AMOUNT * numberOfValidators,
            "BatchDeposit: The amount of ETH does not match the amount of nodes"
        );

        require(
            withdrawalCredentials.length == numberOfValidators,
            "BatchDeposit: You must submit a withdrawal credential for each node"
        );
        require(
            signatures.length == numberOfValidators,
            "BatchDeposit: You must submit a signature for each node"
        );
        require(
            depositDataRoots.length == numberOfValidators,
            "BatchDeposit: You must submit a deposit data root for each node"
        );

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            require(
                pubkeys[i].length == PUBKEY_LENGTH,
                "BatchDeposit: Incorrect public key submitted"
            );
            require(
                withdrawalCredentials[i].length == CREDENTIALS_LENGTH,
                "BatchDeposit: Incorrect withdrawal credentials submitted"
            );
            require(
                signatures[i].length == SIGNATURE_LENGTH,
                "BatchDeposit: Incorrect signature submitted"
            );

            IDepositContract(address(depositContract)).deposit{
                value: DEPOSIT_AMOUNT
            }(
                pubkeys[i],
                withdrawalCredentials[i],
                signatures[i],
                depositDataRoots[i]
            );
        }

        emit DepositEvent(msg.sender, numberOfValidators);
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}
