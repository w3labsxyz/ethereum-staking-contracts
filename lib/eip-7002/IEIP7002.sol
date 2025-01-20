pragma solidity ^0.8.28;

/// @dev This interface is designed to be compatible with EIP-7002.
/// See: https://eips.ethereum.org/EIPS/eip-7002
interface IEIP7002 {
    /// @dev Add withdrawal request adds new request to the withdrawal request queue, so long as a sufficient fee is provided.
    /// @param pubkey The public key of the validator.
    /// @param amount The amount to withdraw in Gwei.
    function addWithdrawalRequest(
        bytes calldata pubkey,
        uint64 amount
    ) external;

    /// @dev Get the current fee for adding withdrawals
    /// If the input length is zero, return the current fee required to add a withdrawal request.
    /// @return The fee required to add a withdrawal request.
    function getFee() external view returns (uint256);
}
