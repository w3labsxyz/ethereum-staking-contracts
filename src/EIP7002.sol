// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title EIP-7002 Compatibility Layer
/// @dev This is a simple wrapper for compatibility with the contract provided via EIP-7002.
///
/// @custom:security-contact security@w3labs.xyz
abstract contract EIP7002 {
    /// @dev The address of the withdrawal request predeploy contract
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    address private constant WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS =
        address(0x0c15F14308530b7CDB8460094BbB9cC28b9AaaAA);

    /// @dev The number of withdrawal requests per block
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    uint256 private constant TARGET_WITHDRAWAL_REQUESTS_PER_BLOCK = 2;

    /// @dev The maximum downwards rate of change of the blob gas price
    /// See: https://eips.ethereum.org/EIPS/eip-7002#configuration
    uint256 private constant WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION = 17;

    /// @dev Error thrown pre EIP-7002 contract deployment
    error EIP7002ContractNotDeployed();

    /// @dev Error when the fee can not be retrieved
    error EIP7002FailedToGetFee();

    /// @dev Error when the withdrawal request can not be added
    error EIP7002FailedToAddWithdrawalRequest();

    /// @notice Get the recommended fee for submitting multiple withdrawal requests at once
    /// @param numberOfWithdrawalRequests number of withdrawal requests
    /// @dev As stated in the EIP-7002 specification, predicting the exact fee upfront is
    /// generally not possible. Overpaying the fee does not return the overpaid amount,
    /// and underpaying the fee will result in a failed withdrawal request. We therefore
    /// approximate the fee generously.
    /// @return The recommended fee (in Wei) for the given number of withdrawal request
    function _recommendedWithdrawalRequestsFee(
        uint256 numberOfWithdrawalRequests
    ) internal returns (uint256) {
        uint256 baseFee = _getEip7002Fee();

        if (numberOfWithdrawalRequests == 1) {
            return baseFee * numberOfWithdrawalRequests;
        }

        // We assume only one more withdrawal request to fit into the
        // TARGET_WITHDRAWAL_REQUESTS_PER_BLOCK
        uint256 excess = numberOfWithdrawalRequests - 1;

        return
            _fakeExponential(
                baseFee * numberOfWithdrawalRequests,
                excess,
                WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION
            );
    }

    function recommendedWithdrawalRequestsFee(
        uint256 numberOfWithdrawalRequests
    ) external returns (uint256) {
        return _recommendedWithdrawalRequestsFee(numberOfWithdrawalRequests);
    }

    /// @dev Get the next fee for a withdrawal request by calling the eip-7002 contract
    /// without any message value or payload data as per the spec in:
    /// https://eips.ethereum.org/EIPS/eip-7002#withdrawal-request-contract
    /// @return The fee (in Wei) for one withdrawal request
    function _getEip7002Fee() internal ifEIP7002IsDeployed returns (uint256) {
        (
            bool success,
            bytes memory feeData
        ) = WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS.call("");

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
    ) internal ifEIP7002IsDeployed {
        bytes memory callData = abi.encodePacked(pubkey, withdrawalAmount);
        (bool success, ) = WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS.call{
            value: withdrawalFee
        }(callData);

        if (!success) revert EIP7002FailedToAddWithdrawalRequest();
    }

    /// @notice Implements the fake exponential calculation from EIP-7002
    /// See: https://eips.ethereum.org/EIPS/eip-7002#fee-calculation
    /// @param factor The base factor (MIN_WITHDRAWAL_REQUEST_FEE)
    /// @param numerator The excess requests
    /// @param denominator The fee update fraction
    /// @return The calculated fee
    function _fakeExponential(
        uint256 factor,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        uint256 i = 1;
        uint256 output = 0;
        uint256 numeratorAccum = factor * denominator;

        while (numeratorAccum > 0) {
            output += numeratorAccum;
            numeratorAccum = (numeratorAccum * numerator) / (denominator * i);
            i += 1;
        }

        return output / denominator;
    }

    /// @dev Modifier to check if the EIP-7002 contract is deployed
    modifier ifEIP7002IsDeployed() {
        uint256 codeSize;
        address target = WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS;
        assembly {
            codeSize := extcodesize(target)
        }
        if (codeSize == 0) revert EIP7002ContractNotDeployed();
        _;
    }
}
