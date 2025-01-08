import * as fs from "fs";

import { task } from "hardhat/config";

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

    const depositPromises = depositData.map((record) =>
      ethereumDepositContract
        .deposit(
          record.pubkey,
          record.withdrawal_credentials,
          record.signature,
          record.deposit_data_root,
          { value },
        )
        .then((tx) => {
          console.log(
            `Sent deposit for account ${record.account} with public key ${record.pubkey}, tx hash: ${tx.hash}`,
          );
          return tx.wait().then(() => {
            console.log(`Transaction confirmed for account ${record.account}`);
          });
        }),
    );
    await Promise.all(depositPromises);
  });
