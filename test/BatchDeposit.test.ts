import { ethers } from "hardhat";
import { execSync } from "child_process";
import { expect } from "chai";

const ETHDO_CONFIG = {
  wallet: "Justfarming Development",
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
  amount: number;
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
    amount: ethers.parseEther((32 * numberOfValidators).toString(), "wei"),
    depositDataRoots,
    pubkeys,
    signatures,
    withdrawalAddress,
  };
}

describe("BatchDeposit", async () => {
  beforeEach(async function () {
    const [_deployer, justfarmingFeeWallet, customer] =
      await ethers.getSigners();

    this.ethereumStakingDepositContract = await ethers.deployContract(
      "DepositContract",
      [],
      {
        value: 0,
      },
    );

    await this.ethereumStakingDepositContract.waitForDeployment();

    this.batchDepositContract = await ethers.deployContract(
      "BatchDeposit",
      [this.ethereumStakingDepositContract.target],
      { value: 0 },
    );

    await this.batchDepositContract.waitForDeployment();

    this.stakingRewardsContract = await ethers.deployContract(
      "StakingRewards",
      [
        this.batchDepositContract.target,
        justfarmingFeeWallet.address,
        customer.address,
        1000,
      ],
    );
  });

  describe("validator registration", async () => {
    it("is allowed with valid validator public keys", async function () {
      const [owner, nobody] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(48)}`;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators([validator1Pubkey]);

      expect(
        await this.batchDepositContract
          .connect(nobody)
          .isValidatorAvailable(validator1Pubkey),
      ).to.be.true;
    });

    it("reverts if a validator is already registered", async function () {
      const [owner] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(48)}`;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators([validator1Pubkey]);

      await expect(
        this.batchDepositContract
          .connect(owner)
          .registerValidators([validator1Pubkey]),
      ).to.be.revertedWith("validator is already registered");
    });

    it("reverts if a validator public key is invalid", async function () {
      const [owner] = await ethers.getSigners();

      const validator1Pubkey = `0x${"01".repeat(47)}`;

      await expect(
        this.batchDepositContract
          .connect(owner)
          .registerValidators([validator1Pubkey]),
      ).to.be.revertedWith("public key must be 48 bytes long");
    });
  });

  describe("batch deposits", async () => {
    it("can perform multiple deposits in one tx", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      const res = await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys,
          validatorDeposits.signatures,
          validatorDeposits.depositDataRoots,
          {
            value: validatorDeposits.amount,
          },
        );

      const expectedPaymentAmount = ethers.parseEther(
        (32 * numberOfNodes).toString(),
        "wei",
      );
      await expect(res).to.changeEtherBalance(payee1, -expectedPaymentAmount);
      await expect(res).to.changeEtherBalance(
        this.batchDepositContract.target,
        0,
      );
      await expect(res).to.changeEtherBalance(
        this.ethereumStakingDepositContract.target,
        expectedPaymentAmount,
      );
      await expect(res)
        .to.emit(this.batchDepositContract, "DepositEvent")
        .withArgs(payee1.address, numberOfNodes);
    });

    it("reverts if transaction value is too low", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const amountWei = ethers.parseEther("1", "wei");
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        1,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: amountWei,
            },
          ),
      ).to.be.revertedWith(
        "the transaction amount must be equal to the number of validators to deploy multiplied by 32 ETH",
      );
    });

    it("reverts if transaction value is too high", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const amountWei = ethers.parseEther("100", "wei");
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        1,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: amountWei,
            },
          ),
      ).to.be.revertedWith(
        "the transaction amount must be equal to the number of validators to deploy multiplied by 32 ETH",
      );
    });

    it("reverts if the number of pubkeys does not match the number of signatures", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures.slice(0, 1),
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWith(
        "the number of signatures must match the number of public keys",
      );
    });

    it("reverts if the number of pubkeys does not match the number of deposit data roots", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots.slice(0, 1),
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWith(
        "the number of deposit data roots must match the number of public keys",
      );
    });

    it("reverts if a public key is invalid", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 2;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            [validatorDeposits.pubkeys[0], "0x0000"],
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWith("public key must be 48 bytes long");
    });

    it("reverts if a signature is invalid", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 2;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys);

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            [validatorDeposits.signatures[0], "0x0000"],
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWith("signature must be 96 bytes long");
    });

    it("reverts if a validator is not available", async function () {
      const [_owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 1;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await expect(
        this.batchDepositContract
          .connect(payee1)
          .batchDeposit(
            validatorDeposits.withdrawalAddress,
            validatorDeposits.pubkeys,
            validatorDeposits.signatures,
            validatorDeposits.depositDataRoots,
            {
              value: validatorDeposits.amount,
            },
          ),
      ).to.be.revertedWith("validator is not available");
    });

    it("updates the available validators after a successful deposit", async function () {
      const [owner, payee1] = await ethers.getSigners();
      const numberOfNodes = 3;
      const validatorDeposits = createValidatorDeposits(
        this.stakingRewardsContract.target,
        numberOfNodes,
      );

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys.slice(0, 1));

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.false;

      await this.batchDepositContract
        .connect(owner)
        .registerValidators(validatorDeposits.pubkeys.slice(1, 3));

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.true;

      await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys.slice(0, 1),
          validatorDeposits.signatures.slice(0, 1),
          validatorDeposits.depositDataRoots.slice(0, 1),
          {
            value: ethers.parseEther((32 * 1).toString()),
          },
        );

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.true;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.true;

      await this.batchDepositContract
        .connect(payee1)
        .batchDeposit(
          validatorDeposits.withdrawalAddress,
          validatorDeposits.pubkeys.slice(1, 3),
          validatorDeposits.signatures.slice(1, 3),
          validatorDeposits.depositDataRoots.slice(1, 3),
          {
            value: ethers.parseEther((32 * 2).toString()),
          },
        );

      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[0],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[1],
        ),
      ).to.be.false;
      expect(
        await this.batchDepositContract.isValidatorAvailable(
          validatorDeposits.pubkeys[2],
        ),
      ).to.be.false;
    });
  });

  it("can transfer ownership", async function () {
    const [owner, owner2] = await ethers.getSigners();
    expect(await this.batchDepositContract.owner()).to.equal(owner.address);
    await this.batchDepositContract.transferOwnership(owner2.address);
    expect(await this.batchDepositContract.owner()).to.equal(owner2.address);
  });
});
