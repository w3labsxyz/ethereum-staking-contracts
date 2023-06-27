import { ethers } from "hardhat";

async function main() {
  const [_deployer, justfarmingFeeWallet, customer1] = await ethers.getSigners();

  // Deploying SplitRewards contract
  const splitRewards = await ethers.deployContract(
    "SplitRewards",
    [[justfarmingFeeWallet.address, customer1.address], [10, 90]],
  );
  await splitRewards.waitForDeployment();
  console.log("SplitRewards deployed to:", splitRewards.target);

  const depositContractAddress = "0x4242424242424242424242424242424242424242"

  // Deploying BatchDeposit contract
  const batchDeposit = await ethers.deployContract(
    "BatchDeposit",
    [depositContractAddress],
  );
  await batchDeposit.waitForDeployment();
  console.log("BatchDeposit deployed to:", batchDeposit.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
