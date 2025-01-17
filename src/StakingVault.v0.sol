// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
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
    UUPSUpgradeable
{
    /*
     * Access Control
     */

    /// @dev Role for the node operator
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Role for the staker
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

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

    /*
     * Contract lifecycle
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize instances of this contract
    function initialize_v0(
        address payable newOperator,
        address payable newFeeRecipient,
        address payable newStaker,
        uint256 newFeeBasisPoints,
        IDepositContract newDepositContractAddress
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _operator = newOperator;
        _grantRole(OPERATOR_ROLE, newOperator);

        _feeRecipient = newFeeRecipient;

        _staker = newStaker;
        _grantRole(STAKER_ROLE, _staker);

        if (newFeeBasisPoints > MAX_BASIS_POINTS)
            revert InvalidFeeBasisPoints(newFeeBasisPoints);
        _feeBasisPoints = newFeeBasisPoints;

        if (block.chainid == 1) {
            _depositContractAddress = IDepositContract(
                // https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa
                0x00000000219ab540356cBB839Cbe05303d7705Fa
            );
        } else if (block.chainid == 17_000) {
            _depositContractAddress = IDepositContract(
                // https://holesky.etherscan.io/address/0x4242424242424242424242424242424242424242
                0x4242424242424242424242424242424242424242
            );
        } else {
            // For other networks, such as those used in testing, we use the supplied address
            _depositContractAddress = newDepositContractAddress;
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
    ) public onlyRole(OPERATOR_ROLE) {
        _revokeRole(OPERATOR_ROLE, _operator);
        _grantRole(OPERATOR_ROLE, newOperator);
        _operator = newOperator;
    }

    /// @notice Update the address of the fee recipient
    function setFeeRecipient(
        address payable newFeeRecipient
    ) public onlyRole(OPERATOR_ROLE) {
        _feeRecipient = newFeeRecipient;
    }

    /*
     * Public views on the internal state
     */

    /// @notice Get the address of the operator
    function operator() public view returns (address) {
        return _operator;
    }

    /// @notice Get the address of the fee recipient
    function feeRecipient() public view returns (address) {
        return _feeRecipient;
    }

    /// @notice Get the address of the staker
    function staker() public view returns (address) {
        return _staker;
    }

    /// @notice Get the fee basis points
    function feeBasisPoints() public view returns (uint256) {
        return _feeBasisPoints;
    }

    /// @notice Get the address of the beacon chain deposit contract
    function depositContractAddress() public view returns (IDepositContract) {
        return _depositContractAddress;
    }
}
