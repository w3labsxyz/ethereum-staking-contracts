import json

# Constants
# https://eips.ethereum.org/EIPS/eip-7002#configuration
MIN_WITHDRAWAL_REQUEST_FEE = 1
WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION = 17

# Implementation according to EIP-7002
# https://eips.ethereum.org/EIPS/eip-7002#fee-calculation
def fake_exponential(factor: int, numerator: int, denominator: int) -> int:
    i = 1
    output = 0
    numerator_accum = factor * denominator
    while numerator_accum > 0:
        output += numerator_accum
        numerator_accum = (numerator_accum * numerator) // (denominator * i)
        i += 1
    return output // denominator


# Generate test vectors for various excess values
# We'll create a range of interesting test cases
test_vectors = []

for i in range(0, 10):
    base_excess = 2 ** i

    for number_of_withdrawal_requests in [1, 2, 8, 16, 32, 64, 100]:
        base_fee = fake_exponential(
            MIN_WITHDRAWAL_REQUEST_FEE,
            base_excess,
            WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION
        )

        expected_fee = base_fee * number_of_withdrawal_requests

        test_vectors.append({
            "numberOfWithdrawalRequests": number_of_withdrawal_requests,
            "baseExcess": base_excess,
            "baseFee": base_fee,
            "expectedFee": expected_fee,
        })

# Output the test vectors in a format suitable for Forge tests
output = {
    "vectors": test_vectors,
    "constants": {
        "MIN_WITHDRAWAL_REQUEST_FEE": MIN_WITHDRAWAL_REQUEST_FEE,
        "WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION": WITHDRAWAL_REQUEST_FEE_UPDATE_FRACTION
    }
}

# Write to file
with open('tests/fixtures/eip7002_testvectors.json', 'w') as f:
    json.dump(output, f, indent=2)

# Print summary
print(f"Generated {len(test_vectors)} test vectors")
for v in test_vectors:
    print(f"Number of withdrawal requests: {v['numberOfWithdrawalRequests']:2d} for excess of {v['baseExcess']:4d} (Base fee: {v['baseFee']:16d} wei) -> Expected fee: {v['expectedFee']:16d} wei")
