import { task } from "hardhat/config";

task("batch-deposit:deploy", "deploy the BatchDeposit contract")
  .addParam(
    "ethereumDepositContractAddress",
    "The address of the Ethereum deposit contract",
  )
  .setAction(async ({ ethereumDepositContractAddress }) => {
    const [_deployer] = await ethers.getSigners();

    const batchDepositContract = await ethers.deployContract(
      "BatchDeposit",
      [ethereumDepositContractAddress],
      { value: 0 },
    );
    await batchDepositContract.waitForDeployment();

    console.log(
      `BatchDeposit contract deployed to: ${batchDepositContract.target}`,
    );
  });

task(
  "batch-deposit:is-validator-available",
  "Checks if a validator is available",
)
  .addParam(
    "batchDepositContractAddress",
    "The address of a BatchDeposit contract",
  )
  .addParam("validatorPublicKey", "The public key of a validator")
  .setAction(async ({ batchDepositContractAddress, validatorPublicKey }) => {
    const [_deployer] = await ethers.getSigners();

    const batchDepositContract = await ethers.getContractAt(
      "BatchDeposit",
      batchDepositContractAddress,
    );

    const isAvailable =
      await batchDepositContract.isValidatorAvailable(validatorPublicKey);

    console.log(
      `Validator ${validatorPublicKey} is ${
        isAvailable ? "available" : "unavailable"
      }`,
    );
  });

task("batch-deposit:register-validators", "Registers multiple validators")
  .addParam(
    "batchDepositContractAddress",
    "The address of a BatchDeposit contract",
  )
  .addParam(
    "validatorPublicKeys",
    "The public keys of multiple validator (comma-separated)",
  )
  .setAction(async ({ batchDepositContractAddress, validatorPublicKeys }) => {
    const [_deployer] = await ethers.getSigners();

    const batchDepositContract = await ethers.getContractAt(
      "BatchDeposit",
      batchDepositContractAddress,
    );

    await batchDepositContract.registerValidators(
      validatorPublicKeys.split(","),
    );

    console.log(`Validators have been registered.`);
  });

task(
  "batch-deposit:batch-deposit",
  "Deposits to multiple validators in one transaction",
)
  .addParam(
    "batchDepositContractAddress",
    "The address of a BatchDeposit contract",
  )
  .addParam(
    "stakingRewardsContractAddress",
    "The address of a StakingRewards contract",
  )
  .addParam(
    "validatorPublicKeys",
    "The public keys of multiple validator (comma-separated)",
  )
  .addParam(
    "validatorSignatures",
    "The signatures of multiple validator (comma-separated)",
  )
  .addParam(
    "validatorDepositDataRoots",
    "The deposit data roots of multiple validator (comma-separated)",
  )
  .setAction(
    async ({
      batchDepositContractAddress,
      stakingRewardsContractAddress,
      validatorPublicKeys,
      validatorSignatures,
      validatorDepositDataRoots,
    }) => {
      const [_deployer] = await ethers.getSigners();

      const batchDepositContract = await ethers.getContractAt(
        "BatchDeposit",
        batchDepositContractAddress,
      );

      const publicKeys = validatorPublicKeys.split(",");
      const value = ethers.parseEther(
        (32 * publicKeys.length).toString(),
        "wei",
      );

      await batchDepositContract.batchDeposit(
        stakingRewardsContractAddress,
        publicKeys,
        validatorSignatures.split(","),
        validatorDepositDataRoots.split(","),
        { value },
      );

      console.log(
        `You have deposited ${value} wei to ${publicKeys.length} validators.`,
      );
    },
  );
