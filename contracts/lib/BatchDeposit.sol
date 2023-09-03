// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./StakingRewards.sol";
import "../interfaces/IDepositContract.sol";

/**
 * @title BatchDeposit
 *
 * @dev This contract allows to batch deposit validators to the Ethereum 2.0
 * deposit contract. The validators available for deposit are registered by the
 * contract owner.
 */
contract BatchDeposit is Ownable, ReentrancyGuard {
    address immutable depositContract;

    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant MAX_VALIDATORS_PER_BATCH = 100;
    uint256 constant DEPOSIT_AMOUNT = 32 ether;
    uint64 constant DEPOSIT_AMOUNT_GWEI = uint64(DEPOSIT_AMOUNT / 1 gwei);

    mapping(bytes => bool) private _isValidatorAvailable;

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
        revert("This contract does not accept ETH being sent to it");
    }

    /**
     * @dev Returns whether a validator is available.
     *
     * @param pubkey The BLS12-381 public key of the validator.
     *
     * @return bool Whether the validator is available.
     */
    function isValidatorAvailable(
        bytes calldata pubkey
    ) public view returns (bool) {
        return _isValidatorAvailable[pubkey];
    }

    /**
     * @dev Register public keys of validators that are ready to be deposited to.
     *
     * @param pubkeys The BLS12-381 public keys of the validators.
     *
     * @notice
     * One the contract owner may register new validators.
     */
    function registerValidators(bytes[] calldata pubkeys) external onlyOwner {
        uint256 numberOfValidators = pubkeys.length;

        require(
            numberOfValidators > 0,
            "the number of validators to register must be greater than 0"
        );

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            require(
                pubkeys[i].length == PUBKEY_LENGTH,
                "public key must be 48 bytes long"
            );
            require(
                !_isValidatorAvailable[pubkeys[i]],
                "validator is already registered"
            );

            _isValidatorAvailable[pubkeys[i]] = true;
        }
    }

    /**
     * @dev Allows to deposit multiple validators in a single transaction.
     *
     * @param stakingRewardsContract The address of an instance of the StakingRewards contract.
     * @param pubkeys The BLS12-381 public keys of the validators.
     * @param signatures The BLS12-381 signatures of the deposit messages.
     *
     * @notice
     * Only Type 1 withdrawal credentials are supported. The withdrawal
     * credentials are constructed using a leading 0x01 to indicate that it
     * is an Ethereum address followed by 11 zero bytes to pad the credential
     * to 32 bytes.
     *
     * Validator public keys must have been registered prior to depositing to
     * them.
     *
     * The following parameters must be provided in the same order:
     * - The BLS12-381 public keys of the validators.
     * - The BLS12-381 signatures of the deposit messages.
     *
     * Also note that deposit data roots are not required as they are calculated
     * by this contract. This is not the most gas efficient way to deposit
     * validators, but it is enabling improved reviewability of batch deposits
     * especially on hardware wallets.
     */
    function batchDeposit(
        address stakingRewardsContract,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures
    ) external payable nonReentrant {
        uint256 numberOfValidators = pubkeys.length;

        // Construct the withdrawal credential using a leading 0x01 to indicate that it is an Ethereum address
        // followed by 11 zero bytes to pad the credential to 32 bytes.
        bytes memory withdrawalCredential = abi.encodePacked(
            bytes1(0x01),
            bytes11(0),
            bytes20(stakingRewardsContract)
        );

        require(
            numberOfValidators > 0 &&
                numberOfValidators <= MAX_VALIDATORS_PER_BATCH,
            "the number of validators must be greater than 0 and less than or equal to 100"
        );
        require(
            msg.value == DEPOSIT_AMOUNT * numberOfValidators,
            "the transaction amount must be equal to the number of validators to deploy multiplied by 32 ETH"
        );
        require(
            signatures.length == pubkeys.length,
            "the number of signatures must match the number of public keys"
        );

        for (uint256 i = 0; i < numberOfValidators; ++i) {
            require(
                pubkeys[i].length == PUBKEY_LENGTH,
                "public key must be 48 bytes long"
            );
            require(
                signatures[i].length == SIGNATURE_LENGTH,
                "signature must be 96 bytes long"
            );
            require(
                _isValidatorAvailable[pubkeys[i]],
                "validator is not available"
            );

            bytes32 depositDataRoot = _getDepositDataRoot(
                DEPOSIT_AMOUNT_GWEI,
                withdrawalCredential,
                pubkeys[i],
                signatures[i]
            );

            _isValidatorAvailable[pubkeys[i]] = false;

            IDepositContract(depositContract).deposit{value: DEPOSIT_AMOUNT}(
                pubkeys[i],
                withdrawalCredential,
                signatures[i],
                depositDataRoot
            );
        }

        IStakingRewardsContract(stakingRewardsContract).activateValidators(
            pubkeys
        );

        emit DepositEvent(msg.sender, numberOfValidators);
    }

    /**
     * @dev Calculate the deposit root hash for a given deposit.
     *
     * @param depositAmount The amount of ETH to be deposited in gwei.
     * @param withdrawalCredential The withdrawal credentials of the validator.
     * @param pubkey The BLS12-381 public key of the validator.
     * @param signature The BLS12-381 signature of the deposit message.
     *
     * @return The deposit root hash.
     *
     * @notice
     * This function is implemented in accordance with the official Ethereum
     * specification. See the following link for the original implementation:
     * https://github.com/ethereum/consensus-specs/blob/e3a939e439d6c05356c9c29c5cd347384180bc01/
     * ... solidity_deposit_contract/deposit_contract.sol#L129
     */
    function _getDepositDataRoot(
        uint64 depositAmount,
        bytes memory withdrawalCredential,
        bytes calldata pubkey,
        bytes calldata signature
    ) internal pure returns (bytes32) {
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(pubkey_root, withdrawalCredential)),
                    sha256(
                        abi.encodePacked(
                            _toLittleEndian64(depositAmount),
                            bytes24(0),
                            signature_root
                        )
                    )
                )
            );
    }

    /**
     * @dev Convert a uint64 to a little endian byte array.
     *
     * @param value The uint64 value to convert.
     *
     * @return ret The little endian byte array.
     *
     * @notice
     * This function is copied from the official Ethereum specification:
     * https://github.com/ethereum/consensus-specs/blob/e3a939e439d6c05356c9c29c5cd347384180bc01/
     * ... solidity_deposit_contract/deposit_contract.sol#L165
     */
    function _toLittleEndian64(
        uint64 value
    ) internal pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
