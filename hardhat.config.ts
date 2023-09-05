import { exec } from "child_process";

import * as dotenv from 'dotenv';
import * as fs from 'fs';
import * as path from 'path';

import { task, HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "./tasks/BatchDeposit";
import "./tasks/StakingRewards";

dotenv.config()
const isTesting = process.env.HARDHAT_TESTING;
let sources = isTesting ? "./contracts" : "./contracts/lib";

if (process.env.RPC_PORT === undefined) {
  console.warn("RPC_PORT environment variable not set. Please run `npx hardhat update-rpc-port` to set it.");
}

/**
  * This function is used to get the enclave RPC port from a running kurtosis
  * enclave.
  * It does this by running a shell command that:
  * 1) Inspects the enclave
  * 2) Finds the el-client-0 container
  * 3) Finds the port mapping for the container's 8545 port
  * 4) Extracts the external port number from the mapping
  *
  * @return The enclave RPC port, or undefined if it couldn't be found
  */
async function getEnclaveRPCPort(): Promise<string | undefined> {
  const command =
    "kurtosis enclave inspect justfarming-contracts" +
    " | grep -A4 el-1-geth-lighthouse" +
    " | grep 'rpc: 8545/'" +
    " | sed -n -e 's/^.*-> 127\\.0\\.0\\.1:\\(.*\\)$/\\1/p'" +
    " | tr -d '\\n'";

  return new Promise<string | undefined>((resolve, _reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Failed to execute command: ${command}\n${error}`);
        resolve(undefined);
      } else if (stderr) {
        console.error(`Command produced stderr: ${command}\n${stderr}`);
        resolve(undefined);
      } else {
        const rpcPort = stdout.trim();
        console.log(`Found enclave RPC port: ${rpcPort}`);
        resolve(rpcPort);
      }
    });
  });
}

task("update-rpc-port", "Prints and persists the enclave RPC port").setAction(async () => {
  const rpcPort = await getEnclaveRPCPort();

  if (rpcPort === undefined || rpcPort === "") {
    console.error("Failed to get enclave RPC port; exiting");
    process.exit(1);
  }

  const envFilePath = path.join(__dirname, '.env');

  // Check if the .env.local file exists, create it if it doesn't
  if (!fs.existsSync(envFilePath)) {
    fs.writeFileSync(envFilePath, '');
  }

  // Load the .env.local file
  const env = dotenv.parse(envFilePath);
  // and update the desired value
  env.RPC_PORT = rpcPort;

  // Write the updated env variables to a file
  fs.writeFileSync(envFilePath, Object.keys(env).map(key => `${key}=${env[key]}`).join('\n'));

  return rpcPort;
});

const config: HardhatUserConfig = {
  solidity: "0.8.21",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      // See its defaults
    },
    localnet: {
      url: `http://127.0.0.1:${process.env.RPC_PORT}`,
      chainId: 3151908,
      // These are private keys associated with prefunded test accounts created by the eth-network-package
      // https://github.com/kurtosis-tech/eth-network-package/blob/main/src/prelaunch_data_generator/genesis_constants/genesis_constants.star
      accounts: [
        "ef5177cd0b6b21c87db5a0bf35d4084a8a57a9d6a064f86d51ac85f2b873a4e2", // 0x878705ba3f8Bc32FCf7F4CAa1A35E72AF65CF766
        "48fcc39ae27a0e8bf0274021ae6ebd8fe4a0e12623d61464c498900b28feb567", // 0x4E9A3d9D1cd2A2b2371b8b3F489aE72259886f1A
        "7988b3a148716ff800414935b305436493e1f25237a2a03e5eebc343735e2f31", // 0xdF8466f277964Bb7a0FFD819403302C34DCD530A
        "b3c409b6b0b3aa5e65ab2dc1930534608239a478106acf6f3d9178e9f9b00b35", // 0x5c613e39Fc0Ad91AfDA24587e6f52192d75FBA50
        "df9bb6de5d3dc59595bcaa676397d837ff49441d211878c024eabda2cd067c9f", // 0x375ae6107f8cC4cF34842B71C6F746a362Ad8EAc
        "7da08f856b5956d40a72968f93396f6acff17193f013e8053f6fbb6c08c194d6", // 0x1F6298457C5d76270325B724Da5d1953923a6B88
      ],
    },
  },
  paths: {
    sources: sources,
  },
};

export default config;
