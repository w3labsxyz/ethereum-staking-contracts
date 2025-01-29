// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Test } from "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StakingVaultSetup } from "./lib/StakingVaultSetup.t.sol";

/// @dev The following tests our implementation of EIP-7002 fees
/// We have generated the testvectors using `/bin/generate_eip7002_testvectors.py` in the root directory
contract EIP7002Test is Test, StakingVaultSetup {
    using stdJson for string;

    struct TestVector {
        uint256 baseExcess;
        uint256 baseFee;
        uint256 expectedFee;
        uint256 numberOfWithdrawalRequests;
    }

    TestVector[] private _vectors;

    function setUp() public override {
        super.setUp();

        // Load test vectors from JSON file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/tests/fixtures/eip7002_testvectors.json");
        string memory json = vm.readFile(path);

        // Parse the JSON array
        bytes memory vectorsData = json.parseRaw(".vectors");
        TestVector[] memory vectors = abi.decode(vectorsData, (TestVector[]));

        // Store vectors for testing
        for (uint256 i = 0; i < vectors.length; i++) {
            _vectors.push(vectors[i]);
        }
    }

    function test_feeRecommendationVectors() public {
        address wrpa = withdrawalRequestPredeployAddress;

        for (uint256 i = 0; i < _vectors.length; i++) {
            TestVector memory vector = _vectors[i];

            // Mock the baseFee value from our test vector
            vm.mockCall(wrpa, bytes(""), abi.encode(vector.baseFee));

            // Check fee calculation for one request
            uint256 fee = stakingVaultProxy.recommendedWithdrawalRequestsFee(vector.numberOfWithdrawalRequests);

            assertEq(fee, vector.expectedFee);
        }
    }
}
