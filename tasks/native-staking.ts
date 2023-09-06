import * as fs from "fs";

import { task } from "hardhat/config";

// Define your hardhat task
task("native-staking:deposit", "Deposits funds directly into the Eth2 contract")
  .addParam(
    "ethereumDepositContractAddress",
    "The address of the Ethereum deposit contract",
  )
  .addParam("depositDataPath", "The path to the depositdata.json file")
  .setAction(async ({ ethereumDepositContractAddress, depositDataPath }) => {
    // Read deposit data from file
    const rawData = fs.readFileSync(depositDataPath, "utf8");
    const depositData = JSON.parse(rawData);

    // Get the signer
    const [signer] = await ethers.getSigners();

    const ethereumDepositContract = await ethers.getContractAt(
      "DepositContract",
      ethereumDepositContractAddress,
    );

    const value = ethers.parseEther("32", "wei");

    // Loop through each deposit record and send the deposit
    for (const record of depositData) {
      const tx = await ethereumDepositContract.deposit(
        record.pubkey,
        record.withdrawal_credentials,
        record.signature,
        record.deposit_data_root,
        { value },
      );

      console.log(
        `Sent deposit for account ${record.account} with public key ${record.pubkey}, tx hash: ${tx.hash}`,
      );
      await tx.wait();
      console.log(`Transaction confirmed for account ${record.account}`);
    }
  });
