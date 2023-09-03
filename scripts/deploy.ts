import { ethers } from "hardhat";

async function main() {
  const [_deployer, justfarmingFeeWallet, customer1] =
    await ethers.getSigners();

  const depositContractAddress = "0x4242424242424242424242424242424242424242";

  // Deploying BatchDeposit contract
  const batchDeposit = await ethers.deployContract("BatchDeposit", [
    depositContractAddress,
  ]);
  await batchDeposit.waitForDeployment();
  console.log("BatchDeposit deployed to:", batchDeposit.target);

  // Deploying StakingRewards contract
  const stakingRewards = await ethers.deployContract("StakingRewards", [
    batchDeposit.target,
    justfarmingFeeWallet.address,
    customer1.address,
    1000,
  ]);
  await stakingRewards.waitForDeployment();
  console.log("StakingRewards deployed to:", stakingRewards.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
