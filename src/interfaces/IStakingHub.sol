// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { StakingVault } from "../StakingVault.sol";

interface IStakingHub {
    function createVault(uint256 initialStakeQuota) external returns (StakingVault);

    function announceStakeQuotaRequest(address staker, uint256 amount) external;

    function announceStakeDelegation(address staker, uint256 amount) external;

    function announceUnbondingRequest(address staker, bytes[] calldata pubkeys) external;
}
