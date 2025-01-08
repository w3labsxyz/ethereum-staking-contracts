import * as fs from "fs";
import * as path from "path";

import { task } from "hardhat/config";

task(
  "generate-typescript-abi",
  "Generates a TypeScript ABI definition",
).setAction(async () => {
  const contractName = "BatchDeposit";

  const artifactsDir = path.join(
    __dirname,
    "..",
    "artifacts",
    "contracts",
    "lib",
  );

  if (!fs.existsSync(artifactsDir)) {
    console.error(
      "Artifacts directory not found. Please run `npx hardhat compile` first.",
    );
    process.exit(1);
  }

  const artifactPath = path.join(
    artifactsDir,
    `${contractName}.sol`,
    `${contractName}.json`,
  );

  const outputDir = path.join(__dirname, "..", "dist");
  const outputPath = path.join(outputDir, "abi.ts");

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const { abi } = artifact;

  const tsContent = `export const abi = ${JSON.stringify(
    abi,
    null,
    2,
  )} as const;`;

  fs.writeFileSync(outputPath, tsContent);

  console.log(
    `The ABI for ${contractName} has been exported to ${outputPath}.`,
  );
});
