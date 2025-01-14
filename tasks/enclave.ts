import { task } from "hardhat/config";

task("debug:transaction", "Debugs a transaction")
  .addParam("txHash", "The transaction hash")
  .setAction(async ({ txHash }, hre) => {
    const provider = new ethers.JsonRpcProvider(
      hre.config.networks.localnet.url,
    );
    const txReceipt = await provider.getTransactionReceipt(txHash);
    await provider.getTransaction(txHash);

    if (txReceipt === null) {
      console.log("Transaction not found or still pending.");
      return;
    }

    console.log("Transaction Details");
    console.log("===================");
    console.log(txReceipt);

    const block = await provider.getBlock(txReceipt.blockNumber);
    console.log("=============");
    console.log(`Status: ${txReceipt.status === 1 ? "Success" : "Failure"}`);
    console.log(`Timestamp: ${new Date(block.timestamp * 1000).toUTCString()}`);
  });

task(
  "debug:list-deposits",
  "Fetches deposits to the Ethereum 2.0 deposit contract",
)
  .addParam(
    "ethereumDepositContractAddress",
    "The address of the Ethereum deposit contract",
  )
  .setAction(async ({ ethereumDepositContractAddress }, hre) => {
    const provider = new ethers.JsonRpcProvider(
      hre.config.networks.localnet.url,
    );

    const latestBlockNumber = await provider.getBlockNumber();
    const logs = await provider.getLogs({
      fromBlock: 0,
      toBlock: latestBlockNumber,
      address: ethereumDepositContractAddress,
      topics: [ethers.id("DepositEvent(bytes,bytes,bytes,bytes,bytes)")],
    });

    if (logs.length === 0) {
      console.log("No deposits found.");
      return;
    }

    console.log(`Deposits to Contract: ${ethereumDepositContractAddress}`);
    console.log("===================================================");

    logs.forEach((depositLog: unknown, i: number) => {
      console.log(`Deposit ${i + 1}`);
      console.log("---------------------------------------------------");
      console.log({ depositLog });
      console.log("---------------------------------------------------");
    });
  });
