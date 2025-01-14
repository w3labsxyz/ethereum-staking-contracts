import { ethers } from "hardhat";
import { execSync } from "child_process";

const ETHDO_CONFIG = {
  wallet: "StakingContractsTests",
  passphrase: "test",
  mnemonic:
    "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete",
};
const CMD_CREATE_WALLET = `ethdo wallet create --wallet="${ETHDO_CONFIG.wallet}" --type="hd" --wallet-passphrase="${ETHDO_CONFIG.passphrase}" --mnemonic="${ETHDO_CONFIG.mnemonic}" --allow-weak-passphrases`;
const CMD_DELETE_WALLET = `ethdo wallet delete --wallet="${ETHDO_CONFIG.wallet}"`;
const CMD_CREATE_ACCOUNT = (index: number) =>
  `ethdo account create --account="${ETHDO_CONFIG.wallet}/Validators/${index}" --wallet-passphrase="${ETHDO_CONFIG.passphrase}" --passphrase="${ETHDO_CONFIG.passphrase}" --allow-weak-passphrases --path="m/12381/3600/${index}/0/0"`;
const CMD_CREATE_DEPOSIT_DATA = (index: number, withdrawalAddress: string) =>
  `ethdo validator depositdata --validatoraccount="${ETHDO_CONFIG.wallet}/Validators/${index}" --depositvalue="32Ether" --withdrawaladdress="${withdrawalAddress}" --passphrase="${ETHDO_CONFIG.passphrase}"`;

type EthdoDepositData = {
  name: string;
  account: string;
  pubkey: string;
  withdrawal_credentials: string;
  signature: string;
  amount: number;
  deposit_data_root: string;
  deposit_message_root: string;
  fork_version: string;
  version: number;
};

type ValidatorDepositSet = {
  amount: bigint;
  depositDataRoots: string[];
  pubkeys: string[];
  signatures: string[];
  withdrawalAddress: string;
};

function createValidatorDeposits(
  withdrawalAddress: string,
  numberOfValidators: number,
): ValidatorDepositSet {
  const depositDataRoots: string[] = [];
  const pubkeys: string[] = [];
  const signatures: string[] = [];

  try {
    execSync(CMD_CREATE_WALLET);
  } catch (error) {
    console.error(`Failed to create wallet`);
    throw error;
  }

  for (let i = 0; i < numberOfValidators; i += 1) {
    execSync(CMD_CREATE_ACCOUNT(i));
    try {
      const rawEthdoDepositData = execSync(
        CMD_CREATE_DEPOSIT_DATA(i, withdrawalAddress),
      );
      const ethdoDepositData = JSON.parse(
        rawEthdoDepositData.toString(),
      )[0] as EthdoDepositData;

      pubkeys.push(ethdoDepositData.pubkey);
      signatures.push(ethdoDepositData.signature);
      depositDataRoots.push(ethdoDepositData.deposit_data_root);
    } catch (error) {
      console.error(`Failed to create deposit data for validator ${i}`);
      execSync(CMD_DELETE_WALLET);
      throw error;
    }
  }

  try {
    execSync(CMD_DELETE_WALLET);
  } catch (error) {
    console.error(`Failed to delete wallet`);
    throw error;
  }

  return {
    amount: ethers.parseEther((32 * numberOfValidators).toString()),
    depositDataRoots,
    pubkeys,
    signatures,
    withdrawalAddress,
  };
}

export default {
  createValidatorDeposits,
};
