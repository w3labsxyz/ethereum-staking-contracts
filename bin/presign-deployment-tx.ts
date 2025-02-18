import { ethers } from "ethers";
import { readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { argv } from "process";

interface UnsignedTx {
  nonce: number;
  gasPrice: bigint;
  gasLimit: bigint;
  to: null;
  value: bigint;
  data: string;
}

const constructSignedTx = async (
  rawDeployTx: string,
  gasPrice: bigint,
  gasLimit: bigint,
): Promise<string> => {
  const tx: UnsignedTx = {
    nonce: 0,
    gasPrice,
    gasLimit,
    value: 0n,
    to: null,
    data: rawDeployTx,
  };

  const v = 27;

  const _r = 1337;
  let hexStr = _r.toString(16);
  let paddedHex = hexStr.padStart(64, "0");
  const r = "0x" + paddedHex;

  const _s = 42;
  hexStr = _s.toString(16);
  paddedHex = hexStr.padStart(64, "0");
  const s = "0x" + paddedHex;

  const serializedTx = ethers.Transaction.from({
    ...tx,
    type: 0,
    signature: {
      v,
      r,
      s,
    },
  }).serialized;

  return serializedTx;
};

const main = async (
  contractName: string,
  gasPrice: bigint,
  gasRequired: bigint,
) => {
  try {
    // Read raw transaction from file
    const rawDeployTx = readFileSync(
      join(process.cwd(), "out", `Create${contractName}.bytecode`),
      "utf8",
    ).trim();

    if (!rawDeployTx.startsWith("0x")) {
      throw new Error("Raw transaction must start with 0x");
    }

    const signedTx = await constructSignedTx(
      rawDeployTx,
      gasPrice,
      gasRequired,
    );

    // Run ec recover to predict the deployer address
    const parsed = ethers.Transaction.from(signedTx);
    const deployer = parsed.from;

    if (!deployer) return false;

    // Write signed transaction to file
    writeFileSync(
      join(process.cwd(), "out", `Create${contractName}.tx.json`),
      signedTx,
    );

    const expectedTxFee = ethers.formatEther(gasPrice * gasRequired);

    console.log(
      `Deployment for '${contractName}' successfully signed and written to out/Create${contractName}.tx.json. Please fund the 'deployer' with the expected tx fee below.`,
      {
        deployer,
        expectedTxFee,
      },
    );
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
};

// Execute if this is the main module
if (require.main === module) {
  const args = argv.slice(2);
  const gasPrice = BigInt(args[1]);
  const gasRequired = BigInt(args[2]);
  main(args[0], gasPrice, gasRequired);
}
