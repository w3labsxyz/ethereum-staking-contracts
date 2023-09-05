import { task } from "hardhat/config";

task("staking-rewards:deploy", "deploy the StakingRewards contract")
  .addParam(
    "batchDepositContractAddress",
    "The address of the BatchDeposit contract",
  )
  .addParam("feeAddress", "The address of the Justfarming fee wallet")
  .addParam("feeBasisPoints", "The fee (in basis points)")
  .addParam(
    "rewardsAddress",
    "The address of the customer who will receive the rewards",
  )
  .setAction(
    async ({
      batchDepositContractAddress,
      feeAddress,
      feeBasisPoints,
      rewardsAddress,
    }) => {
      const [_deployer] = await ethers.getSigners();

      const stakingRewardsContract = await ethers.deployContract(
        "StakingRewards",
        [
          batchDepositContractAddress,
          feeAddress,
          rewardsAddress,
          feeBasisPoints,
        ],
        { value: 0 },
      );
      await stakingRewardsContract.waitForDeployment();

      console.log(
        `StakingRewards contract deployed to: ${stakingRewardsContract.target}`,
      );
    },
  );
