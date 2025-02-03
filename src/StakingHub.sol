// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { StakingVault } from "./StakingVault.sol";
import { IStakingHub } from "./interfaces/IStakingHub.sol";

contract StakingHub is IStakingHub, AccessControl, ReentrancyGuardTransient {
    /*
     * Access Control
     */

    /// @dev Role for the node operator
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev Role for StakingVaults
    bytes32 public constant STAKING_VAULT_ROLE = keccak256("STAKING_VAULT_ROLE");

    /*
     * State
     */

    /// @dev The address of the StakingVault implementation contract
    StakingVault private _stakingVaultImplementation;

    /// @dev The StakingVault contract instances by owner
    mapping(address => StakingVault) private _vaultsByOwner;

    /// @dev The default address of the node operator used for new vaults
    address payable private _defaultOperator;

    /// @dev The default address of the fee recipient used for new vaults
    address payable private _defaultFeeRecipient;

    /// @dev The default fee basis points used for new vaults
    uint256 private _defaultFeeBasisPoints;

    /*
     * Events
     */

    /// @dev Event emitted when a new vault is created
    event VaultCreated(address indexed owner, address indexed vault);

    /// @dev Event emitted when a stake quota is requested for a vault
    event StakeQuotaRequested(address vault, uint256 amount);

    /// @dev Event emitted when a stake is deposited to a vault
    event StakeDeposited(address vault, uint256 amount);

    /// @dev Event emitted when a vault issues an unbonding request
    event StakeUnbondingRequested(address vault, bytes[] pubkeys);

    /*
     * Errors
     */

    /// @dev An error raised when a user tries to create multiple vaults
    error OneVaultPerAddress();

    /// @dev Error when the implementation address is the zero address
    error ImplementationZeroAddress();

    /// @dev Error when the operator address is the zero address
    error OperatorZeroAddress();

    /// @dev Error when the fee recipient address is the zero address
    error FeeRecipientZeroAddress();

    /// @dev Error when a vault can not be found
    error VaultNotFound();

    /*
     * Contract Lifecycle
     */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        StakingVault newStakingVault,
        address payable newOperator,
        address payable newFeeRecipient,
        uint256 newFeeBasisPoints
    ) {
        if (address(newStakingVault) == address(0)) {
            revert ImplementationZeroAddress();
        }

        if (newOperator == address(0)) revert OperatorZeroAddress();
        if (newFeeRecipient == address(0)) revert FeeRecipientZeroAddress();

        _grantRole(OPERATOR_ROLE, newOperator);

        _stakingVaultImplementation = newStakingVault;
        _defaultOperator = newOperator;
        _defaultFeeRecipient = newFeeRecipient;
        _defaultFeeBasisPoints = newFeeBasisPoints;
    }

    /// @notice Create a new proxy to the StakingVault
    function createVault(uint256 initialStakeQuota) external nonReentrant returns (StakingVault) {
        if (hasVault(msg.sender)) revert OneVaultPerAddress();

        StakingVault vault = _deployVault(msg.sender, initialStakeQuota);

        _vaultsByOwner[msg.sender] = vault;
        _grantRole(STAKING_VAULT_ROLE, address(vault));

        emit VaultCreated(msg.sender, address(vault));
        emit StakeQuotaRequested(address(vault), initialStakeQuota);

        return vault;
    }

    /// @dev Predict the address of a vault for a specific owner
    /// @param staker The owner of the vault
    /// @param initialStakeQuota The initial stake quota
    /// @return The address of the vault
    function predictVaultAddress(address staker, uint256 initialStakeQuota) external view returns (StakingVault) {
        bytes32 salt = keccak256(abi.encodePacked(staker));
        bytes memory bytecode = _getVaultCreationCode(staker, initialStakeQuota);

        address vaultAddress = Create2.computeAddress(salt, keccak256(bytecode), address(this));
        return StakingVault(payable(vaultAddress));
    }

    /*
     * Interface for StakingVaults
     */

    /// @dev Announce a new stake quota request
    function announceStakeQuotaRequest(address staker, uint256 amount) external onlyRole(STAKING_VAULT_ROLE) {
        address vault = address(_vaultsByOwner[staker]);
        if (vault != msg.sender) revert VaultNotFound();
        emit StakeQuotaRequested(vault, amount);
    }

    /// @dev Announce a new stake deposit
    function announceStakeDelegation(address staker, uint256 amount) external onlyRole(STAKING_VAULT_ROLE) {
        address vault = address(_vaultsByOwner[staker]);
        if (vault != msg.sender) revert VaultNotFound();
        emit StakeDeposited(vault, amount);
    }

    // @dev Announce unbonding
    function announceUnbondingRequest(address staker, bytes[] calldata pubkeys) external onlyRole(STAKING_VAULT_ROLE) {
        address vault = address(_vaultsByOwner[staker]);
        if (vault != msg.sender) revert VaultNotFound();
        emit StakeUnbondingRequested(vault, pubkeys);
    }

    /*
     * Public views on the internal state
     */

    /// @notice Get the address of the StakingVault of a specific owner
    function vaultOfStaker(address staker) public view returns (StakingVault) {
        return _vaultsByOwner[staker];
    }

    /// @notice Check whether a specific owner has a StakingVault
    function hasVault(address vaultOwner) public view returns (bool) {
        return address(_vaultsByOwner[vaultOwner]) != address(0);
    }

    /// @notice Get the address of the StakingVault implementation contract
    function defaultStakingVaultImplementation() public view returns (StakingVault) {
        return _stakingVaultImplementation;
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
     * Administration
     */

    /// @notice Update the address of the default operator
    function setDefaultOperator(address payable newOperator) external onlyRole(OPERATOR_ROLE) {
        if (newOperator == address(0)) revert OperatorZeroAddress();

        _defaultOperator = newOperator;
    }

    /// @notice Update the address of the default fee recipient
    function setDefaultFeeRecipient(address payable newFeeRecipient) external onlyRole(OPERATOR_ROLE) {
        if (newFeeRecipient == address(0)) revert FeeRecipientZeroAddress();

        _defaultFeeRecipient = newFeeRecipient;
    }

    /// @notice Update the default fee basis points
    function setDefaultFeeBasisPoints(uint256 newFeeBasisPoints) external onlyRole(OPERATOR_ROLE) {
        _defaultFeeBasisPoints = newFeeBasisPoints;
    }

    /// @notice Update the default StakingVault implementation contract
    function setDefaultStakingVaultImplementation(StakingVault newStakingVault) external onlyRole(OPERATOR_ROLE) {
        if (address(newStakingVault) == address(0)) {
            revert ImplementationZeroAddress();
        }

        _stakingVaultImplementation = newStakingVault;
    }

    /*
     * Internal functions
     */

    /// @dev Deploy a contract using the CREATE2 opcode
    /// @param staker The owner of the vault
    /// @param initialStakeQuota The initial stake quota
    /// @return The address of the deployed contract
    function _deployVault(address staker, uint256 initialStakeQuota) internal virtual returns (StakingVault) {
        bytes32 salt = keccak256(abi.encodePacked(staker));
        bytes memory bytecode = _getVaultCreationCode(staker, initialStakeQuota);

        address vaultAddress = Create2.deploy(0, salt, bytecode);
        return StakingVault(payable(vaultAddress));
    }

    /// @dev Get the bytecode for deploying a proxy to the StakingVault
    /// @param staker The owner of the vault
    /// @param initialStakeQuota The initial stake quota
    /// @return The bytecode
    function _getVaultCreationCode(
        address staker,
        uint256 initialStakeQuota
    )
        internal
        view
        virtual
        returns (bytes memory)
    {
        // The following code is equivalent to the following Solidity code:
        // new ERC1967Proxy(
        //     address(_stakingVaultImplementation),
        //     abi.encodeWithSelector(
        //         StakingVault.initialize.selector,
        //         address(this),
        //         _defaultOperator,
        //         _defaultFeeRecipient,
        //         staker,
        //         _defaultFeeBasisPoints,
        //         initialStakeQuota
        //     )
        // );
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                address(_stakingVaultImplementation),
                abi.encodeWithSelector(
                    StakingVault.initialize.selector,
                    address(this),
                    _defaultOperator,
                    _defaultFeeRecipient,
                    staker,
                    _defaultFeeBasisPoints,
                    initialStakeQuota
                )
            )
        );
    }
}
