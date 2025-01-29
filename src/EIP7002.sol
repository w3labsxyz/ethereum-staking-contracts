// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title EIP-7002 Compatibility Layer
/// @dev This is a simple wrapper for compatibility with the contract provided via EIP-7002.
///
/// @custom:security-contact security@w3labs.xyz
abstract contract EIP7002 {
    /// @dev The address of the withdrawal request predeploy contract
    address internal _withdrawalRequestPredeployAddress;

    /// @dev The number of withdrawal requests per block
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    uint256 private constant TARGET_WITHDRAWAL_REQUESTS_PER_BLOCK = 2;

    /// @dev The maximum downwards rate of change of the blob gas price
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    uint256 private constant WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION = 17;

    /// @dev The minimum withdrawal request fee
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    uint256 private constant MIN_WITHDRAWAL_REQUEST_FEE = 1;

    /// @dev Error thrown pre EIP-7002 contract deployment
    error EIP7002ContractNotDeployed();

    /// @dev Error when the fee can not be retrieved
    error EIP7002FailedToGetFee();

    /// @dev Error when the withdrawal request can not be added
    error EIP7002FailedToAddWithdrawalRequest();

    /// @notice Get the recommended fee for submitting multiple withdrawal requests at once
    /// @param numberOfWithdrawalRequests number of withdrawal requests
    /// @dev As stated in the EIP-7002 specification, the fee is only updated at the end of
    /// a block. Hence, adding multiple withdrawal requests using the current fee in the same
    /// block is safe to do. Compare: https://eips.ethereum.org/EIPS/eip-7002#fee-update-rule
    /// @return The recommended fee (in Wei) for the given number of withdrawal request
    function _recommendedWithdrawalRequestsFee(uint256 numberOfWithdrawalRequests) internal virtual returns (uint256) {
        uint256 baseFee = _getEip7002Fee();

        if (numberOfWithdrawalRequests == 0) return baseFee;

        return baseFee * numberOfWithdrawalRequests;
    }

    /// @dev Get the next fee for a withdrawal request by calling the eip-7002 contract
    /// without any message value or payload data as per the spec in:
    /// https://eips.ethereum.org/EIPS/eip-7002#withdrawal-request-contract
    /// @return The fee (in Wei) for one withdrawal request
    function _getEip7002Fee() internal virtual ifEIP7002IsDeployed returns (uint256) {
        (bool success, bytes memory feeData) = _withdrawalRequestPredeployAddress.call("");

        if (!success) revert EIP7002FailedToGetFee();

        return uint256(bytes32(feeData));
    }

    /// @dev Add a withdrawal request to the eip-7002 contract
    /// by submitting 56 bytes: 48 bytes public key and 8 bytes withdrawal amount in gwei
    /// See: https://eips.ethereum.org/EIPS/eip-7002#withdrawal-request-contract
    /// @dev This function forwards the entire message value to the eip-7002 contract
    /// @param pubkey The public key of the validator to trigger a withdrawal for
    /// @param withdrawalAmount The withdrawal amount in gwei
    function _addEip7002WithdrawalRequest(
        bytes calldata pubkey,
        uint64 withdrawalAmount,
        uint256 withdrawalFee
    )
        internal
        virtual
        ifEIP7002IsDeployed
    {
        bytes memory callData = abi.encodePacked(pubkey, withdrawalAmount);
        (bool success,) = _withdrawalRequestPredeployAddress.call{ value: withdrawalFee }(callData);

        if (!success) revert EIP7002FailedToAddWithdrawalRequest();
    }

    /// @dev Modifier to check if the EIP-7002 contract is deployed
    modifier ifEIP7002IsDeployed() {
        uint256 codeSize;
        address target = _withdrawalRequestPredeployAddress;
        assembly {
            codeSize := extcodesize(target)
        }
        if (codeSize == 0) revert EIP7002ContractNotDeployed();
        _;
    }
}
