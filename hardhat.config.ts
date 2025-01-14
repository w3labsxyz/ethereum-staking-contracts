import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "solidity-coverage";

import "./tasks/abi";
import "./tasks/BatchDeposit";
import "./tasks/StakingRewards";
import "./tasks/enclave";
import "./tasks/native-staking";

dotenv.config();

const isTesting = process.env.HARDHAT_TESTING;
const sources = isTesting ? "./contracts" : "./contracts/lib";

const etherscanApiKey = process.env.ETHERSCAN_API_KEY;

if (etherscanApiKey === undefined) {
  console.warn("ETHERSCAN_API_KEY environment variable not set.");
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  etherscan: etherscanApiKey ? { apiKey: etherscanApiKey } : undefined,
  sourcify: {
    enabled: true,
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {
      // See its defaults
    },
    localnet: {
      url: `http://127.0.0.1:${process.env.EL_RPC_PORT}`,
      chainId: 1337,
      // These are private keys associated with prefunded test accounts created by the eth-network-package
      // https://github.com/ethpandaops/ethereum-package/blob/main/src/prelaunch_data_generator/genesis_constants/genesis_constants.star
      accounts: [
        "bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31", // 0x8943545177806ED17B9F23F0a21ee5948eCaa776
        "39725efee3fb28614de3bacaffe4cc4bd8c436257e2c8bb887c4b5c4be45e76d", // 0xE25583099BA105D9ec0A67f5Ae86D90e50036425
        "53321db7c1e331d93a11a41d16f004d7ff63972ec8ec7c25db329728ceeb1710", // 0x614561D2d143621E126e87831AEF287678B442b8
        "ab63b23eb7941c1251757e24b3d2350d2bc05c3c388d06f8fe6feafefb1e8c70", // 0xf93Ee4Cf8c6c40b329b0c0626F28333c132CF241
        "5d2344259f42259f82d2c140aa66102ba89b57b4883ee441a8b312622bd42491", // 0x802dCbE1B1A97554B4F50DB5119E37E8e7336417
        "27515f805127bebad2fb9b183508bdacb8c763da16f54e0678b16e8f28ef3fff", // 0xAe95d8DA9244C37CaC0a3e16BA966a8e852Bb6D6
        "7ff1a4c1d57e5e784d327c4c7651e952350bc271f156afb3d00d20f5ef924856", // 0x2c57d1CFC6d5f8E4182a56b4cf75421472eBAEa4
        "3a91003acaf4c21b3953d94fa4a6db694fa69e5242b2e37be05dd82761058899", // 0x741bFE4802cE1C4b5b00F9Df2F5f179A1C89171A
        "bb1d0f125b4fb2bb173c318cdead45468474ca71474e2247776b2b4c0fa2d3f5", // 0xc3913d4D8bAb4914328651C2EAE817C8b78E1f4c
        "850643a0224065ecce3882673c21f56bcf6eef86274cc21cadff15930b59fc8c", // 0x65D08a056c17Ae13370565B04cF77D2AfA1cB9FA
        "94eb3102993b41ec55c241060f47daa0f6372e2e3ad7e91612ae36c364042e44", // 0x3e95dFbBaF6B348396E6674C7871546dCC568e56
      ],
    },
    holesky: {
      url: "https://ethereum-holesky.publicnode.com",
      chainId: 17000,
    },
    mainnet: {
      url: "https://ethereum.publicnode.com",
      chainId: 1,
    },
  },
  paths: {
    sources,
  },
};

export default config;
