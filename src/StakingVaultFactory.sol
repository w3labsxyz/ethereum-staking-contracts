// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {StakingVaultV0} from "./StakingVault.v0.sol";

contract StakingVaultFactory is Ownable, ReentrancyGuardTransientUpgradeable {
    /// @dev The address of the StakingVault implementation contract
    StakingVaultV0 private immutable _stakingVault;

    /// @dev The StakingVault contract instances by owner
    mapping(address => StakingVaultV0) private _vaultsByOwner;

    /// @dev The default address of the node operator used for new vaults
    address payable private _defaultOperator;

    /// @dev The default address of the fee recipient used for new vaults
    address payable private _defaultFeeRecipient;

    /// @dev The default fee basis points used for new vaults
    uint256 private _defaultFeeBasisPoints;

    /// @dev An error raised when a user tries to create multiple vaults
    error OneVaultPerAddress();

    /// @dev Error when the implementation address is the zero address
    error ImplementationZeroAddress();

    /// @dev Error when the operator address is the zero address
    error OperatorZeroAddress();

    /// @dev Error when the fee recipient address is the zero address
    error FeeRecipientZeroAddress();

    /// @dev Event emitted when a new vault is created
    event VaultCreated(address indexed owner, address indexed vault);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        StakingVaultV0 newStakingVault,
        address payable newOperator,
        address payable newFeeRecipient,
        uint256 newFeeBasisPoints
    ) Ownable(msg.sender) {
        _disableInitializers();

        if (address(newStakingVault) == address(0))
            revert ImplementationZeroAddress();

        if (newOperator == address(0)) revert OperatorZeroAddress();
        if (newFeeRecipient == address(0)) revert FeeRecipientZeroAddress();

        _stakingVault = newStakingVault;
        _defaultOperator = newOperator;
        _defaultFeeRecipient = newFeeRecipient;
        _defaultFeeBasisPoints = newFeeBasisPoints;
    }

    /// @notice Create a new proxy to the StakingVault
    function createVault() external nonReentrant returns (address) {
        if (hasVault(msg.sender)) revert OneVaultPerAddress();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(_stakingVault),
            abi.encodeWithSelector(
                StakingVaultV0.initializeV0.selector,
                _defaultOperator,
                _defaultFeeRecipient,
                msg.sender,
                _defaultFeeBasisPoints
            )
        );

        _vaultsByOwner[msg.sender] = StakingVaultV0(address(proxy));

        emit VaultCreated(msg.sender, address(proxy));

        return address(proxy);
    }

    /*
     * Public views on the internal state
     */

    /// @notice Get the address of the StakingVault implementation contract
    function stakingVault() public view returns (StakingVaultV0) {
        return _stakingVault;
    }

    /// @notice Get the address of the StakingVault of a specific owner
    function vaultForAddress(
        address staker
    ) public view returns (StakingVaultV0) {
        return _vaultsByOwner[staker];
    }

    /// @notice Check whether a specific owner has a StakingVault
    function hasVault(address vaultOwner) public view returns (bool) {
        return address(_vaultsByOwner[vaultOwner]) != address(0);
    }

    /// @notice Get the address of the default operator
    function defaultOperator() public view returns (address) {
        return _defaultOperator;
    }

    /// @notice Get the address of the default fee recipient
    function defaultFeeRecipient() public view returns (address) {
        return _defaultFeeRecipient;
    }

    /*
     * Administrative functions to update the default operator and feeRecipient
     */

    /// @notice Update the address of the default operator
    function setDefaultOperator(
        address payable newOperator
    ) external onlyOwner {
        if (newOperator == address(0)) revert OperatorZeroAddress();

        _defaultOperator = newOperator;
    }

    /// @notice Update the address of the default fee recipient
    function setDefaultFeeRecipient(
        address payable newFeeRecipient
    ) external onlyOwner {
        if (newFeeRecipient == address(0)) revert FeeRecipientZeroAddress();

        _defaultFeeRecipient = newFeeRecipient;
    }

    /// @notice Update the default fee basis points
    function setDefaultFeeBasisPoints(
        uint256 newFeeBasisPoints
    ) external onlyOwner {
        _defaultFeeBasisPoints = newFeeBasisPoints;
    }
}
