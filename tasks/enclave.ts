import * as dotenv from "dotenv";

import * as fs from "fs";
import * as path from "path";

import { exec } from "child_process";
import { task } from "hardhat/config";

/**
 * This function is used to get the enclave RPC port from a running kurtosis
 * enclave.
 * It does this by running a shell command that:
 * 1) Inspects the enclave
 * 2) Finds the el-1-geth-lighthouse container
 * 3) Finds the port mapping for the container's 8545 port
 * 4) Extracts the external port number from the mapping
 *
 * @return The enclave RPC port, or undefined if it couldn't be found
 */
async function getRPCPort(
  serviceName: string,
  servicePort: string,
): Promise<number> {
  const command =
    "kurtosis enclave inspect w3labs-contracts" +
    ` | grep -A4 ${serviceName}` +
    ` | grep '${servicePort}/'` +
    " | sed -n -e 's/^.*127\\.0\\.0\\.1:\\([0-9]*\\).*$/\\1/p'" +
    " | tr -d '\\n'";

  return new Promise<number>((resolve, _reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Failed to execute command: ${command}\n${error}`);
        resolve(-1);
      } else if (stderr) {
        console.error(`Command produced stderr: ${command}\n${stderr}`);
        resolve(-1);
      } else {
        const rpcPort = stdout.trim();
        console.log(`Found enclave RPC port: ${rpcPort}`);
        resolve(parseInt(rpcPort, 10));
      }
    });
  });
}

task("update-rpc-port", "Prints and persists the enclave RPC port").setAction(
  async () => {
    const elRpcPort = await getRPCPort("el-1-geth-lighthouse", "rpc: 8545");
    const clRpcPort =
      (await getRPCPort("cl-1-lighthouse-geth", "http: 4000")) - 1; // The RPC port is actually off by one ¯\_(ツ)_/¯

    if (elRpcPort < 0) {
      console.error(
        "Failed to get the RPC port for the execution layer; exiting",
      );
      process.exit(1);
    }

    if (clRpcPort < 0) {
      console.error(
        "Failed to get the RPC port for the consensus layer; exiting",
      );
      process.exit(1);
    }

    const envFilePath = path.join(__dirname, "..", ".env");

    if (!fs.existsSync(envFilePath)) {
      fs.writeFileSync(envFilePath, "");
    }

    const env = dotenv.parse(envFilePath);
    env.EL_RPC_PORT = elRpcPort.toString();
    env.CL_RPC_PORT = clRpcPort.toString();

    fs.writeFileSync(
      envFilePath,
      Object.keys(env)
        .map((key) => `${key}=${env[key]}`)
        .join("\n"),
    );
  },
);

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
