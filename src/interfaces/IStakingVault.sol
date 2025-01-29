// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IDepositContract } from "@ethereum/beacon-deposit-contract/IDepositContract.sol";

interface IStakingVault {
    /*
     * Data structures
     */

    /// @dev The structure of stored, i.e., partial deposit data
    /// @dev To save gas, we chunk the 48 bytes public keys and 96 bytes signatures into 32 bytes pieces.
    /// @dev To save gas, the assumption is that the deposit value is always MAX_EFFECTIVE_BALANCE
    /// @param pubkey The BLS12-381 public key of the validator
    /// @param signature The BLS12-381 signature of the deposit message
    struct StoredDepositData {
        bytes32 pubkey_1;
        bytes32 pubkey_2;
        bytes32 signature_1;
        bytes32 signature_2;
        bytes32 signature_3;
    }

    /// @dev The structure of full deposit data
    /// @param pubkey The BLS12-381 public key of the validator
    /// @param signature The BLS12-381 signature of the deposit message
    /// @param depositValue The deposit value of the validator
    struct DepositData {
        bytes pubkey;
        bytes32 withdrawalCredentials;
        bytes signature;
        bytes32 depositDataRoot;
        uint256 depositValue;
    }

    function requestStakeQuota(uint256 newRequestedStakeQuota) external;

    function approveStakeQuota(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        uint256[] calldata depositValues
    )
        external;

    function recommendedWithdrawalRequestsFee(uint256 numberOfWithdrawalRequests) external returns (uint256);

    function requestUnbondings(bytes[] calldata pubkeys) external payable;

    function attestUnbondings(bytes[] calldata pubkeys) external;

    function withdrawPrincipal() external;

    function claimRewards() external;

    function claimFees() external;

    function stakeQuota() external view returns (uint256);

    function stakedBalance() external view returns (uint256);

    function withdrawablePrincipal() external view returns (uint256);

    function claimableRewards() external view returns (uint256);

    function claimedRewards() external view returns (uint256);

    function claimableFees() external view returns (uint256);

    function claimedFees() external view returns (uint256);

    function billableRewards() external view returns (uint256 ret);

    function allPubkeys() external view returns (bytes[] memory);

    function depositData(uint256 newStake) external view returns (DepositData[] memory);

    function setFeeRecipient(address payable newFeeRecipient) external;

    function feeRecipient() external view returns (address);

    function staker() external view returns (address);

    function feeBasisPoints() external view returns (uint256);

    function depositContractAddress() external view returns (IDepositContract);
}
