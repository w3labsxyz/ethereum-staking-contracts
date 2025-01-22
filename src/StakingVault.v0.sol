// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IDepositContract} from "@ethereum/beacon-deposit-contract/IDepositContract.sol";

/// @title StakingVault V0
/// @notice This is the base layer of our StakingVault contract, implementing
/// access control and the UUPS (EIP-1822).
/// The actual staking concerns are implemented in inheriting contracts.
///
/// @custom:security-contact security@w3labs.xyz
contract StakingVaultV0 is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    UUPSUpgradeable
{
    /*
     * Access Control
     */

    /// @dev Role for the node operator
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Role for the staker
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    /// @dev Role for depositors
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /// @dev Fees can not exceed 100%
    uint256 private constant MAX_BASIS_POINTS = 10_000;

    /*
     * State variables of the base contract
     */

    /// @dev The address of the node operator
    address payable internal _operator;

    /// @dev The address of the fee recipient
    address payable internal _feeRecipient;

    /// @dev The address of the staker
    address payable internal _staker;

    /// @dev The basis points charged as a fee
    uint256 internal _feeBasisPoints;

    /// @dev The address of the beacon chain deposit contract
    /// See: https://eips.ethereum.org/EIPS/eip-2982#parameters
    IDepositContract internal _depositContractAddress;

    /*
     * Errors
     */

    error InvalidFeeBasisPoints(uint256 feeBasisPoints);

    error ZeroAddress();

    error InvalidRoleRemoval();

    /*
     * Contract lifecycle
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize instances of this contract
    function initializeV0(
        address payable newOperator,
        address payable newFeeRecipient,
        address payable newStaker,
        uint256 newFeeBasisPoints
    ) external initializer {
        if (newOperator == address(0)) revert ZeroAddress();
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        if (newStaker == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _operator = newOperator;
        _grantRole(OPERATOR_ROLE, newOperator);

        _feeRecipient = newFeeRecipient;

        _staker = newStaker;
        _grantRole(STAKER_ROLE, _staker);
        _grantRole(DEPOSITOR_ROLE, _staker);

        if (newFeeBasisPoints > MAX_BASIS_POINTS)
            revert InvalidFeeBasisPoints(newFeeBasisPoints);

        _feeBasisPoints = newFeeBasisPoints;

        if (block.chainid == 1) {
            _depositContractAddress = IDepositContract(
                // https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa
                0x00000000219ab540356cBB839Cbe05303d7705Fa
            );
        } else {
            _depositContractAddress = IDepositContract(
                // For other networks, such as those used in testing, we use the supplied address
                // https://holesky.etherscan.io/address/0x4242424242424242424242424242424242424242
                0x4242424242424242424242424242424242424242
            );
        }
    }

    /// @notice Authorizes that upgrades via `upgradeToAndCall` can only be done by the staker
    /// @dev Implementation provided for the requirement of the `UUPSUpgradeable` interface
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(STAKER_ROLE) {}

    /*
     * Administrative functions
     */

    /// @notice Update the address of the operator
    function setOperator(
        address payable newOperator
    ) external onlyRole(OPERATOR_ROLE) {
        if (newOperator == address(0)) revert ZeroAddress();
        _revokeRole(OPERATOR_ROLE, _operator);
        _grantRole(OPERATOR_ROLE, newOperator);
        _operator = newOperator;
    }

    /// @notice Update the address of the fee recipient
    function setFeeRecipient(
        address payable newFeeRecipient
    ) external onlyRole(OPERATOR_ROLE) {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        _feeRecipient = newFeeRecipient;
    }

    /// @notice Add additional depositors to the allowlist
    function addDepositor(
        address payable depositor
    ) external onlyRole(STAKER_ROLE) {
        if (depositor == address(0)) revert ZeroAddress();
        _grantRole(DEPOSITOR_ROLE, depositor);
    }

    /// @notice Remove depositors from the allowlist
    /// @dev Can't remove the staker from the allowlist
    function removeDepositor(
        address payable depositor
    ) external onlyRole(STAKER_ROLE) {
        if (depositor == address(0)) revert ZeroAddress();
        if (depositor == _staker) revert InvalidRoleRemoval();
        _revokeRole(DEPOSITOR_ROLE, depositor);
    }

    /*
     * Public views on the internal state
     */

    /// @notice Get the address of the operator
    function operator() external view returns (address) {
        return _operator;
    }

    /// @notice Get the address of the fee recipient
    function feeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    /// @notice Get the address of the staker
    function staker() external view returns (address) {
        return _staker;
    }

    /// @notice Check whether an address is a depositor
    function isDepositor(address depositor) external view returns (bool) {
        return hasRole(DEPOSITOR_ROLE, depositor);
    }

    /// @notice Get the fee basis points
    function feeBasisPoints() external view returns (uint256) {
        return _feeBasisPoints;
    }

    /// @notice Get the address of the beacon chain deposit contract
    function depositContractAddress() external view returns (IDepositContract) {
        return _depositContractAddress;
    }
}
