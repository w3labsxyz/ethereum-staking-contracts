// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

library BeaconChain {
    // @dev The minimum amount required to activate a validator
    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;

    // @dev The maximum effective balance that a validator can have
    //
    // @dev This value will change with EIP-7251, but only when compounding
    // withdrawal credentials are used. We'll updgrade the contract when
    // the EIP is merged.
    //
    // https://eips.ethereum.org/EIPS/eip-7251
    uint256 public constant MAX_EFFECTIVE_BALANCE = 32 ether;

    /// @dev The byte-length of validator public keys
    uint256 public constant PUBKEY_LENGTH = 48;

    /// @dev The byte-length of validator signatures
    uint256 public constant SIGNATURE_LENGTH = 96;

    /// @dev Error when the deposit amount is not a multiple of gwei or exceeds the maximum uint64 value
    error DepositAmountInvalid();

    /// @dev Calculate the deposit data root based on partial deposit data
    /// The implementation has been adapted from the Ethereum 2.0 specification:
    /// https://github.com/ethereum/consensus-specs/blob/dev/solidity_deposit_contract/deposit_contract.sol#L128-L137
    /// We are using the OpenZeppelin Bytes library for slicing because we are not
    /// handling bytes as calldata but from memory.
    ///
    /// @param pubkey The BLS12-381 public key of the validator
    /// @param withdrawalCredentials The withdrawal credentials of the validator
    /// @param signature The BLS12-381 signature of the deposit message
    function depositDataRoot(
        bytes memory pubkey,
        bytes32 withdrawalCredentials,
        bytes memory signature,
        uint256 depositAmountInWei
    ) internal pure returns (bytes32) {
        // Check deposit amount: The deposit value must be a multiple of gwei
        if (depositAmountInWei % 1 gwei != 0) revert DepositAmountInvalid();

        uint depositAmountInGwei = depositAmountInWei / 1 gwei;
        // The deposit value must not exceed the maximum uint64 value
        if (depositAmountInGwei > type(uint64).max)
            revert DepositAmountInvalid();

        bytes memory depositAmount = _to_little_endian_64(
            uint64(depositAmountInGwei)
        );
        bytes32 pubkeyRoot = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(Bytes.slice(signature, 0, 64))),
                sha256(
                    abi.encodePacked(
                        Bytes.slice(signature, 64, SIGNATURE_LENGTH),
                        bytes32(0)
                    )
                )
            )
        );
        return
            sha256(
                abi.encodePacked(
                    sha256(abi.encodePacked(pubkeyRoot, withdrawalCredentials)),
                    sha256(
                        abi.encodePacked(
                            depositAmount,
                            bytes24(0),
                            signatureRoot
                        )
                    )
                )
            );
    }

    /// @dev Convert a uint64 value to a little-endian byte array
    /// Implementation adapted from the Ethereum 2.0 specification:
    /// https://github.com/ethereum/consensus-specs/blob/dev/solidity_deposit_contract/deposit_contract.sol#L165-L177
    function _to_little_endian_64(
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
